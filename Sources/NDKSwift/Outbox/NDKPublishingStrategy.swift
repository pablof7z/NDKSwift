import Foundation

/// Manages publishing events using the outbox model with retry logic and status tracking
actor NDKPublishingStrategy {
    private let ndk: NDK
    private let selector: NDKRelaySelector
    private let ranker: NDKRelayRanker

    /// Active outbox items being published
    private var outboxItems: [String: OutboxItem] = [:]

    /// Queue of items waiting to be published
    private var publishQueue: [OutboxItem] = []

    /// Active publishing tasks
    private var activeTasks: [String: Task<Void, Never>] = [:]

    init(ndk: NDK, selector: NDKRelaySelector, tracker: NDKOutboxTracker) {
        self.ndk = ndk
        self.selector = selector
        self.ranker = NDKRelayRanker(ndk: ndk, tracker: tracker)
    }

    /// Publish an event using the outbox model
    @discardableResult
    func publish(
        _ event: NDKEvent,
        config: OutboxPublishConfig = .default,
        customStrategy: RelaySelectionStrategy? = nil
    ) async throws -> PublishResult {
        // Select target relays
        let selection: RelaySelectionResult
        if let customStrategy = customStrategy {
            let customRelays = await customStrategy.selectRelays(event.pubkey)
            selection = RelaySelectionResult(
                relays: Set(customRelays),
                missingRelayInfoPubkeys: [],
                selectionMethod: .outbox
            )
        } else {
            selection = await selector.selectRelaysForPublishing(
                event: event,
                config: config.selectionConfig
            )
        }

        // Create outbox item
        let item = OutboxItem(
            event: event,
            targetRelays: selection.relays,
            config: config,
            selectionMethod: selection.selectionMethod
        )

        // Store in outbox
        let eventId = event.id
        outboxItems[eventId] = item

        // Start publishing
        let task = Task {
            await publishOutboxItem(item)
        }
        activeTasks[eventId] = task

        // Wait for initial results if not background
        if !config.publishInBackground {
            await task.value
        }

        // Return current status
        return await getPublishResult(for: eventId)
    }

    /// Get the current status of a publishing operation
    func getPublishResult(for eventId: String) async -> PublishResult {
        guard let item = outboxItems[eventId] else {
            return PublishResult(
                eventId: eventId,
                overallStatus: .unknown,
                relayStatuses: [:],
                successCount: 0,
                failureCount: 0
            )
        }

        return PublishResult(
            eventId: eventId,
            overallStatus: await item.overallStatus,
            relayStatuses: await item.relayStatuses,
            successCount: await item.successCount,
            failureCount: await item.failureCount
        )
    }

    /// Cancel publishing for an event
    func cancelPublish(eventId: String) async {
        activeTasks[eventId]?.cancel()
        activeTasks.removeValue(forKey: eventId)
        if let item = outboxItems[eventId] {
            await item.setOverallStatus(.cancelled)
        }
    }

    /// Get all pending outbox items
    func getPendingItems() async -> [OutboxItem] {
        var pendingItems: [OutboxItem] = []
        for item in outboxItems.values {
            let status = await item.getOverallStatus()
            if status == .pending || status == .inProgress {
                pendingItems.append(item)
            }
        }
        return pendingItems
    }

    /// Clean up completed items older than specified age
    func cleanupCompleted(olderThan age: TimeInterval = 3600) async {
        let cutoffDate = Date().addingTimeInterval(-age)

        var itemsToKeep: [String: OutboxItem] = [:]
        for (key, item) in outboxItems {
            let status = await item.getOverallStatus()
            let lastUpdated = await item.getLastUpdated()
            
            // Keep if not completed or recent
            if status != .succeeded && status != .failed {
                itemsToKeep[key] = item
            } else if lastUpdated > cutoffDate {
                itemsToKeep[key] = item
            }
        }
        outboxItems = itemsToKeep
    }

    // MARK: - Private Methods

    private func publishOutboxItem(_ item: OutboxItem) async {
        await item.setOverallStatus(.inProgress)

        // Create tasks for each relay
        await withTaskGroup(of: Void.self) { group in
            for relayURL in item.targetRelays {
                group.addTask { [weak self] in
                    await self?.publishToRelay(item: item, relayURL: relayURL)
                }
            }
        }

        // Update overall status
        await updateOverallStatus(for: item)
    }

    private func publishToRelay(item: OutboxItem, relayURL: String) async {
        var attempts = 0
        let config = item.config
        var backoffInterval: TimeInterval = config.initialBackoffInterval

        while attempts < config.maxRetries {
            attempts += 1

            // Check if cancelled
            if await item.getOverallStatus() == .cancelled {
                return
            }

            // Get or establish connection
            guard let relay = await getOrConnectRelay(url: relayURL) else {
                await item.updateRelayStatus(relayURL, status: .failed(.connectionFailed))
                await ranker.updateRelayPerformance(relayURL, success: false)
                return
            }

            // Attempt to publish
            let startTime = Date()
            let result = await attemptPublishToRelay(
                event: item.event,
                relay: relay,
                item: item
            )
            let responseTime = Date().timeIntervalSince(startTime)

            switch result {
            case .success:
                await item.updateRelayStatus(relayURL, status: .succeeded)
                await ranker.updateRelayPerformance(
                    relayURL,
                    success: true,
                    responseTime: responseTime
                )
                await updateOverallStatus(for: item)
                return


            case .rateLimited:
                await item.updateRelayStatus(relayURL, status: .rateLimited)
                // Exponential backoff
                try? await Task.sleep(nanoseconds: UInt64(backoffInterval) * TimeConstants.nanosecondsPerSecond)
                backoffInterval *= config.backoffMultiplier

            case .authRequired:
                // Attempt NIP-42 auth
                if await handleAuthChallenge(relay: relay) {
                    // Retry after auth
                    continue
                } else {
                    await item.updateRelayStatus(relayURL, status: .failed(.authFailed))
                    return
                }

            case let .permanentFailure(reason):
                await item.updateRelayStatus(relayURL, status: .failed(reason))
                await ranker.updateRelayPerformance(relayURL, success: false)
                return

            case .temporaryFailure:
                if attempts < config.maxRetries {
                    await item.updateRelayStatus(relayURL, status: .retrying(attempt: attempts))
                    try? await Task.sleep(nanoseconds: UInt64(backoffInterval) * TimeConstants.nanosecondsPerSecond)
                    backoffInterval *= config.backoffMultiplier
                } else {
                    await item.updateRelayStatus(relayURL, status: .failed(.maxRetriesExceeded))
                    await ranker.updateRelayPerformance(relayURL, success: false)
                    return
                }
            }
        }
    }

    private func attemptPublishToRelay(
        event: NDKEvent,
        relay: NDKRelay,
        item _: OutboxItem
    ) async -> PublishAttemptResult {
        do {
            // Send event
            let response = try await relay.publish(event)

            // Parse response
            if response.success {
                return .success
            } else if let message = response.message {
                if message.contains("rate") {
                    return .rateLimited
                } else if message.contains("auth") {
                    return .authRequired
                } else if message.contains("invalid") || message.contains("error") {
                    return .permanentFailure(reason: .invalid(message))
                }
            }
            return .temporaryFailure

        } catch {
            // Network or other errors
            return .temporaryFailure
        }
    }


    private func handleAuthChallenge(relay _: NDKRelay) async -> Bool {
        // This would implement NIP-42 auth
        // For now, returning false as auth implementation is relay-specific
        return false
    }

    private func getOrConnectRelay(url: String) async -> NDKRelay? {
        let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        
        // First check if already connected
        if let relay = await ndk.pool.getRelay(for: normalizedUrl) {
            return relay
        }

        // Try to connect
        let relay = await ndk.pool.addRelay(normalizedUrl)
        relay.ndk = ndk
        try? await relay.connect()
        return relay
    }

    private func updateOverallStatus(for item: OutboxItem) async {
        let relayStatuses = await item.relayStatuses
        let successCount = relayStatuses.values.filter { $0 == .succeeded }.count
        let failureCount = relayStatuses.values.filter {
            if case .failed = $0 { return true }
            return false
        }.count
        let pendingCount = relayStatuses.values.filter {
            $0 == .pending || $0 == .inProgress
        }.count

        await item.setSuccessCount(successCount)
        await item.setFailureCount(failureCount)

        let config = item.config
        if successCount >= config.minSuccessfulRelays {
            await item.setOverallStatus(.succeeded)
        } else if pendingCount == 0, successCount < config.minSuccessfulRelays {
            await item.setOverallStatus(.failed)
        }

        await item.setLastUpdated(Date())
    }

}

