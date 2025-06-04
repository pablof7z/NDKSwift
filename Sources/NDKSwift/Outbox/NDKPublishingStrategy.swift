import Foundation

/// Manages publishing events using the outbox model with retry logic and status tracking
public actor NDKPublishingStrategy {
    private let ndk: NDK
    private let selector: NDKRelaySelector
    private let ranker: NDKRelayRanker
    
    /// Active outbox items being published
    private var outboxItems: [String: OutboxItem] = [:]
    
    /// Queue of items waiting to be published
    private var publishQueue: [OutboxItem] = []
    
    /// Active publishing tasks
    private var activeTasks: [String: Task<Void, Never>] = [:]
    
    public init(ndk: NDK, selector: NDKRelaySelector, ranker: NDKRelayRanker) {
        self.ndk = ndk
        self.selector = selector
        self.ranker = ranker
    }
    
    /// Publish an event using the outbox model
    @discardableResult
    public func publish(
        _ event: NDKEvent,
        config: OutboxPublishConfig = .default
    ) async throws -> PublishResult {
        // Select target relays
        let selection = await selector.selectRelaysForPublishing(
            event: event,
            config: config.selectionConfig
        )
        
        // Create outbox item
        let item = OutboxItem(
            event: event,
            targetRelays: selection.relays,
            config: config,
            selectionMethod: selection.selectionMethod
        )
        
        // Store in outbox
        if let eventId = event.id {
            outboxItems[eventId] = item
        }
        
        // Start publishing
        let task = Task {
            await publishOutboxItem(item)
        }
        if let eventId = event.id {
            activeTasks[eventId] = task
        }
        
        // Wait for initial results if not background
        if !config.publishInBackground {
            await task.value
        }
        
        // Return current status
        if let eventId = event.id {
            return getPublishResult(for: eventId)
        } else {
            return PublishResult(
                eventId: "",
                overallStatus: .pending,
                relayStatuses: [:],
                successCount: 0,
                failureCount: 0,
                powDifficulty: 0
            )
        }
    }
    
    /// Get the current status of a publishing operation
    public func getPublishResult(for eventId: String) -> PublishResult {
        guard let item = outboxItems[eventId] else {
            return PublishResult(
                eventId: eventId,
                overallStatus: .unknown,
                relayStatuses: [:],
                successCount: 0,
                failureCount: 0,
                powDifficulty: 0
            )
        }
        
        return PublishResult(
            eventId: eventId,
            overallStatus: item.overallStatus,
            relayStatuses: item.relayStatuses,
            successCount: item.successCount,
            failureCount: item.failureCount,
            powDifficulty: item.currentPowDifficulty
        )
    }
    
    /// Cancel publishing for an event
    public func cancelPublish(eventId: String) {
        activeTasks[eventId]?.cancel()
        activeTasks.removeValue(forKey: eventId)
        outboxItems[eventId]?.overallStatus = .cancelled
    }
    
    /// Get all pending outbox items
    public func getPendingItems() -> [OutboxItem] {
        outboxItems.values.filter { item in
            item.overallStatus == .pending || item.overallStatus == .inProgress
        }
    }
    
    /// Clean up completed items older than specified age
    public func cleanupCompleted(olderThan age: TimeInterval = 3600) {
        let cutoffDate = Date().addingTimeInterval(-age)
        
        outboxItems = outboxItems.filter { (eventId, item) in
            // Keep if not completed or recent
            if item.overallStatus != .succeeded && item.overallStatus != .failed {
                return true
            }
            return item.lastUpdated > cutoffDate
        }
    }
    
    // MARK: - Private Methods
    
    private func publishOutboxItem(_ item: OutboxItem) async {
        item.overallStatus = .inProgress
        
        // Create tasks for each relay
        await withTaskGroup(of: Void.self) { group in
            for relayURL in item.targetRelays {
                group.addTask { [weak self] in
                    await self?.publishToRelay(item: item, relayURL: relayURL)
                }
            }
        }
        
        // Update overall status
        updateOverallStatus(for: item)
    }
    
    private func publishToRelay(item: OutboxItem, relayURL: String) async {
        var attempts = 0
        var backoffInterval: TimeInterval = item.config.initialBackoffInterval
        
        while attempts < item.config.maxRetries {
            attempts += 1
            
            // Check if cancelled
            if item.overallStatus == .cancelled {
                return
            }
            
            // Get or establish connection
            guard let relay = await getOrConnectRelay(url: relayURL) else {
                item.updateRelayStatus(relayURL, status: .failed(.connectionFailed))
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
                item.updateRelayStatus(relayURL, status: .succeeded)
                await ranker.updateRelayPerformance(
                    relayURL,
                    success: true,
                    responseTime: responseTime
                )
                updateOverallStatus(for: item)
                return
                
            case .requiresPow(let difficulty):
                // Handle POW requirement
                if await handlePowRequirement(item: item, difficulty: difficulty) {
                    // Retry with new event (POW added)
                    attempts = 0 // Reset attempts for POW retry
                    continue
                } else {
                    item.updateRelayStatus(relayURL, status: .failed(.powGenerationFailed))
                    return
                }
                
            case .rateLimited:
                item.updateRelayStatus(relayURL, status: .rateLimited)
                // Exponential backoff
                try? await Task.sleep(nanoseconds: UInt64(backoffInterval * 1_000_000_000))
                backoffInterval *= item.config.backoffMultiplier
                
            case .authRequired:
                // Attempt NIP-42 auth
                if await handleAuthChallenge(relay: relay) {
                    // Retry after auth
                    continue
                } else {
                    item.updateRelayStatus(relayURL, status: .failed(.authFailed))
                    return
                }
                
            case .permanentFailure(let reason):
                item.updateRelayStatus(relayURL, status: .failed(reason))
                await ranker.updateRelayPerformance(relayURL, success: false)
                return
                
            case .temporaryFailure:
                if attempts < item.config.maxRetries {
                    item.updateRelayStatus(relayURL, status: .retrying(attempt: attempts))
                    try? await Task.sleep(nanoseconds: UInt64(backoffInterval * 1_000_000_000))
                    backoffInterval *= item.config.backoffMultiplier
                } else {
                    item.updateRelayStatus(relayURL, status: .failed(.maxRetriesExceeded))
                    await ranker.updateRelayPerformance(relayURL, success: false)
                    return
                }
            }
        }
    }
    
    private func attemptPublishToRelay(
        event: NDKEvent,
        relay: NDKRelay,
        item: OutboxItem
    ) async -> PublishAttemptResult {
        do {
            // Send event
            let response = try await relay.publish(event)
            
            // Parse response
            if response.success {
                return .success
            } else if let message = response.message {
                if message.contains("pow:") {
                    // Extract difficulty
                    let difficulty = extractPowDifficulty(from: message) ?? 20
                    return .requiresPow(difficulty: difficulty)
                } else if message.contains("rate") {
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
    
    private func handlePowRequirement(item: OutboxItem, difficulty: Int) async -> Bool {
        // Update required difficulty
        item.currentPowDifficulty = max(item.currentPowDifficulty ?? 0, difficulty)
        
        // Check if we should generate POW
        guard item.config.enablePow,
              let maxDifficulty = item.config.maxPowDifficulty,
              difficulty <= maxDifficulty else {
            return false
        }
        
        // Generate POW
        // TODO: Implement POW generation when available
        // For now, we can't generate POW, so return false
        return false
        
        /* Future implementation:
        do {
            var mutableEvent = item.event
            try await mutableEvent.generatePow(targetDifficulty: difficulty)
            
            // Update the event in the outbox item
            item.event = mutableEvent
            
            // Reset all relay statuses to pending since event ID changed
            for relayURL in item.targetRelays {
                item.updateRelayStatus(relayURL, status: .pending)
            }
            
            return true
        } catch {
            return false
        }
        */
    }
    
    private func handleAuthChallenge(relay: NDKRelay) async -> Bool {
        // This would implement NIP-42 auth
        // For now, returning false as auth implementation is relay-specific
        return false
    }
    
    private func getOrConnectRelay(url: String) async -> NDKRelay? {
        // First check if already connected
        if let relay = ndk.relayPool.relay(for: url) {
            return relay
        }
        
        // Try to connect
        return await ndk.relayPool.addRelay(url: url)
    }
    
    private func updateOverallStatus(for item: OutboxItem) {
        let successCount = item.relayStatuses.values.filter { $0 == .succeeded }.count
        let failureCount = item.relayStatuses.values.filter { 
            if case .failed = $0 { return true }
            return false
        }.count
        let pendingCount = item.relayStatuses.values.filter { 
            $0 == .pending || $0 == .inProgress
        }.count
        
        item.successCount = successCount
        item.failureCount = failureCount
        
        if successCount >= item.config.minSuccessfulRelays {
            item.overallStatus = .succeeded
        } else if pendingCount == 0 && successCount < item.config.minSuccessfulRelays {
            item.overallStatus = .failed
        }
        
        item.lastUpdated = Date()
    }
    
    private func extractPowDifficulty(from message: String) -> Int? {
        // Extract difficulty from message like "pow: difficulty 20 required"
        let pattern = #"pow:.*?(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: message,
                range: NSRange(message.startIndex..., in: message)
              ),
              let range = Range(match.range(at: 1), in: message) else {
            return nil
        }
        
        return Int(message[range])
    }
}

// MARK: - Supporting Types

/// Configuration for outbox publishing
public struct OutboxPublishConfig {
    public let selectionConfig: PublishingConfig
    public let minSuccessfulRelays: Int
    public let maxRetries: Int
    public let initialBackoffInterval: TimeInterval
    public let backoffMultiplier: Double
    public let publishInBackground: Bool
    public let enablePow: Bool
    public let maxPowDifficulty: Int?
    
    public init(
        selectionConfig: PublishingConfig = .default,
        minSuccessfulRelays: Int = 1,
        maxRetries: Int = 3,
        initialBackoffInterval: TimeInterval = 1.0,
        backoffMultiplier: Double = 2.0,
        publishInBackground: Bool = false,
        enablePow: Bool = true,
        maxPowDifficulty: Int? = 24
    ) {
        self.selectionConfig = selectionConfig
        self.minSuccessfulRelays = minSuccessfulRelays
        self.maxRetries = maxRetries
        self.initialBackoffInterval = initialBackoffInterval
        self.backoffMultiplier = backoffMultiplier
        self.publishInBackground = publishInBackground
        self.enablePow = enablePow
        self.maxPowDifficulty = maxPowDifficulty
    }
    
    public static let `default` = OutboxPublishConfig()
}

/// An item in the outbox queue
public class OutboxItem {
    public var event: NDKEvent
    public let targetRelays: Set<String>
    public let config: OutboxPublishConfig
    public let selectionMethod: SelectionMethod
    public var relayStatuses: [String: RelayPublishStatus] = [:]
    public var overallStatus: PublishStatus = .pending
    public var successCount: Int = 0
    public var failureCount: Int = 0
    public var currentPowDifficulty: Int?
    public var lastUpdated: Date = Date()
    
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
    
    func updateRelayStatus(_ relay: String, status: RelayPublishStatus) {
        relayStatuses[relay] = status
        lastUpdated = Date()
        
        // Also update the event's relay status
        event.updatePublishStatus(relay: relay, status: status)
    }
}

/// Overall publish status
public enum PublishStatus: String, Codable {
    case pending
    case inProgress
    case succeeded
    case failed
    case cancelled
    case unknown
}

/// Status of publishing to a specific relay
public enum RelayPublishStatus: Equatable, Codable {
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
        case .failed(let reason):
            try container.encode("failed", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .rateLimited:
            try container.encode("rateLimited", forKey: .type)
        case .retrying(let attempt):
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
public enum PublishFailureReason: Equatable, Codable {
    case connectionFailed
    case authFailed
    case invalid(String)
    case maxRetriesExceeded
    case powGenerationFailed
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
        case .invalid(let message):
            try container.encode("invalid", forKey: .type)
            try container.encode(message, forKey: .message)
        case .maxRetriesExceeded:
            try container.encode("maxRetriesExceeded", forKey: .type)
        case .powGenerationFailed:
            try container.encode("powGenerationFailed", forKey: .type)
        case .custom(let message):
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
        case "powGenerationFailed":
            self = .powGenerationFailed
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
    case requiresPow(difficulty: Int)
    case rateLimited
    case authRequired
    case permanentFailure(reason: PublishFailureReason)
    case temporaryFailure
}

/// Result of a publish operation
public struct PublishResult {
    public let eventId: String
    public let overallStatus: PublishStatus
    public let relayStatuses: [String: RelayPublishStatus]
    public let successCount: Int
    public let failureCount: Int
    public let powDifficulty: Int?
    
    public var isComplete: Bool {
        overallStatus == .succeeded || overallStatus == .failed || overallStatus == .cancelled
    }
}