// MARK: - Supporting Types

/// Configuration for outbox publishing
public struct OutboxPublishConfig: Sendable {
    public let selectionConfig: PublishingConfig
    public let minSuccessfulRelays: Int
    public let maxRetries: Int
    public let initialBackoffInterval: TimeInterval
    public let backoffMultiplier: Double
    public let publishInBackground: Bool

    public init(
        selectionConfig: PublishingConfig = .default,
        minSuccessfulRelays: Int = 1,
        maxRetries: Int = 3,
        initialBackoffInterval: TimeInterval = 1.0,
        backoffMultiplier: Double = 2.0,
        publishInBackground: Bool = false
    ) {
        self.selectionConfig = selectionConfig
        self.minSuccessfulRelays = minSuccessfulRelays
        self.maxRetries = maxRetries
        self.initialBackoffInterval = initialBackoffInterval
        self.backoffMultiplier = backoffMultiplier
        self.publishInBackground = publishInBackground
    }

    public static let `default` = OutboxPublishConfig()
}

/// An item in the outbox queue
actor OutboxItem {
    public let event: NDKEvent
    public let targetRelays: Set<String>
    public let config: OutboxPublishConfig
    public let selectionMethod: SelectionMethod
    public var relayStatuses: [String: RelayPublishStatus] = [:]
    public var overallStatus: PublishStatus = .pending
    public var successCount: Int = 0
    public var failureCount: Int = 0
    public var lastUpdated: Date = .init()

    init(
        event: NDKEvent,
        targetRelays: Set<String>,
        config: OutboxPublishConfig,
        selectionMethod: SelectionMethod
    ) {
        self.event = event
        self.targetRelays = targetRelays
        self.config = config
        self.selectionMethod = selectionMethod

        // Initialize all relays as pending
        for relay in targetRelays {
            relayStatuses[relay] = .pending
        }
    }

    func updateRelayStatus(_ relay: String, status: RelayPublishStatus) async {
        relayStatuses[relay] = status
        lastUpdated = Date()

        // Also update the event's relay status
        event.updatePublishStatus(relay: relay, status: status)
    }
    
    func setOverallStatus(_ status: PublishStatus) {
        overallStatus = status
    }
    
    func getOverallStatus() -> PublishStatus {
        return overallStatus
    }
    
    func getLastUpdated() -> Date {
        return lastUpdated
    }
    
    func incrementSuccessCount() {
        successCount += 1
    }
    
    func incrementFailureCount() {
        failureCount += 1
    }
    
    func setSuccessCount(_ count: Int) {
        successCount = count
    }
    
    func setFailureCount(_ count: Int) {
        failureCount = count
    }
    
    
    func setLastUpdated(_ date: Date) {
        lastUpdated = date
    }
}

/// Overall publish status
public enum PublishStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case succeeded
    case failed
    case cancelled
    case unknown
}

/// Status of publishing to a specific relay
public enum RelayPublishStatus: Equatable, Codable, Sendable {
    case pending
    case inProgress
    case succeeded
    case failed(PublishFailureReason)
    case rateLimited
    case retrying(attempt: Int)

    enum CodingKeys: String, CodingKey {
        case type
        case reason
        case attempt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .pending:
            try container.encode("pending", forKey: .type)
        case .inProgress:
            try container.encode("inProgress", forKey: .type)
        case .succeeded:
            try container.encode("succeeded", forKey: .type)
        case let .failed(reason):
            try container.encode("failed", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .rateLimited:
            try container.encode("rateLimited", forKey: .type)
        case let .retrying(attempt):
            try container.encode("retrying", forKey: .type)
            try container.encode(attempt, forKey: .attempt)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "pending":
            self = .pending
        case "inProgress":
            self = .inProgress
        case "succeeded":
            self = .succeeded
        case "failed":
            let reason = try container.decode(PublishFailureReason.self, forKey: .reason)
            self = .failed(reason)
        case "rateLimited":
            self = .rateLimited
        case "retrying":
            let attempt = try container.decode(Int.self, forKey: .attempt)
            self = .retrying(attempt: attempt)
        default:
            self = .pending
        }
    }
}

/// Reason for publish failure
public enum PublishFailureReason: Equatable, Codable, Sendable {
    case connectionFailed
    case authFailed
    case invalid(String)
    case maxRetriesExceeded
    case custom(String)

    enum CodingKeys: String, CodingKey {
        case type
        case message
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .connectionFailed:
            try container.encode("connectionFailed", forKey: .type)
        case .authFailed:
            try container.encode("authFailed", forKey: .type)
        case let .invalid(message):
            try container.encode("invalid", forKey: .type)
            try container.encode(message, forKey: .message)
        case .maxRetriesExceeded:
            try container.encode("maxRetriesExceeded", forKey: .type)
        case let .custom(message):
            try container.encode("custom", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "connectionFailed":
            self = .connectionFailed
        case "authFailed":
            self = .authFailed
        case "invalid":
            let message = try container.decode(String.self, forKey: .message)
            self = .invalid(message)
        case "maxRetriesExceeded":
            self = .maxRetriesExceeded
        case "custom":
            let message = try container.decode(String.self, forKey: .message)
            self = .custom(message)
        default:
            self = .connectionFailed
        }
    }
}

/// Result of a publish attempt
private enum PublishAttemptResult {
    case success
    case rateLimited
    case authRequired
    case permanentFailure(reason: PublishFailureReason)
    case temporaryFailure
}

/// Result of a publish operation
public struct PublishResult: Sendable {
    public let eventId: String
    public let overallStatus: PublishStatus
    public let relayStatuses: [String: RelayPublishStatus]
    public let successCount: Int
    public let failureCount: Int

    public var isComplete: Bool {
        overallStatus == .succeeded || overallStatus == .failed || overallStatus == .cancelled
    }
    
    public var successfulRelayUrls: Set<String> {
        Set(relayStatuses.compactMap { url, status in
            if case .succeeded = status {
                return url
            }
            return nil
        })
    }
}
