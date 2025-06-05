import Foundation

/// Manages fetching events using the outbox model with intelligent relay selection
public actor NDKFetchingStrategy {
    private let ndk: NDK
    private let selector: NDKRelaySelector
    private let ranker: NDKRelayRanker

    /// Active fetch operations
    private var activeFetches: [String: FetchOperation] = [:]

    /// Subscription management
    private var activeSubscriptions: [String: OutboxSubscription] = [:]

    public init(ndk: NDK, selector: NDKRelaySelector, ranker: NDKRelayRanker) {
        self.ndk = ndk
        self.selector = selector
        self.ranker = ranker
    }

    /// Fetch events using outbox model
    public func fetchEvents(
        filter: NDKFilter,
        config: OutboxFetchConfig = .default
    ) async throws -> [NDKEvent] {
        let fetchId = UUID().uuidString

        // Select source relays
        let selection = await selector.selectRelaysForFetching(
            filter: filter,
            config: config.selectionConfig
        )

        // Create fetch operation
        let operation = FetchOperation(
            id: fetchId,
            filter: filter,
            targetRelays: selection.relays,
            config: config,
            selectionMethod: selection.selectionMethod
        )

        activeFetches[fetchId] = operation
        defer { activeFetches.removeValue(forKey: fetchId) }

        // Execute fetch
        return try await executeFetch(operation: operation)
    }

    /// Subscribe to events using outbox model
    public func subscribe(
        filters: [NDKFilter],
        config: OutboxSubscriptionConfig = .default,
        eventHandler: @escaping (NDKEvent) -> Void
    ) async throws -> OutboxSubscription {
        let subscriptionId = UUID().uuidString

        // Determine relay sets for each filter
        var relaySelections: [RelaySelectionResult] = []
        for filter in filters {
            let selection = await selector.selectRelaysForFetching(
                filter: filter,
                config: config.fetchConfig.selectionConfig
            )
            relaySelections.append(selection)
        }

        // Combine relay selections
        let allRelays = Set(relaySelections.flatMap { $0.relays })

        // Create outbox subscription
        let subscription = OutboxSubscription(
            id: subscriptionId,
            filters: filters,
            targetRelays: allRelays,
            config: config,
            eventHandler: eventHandler
        )

        activeSubscriptions[subscriptionId] = subscription

        // Start subscriptions on selected relays
        try await startSubscription(subscription)

        return subscription
    }

    /// Close a subscription
    public func closeSubscription(_ subscriptionId: String) async {
        guard let subscription = activeSubscriptions[subscriptionId] else { return }

        // Close all relay subscriptions
        for (_, relaySubscription) in subscription.relaySubscriptions {
            relaySubscription.close()
        }

        subscription.status = .closed
        activeSubscriptions.removeValue(forKey: subscriptionId)
    }

    /// Get active subscriptions
    public func getActiveSubscriptions() -> [OutboxSubscription] {
        Array(activeSubscriptions.values)
    }

    // MARK: - Private Methods

    private func executeFetch(operation: FetchOperation) async throws -> [NDKEvent] {
        var collectedEvents: [String: NDKEvent] = [:] // Deduplicate by ID
        var errors: [Error] = []

        // Create concurrent fetch tasks for each relay
        await withTaskGroup(of: FetchResult.self) { group in
            for relayURL in operation.targetRelays {
                group.addTask { [weak self] in
                    await self?.fetchFromRelay(
                        relayURL: relayURL,
                        filter: operation.filter,
                        config: operation.config
                    ) ?? .failure(FetchError.cancelled)
                }
            }

            // Collect results
            var successfulRelays = 0
            for await result in group {
                switch result {
                case let .success(events, relayURL):
                    successfulRelays += 1
                    operation.updateRelayStatus(relayURL, status: .succeeded(eventCount: events.count))

                    // Deduplicate events
                    for event in events {
                        if let eventId = event.id {
                            collectedEvents[eventId] = event
                        }
                    }

                    // Update relay performance
                    await ranker.updateRelayPerformance(relayURL, success: true)

                case let .failure(error):
                    errors.append(error)
                    if let fetchError = error as? FetchError,
                       case let .relayError(relayURL, _) = fetchError
                    {
                        operation.updateRelayStatus(relayURL, status: .failed)
                        await ranker.updateRelayPerformance(relayURL, success: false)
                    }
                }

                // Check if we have enough successful relays
                if successfulRelays >= operation.config.minSuccessfulRelays {
                    // Could implement early termination here if desired
                }
            }
        }

        // Check if we met minimum relay requirement
        let successCount = operation.relayStatuses.values.filter {
            if case .succeeded = $0 { return true }
            return false
        }.count

        if successCount < operation.config.minSuccessfulRelays, !errors.isEmpty {
            throw FetchError.insufficientRelays(
                required: operation.config.minSuccessfulRelays,
                successful: successCount
            )
        }

        return Array(collectedEvents.values).sorted { $0.createdAt > $1.createdAt }
    }

    private func fetchFromRelay(
        relayURL: String,
        filter: NDKFilter,
        config: OutboxFetchConfig
    ) async -> FetchResult {
        do {
            // Get or connect to relay
            guard let relay = await getOrConnectRelay(url: relayURL) else {
                return .failure(FetchError.relayError(relayURL, "Connection failed"))
            }

            // Create subscription with timeout
            let events = try await withTimeout(seconds: config.timeoutInterval) {
                try await relay.fetchEvents(filter: filter)
            }

            return .success(events: events, relayURL: relayURL)

        } catch {
            return .failure(FetchError.relayError(relayURL, error.localizedDescription))
        }
    }

    private func startSubscription(_ subscription: OutboxSubscription) async throws {
        subscription.status = .connecting

        // Start subscriptions on each relay
        await withTaskGroup(of: Void.self) { group in
            for relayURL in subscription.targetRelays {
                group.addTask { [weak self] in
                    await self?.subscribeToRelay(
                        subscription: subscription,
                        relayURL: relayURL
                    )
                }
            }
        }

        // Update status based on successful connections
        let connectedCount = subscription.relaySubscriptions.count
        if connectedCount > 0 {
            subscription.status = .active(connectedRelays: connectedCount)
        } else {
            subscription.status = .failed
        }
    }

    private func subscribeToRelay(
        subscription: OutboxSubscription,
        relayURL: String
    ) async {
        // Get or connect to relay
        guard let relay = await getOrConnectRelay(url: relayURL) else {
            subscription.updateRelayStatus(relayURL, status: .failed)
            return
        }

        // Create relay subscription through NDK
        var options = NDKSubscriptionOptions()
        options.relays = Set([relay])

        let relaySubscription = ndk.subscribe(
            filters: subscription.filters,
            options: options
        )

        // Handle events
        relaySubscription.onEvent { [weak subscription] event in
            // Deduplicate events
            guard let subscription = subscription else { return }

            guard let eventId = event.id else { return }
            if !subscription.seenEventIds.contains(eventId) {
                subscription.seenEventIds.insert(eventId)
                subscription.eventCount += 1
                subscription.eventHandler(event)
            }
        }

        // Handle EOSE
        relaySubscription.onEOSE { [weak subscription] in
            subscription?.updateRelayStatus(relayURL, status: .eose)
        }

        subscription.relaySubscriptions[relayURL] = relaySubscription
        subscription.updateRelayStatus(relayURL, status: .active)
    }

    private func getOrConnectRelay(url: String) async -> NDKRelay? {
        // First check if already connected
        if let relay = await ndk.relayPool.relay(for: url) {
            return relay
        }

        // Try to connect
        return await ndk.relayPool.addRelay(url: url)
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw FetchError.timeout
            }

            guard let result = try await group.next() else {
                throw FetchError.timeout
            }

            group.cancelAll()
            return result
        }
    }
}

// MARK: - Supporting Types

/// Configuration for outbox fetching
public struct OutboxFetchConfig {
    public let selectionConfig: FetchingConfig
    public let minSuccessfulRelays: Int
    public let timeoutInterval: TimeInterval
    public let deduplicateEvents: Bool

    public init(
        selectionConfig: FetchingConfig = .default,
        minSuccessfulRelays: Int = 1,
        timeoutInterval: TimeInterval = 30.0,
        deduplicateEvents: Bool = true
    ) {
        self.selectionConfig = selectionConfig
        self.minSuccessfulRelays = minSuccessfulRelays
        self.timeoutInterval = timeoutInterval
        self.deduplicateEvents = deduplicateEvents
    }

    public static let `default` = OutboxFetchConfig()
}

/// Configuration for outbox subscriptions
public struct OutboxSubscriptionConfig {
    public let fetchConfig: OutboxFetchConfig
    public let autoReconnect: Bool
    public let reconnectDelay: TimeInterval

    public init(
        fetchConfig: OutboxFetchConfig = .default,
        autoReconnect: Bool = true,
        reconnectDelay: TimeInterval = 5.0
    ) {
        self.fetchConfig = fetchConfig
        self.autoReconnect = autoReconnect
        self.reconnectDelay = reconnectDelay
    }

    public static let `default` = OutboxSubscriptionConfig()
}

/// A fetch operation
private class FetchOperation {
    let id: String
    let filter: NDKFilter
    let targetRelays: Set<String>
    let config: OutboxFetchConfig
    let selectionMethod: SelectionMethod
    var relayStatuses: [String: FetchStatus] = [:]

    init(
        id: String,
        filter: NDKFilter,
        targetRelays: Set<String>,
        config: OutboxFetchConfig,
        selectionMethod: SelectionMethod
    ) {
        self.id = id
        self.filter = filter
        self.targetRelays = targetRelays
        self.config = config
        self.selectionMethod = selectionMethod
    }

    func updateRelayStatus(_ relay: String, status: FetchStatus) {
        relayStatuses[relay] = status
    }
}

/// An outbox subscription
public class OutboxSubscription {
    public let id: String
    public let filters: [NDKFilter]
    public let targetRelays: Set<String>
    public let config: OutboxSubscriptionConfig
    public let eventHandler: (NDKEvent) -> Void

    public var status: SubscriptionStatus = .pending
    public var relayStatuses: [String: SubscriptionRelayStatus] = [:]
    public var relaySubscriptions: [String: NDKSubscription] = [:]
    public var seenEventIds: Set<String> = []
    public var eventCount: Int = 0

    init(
        id: String,
        filters: [NDKFilter],
        targetRelays: Set<String>,
        config: OutboxSubscriptionConfig,
        eventHandler: @escaping (NDKEvent) -> Void
    ) {
        self.id = id
        self.filters = filters
        self.targetRelays = targetRelays
        self.config = config
        self.eventHandler = eventHandler
    }

    func updateRelayStatus(_ relay: String, status: SubscriptionRelayStatus) {
        relayStatuses[relay] = status
    }
}

/// Fetch status for a relay
private enum FetchStatus {
    case pending
    case inProgress
    case succeeded(eventCount: Int)
    case failed
}

/// Subscription status
public enum SubscriptionStatus {
    case pending
    case connecting
    case active(connectedRelays: Int)
    case failed
    case closed
}

/// Subscription relay status
public enum SubscriptionRelayStatus {
    case pending
    case connecting
    case active
    case eose // End of stored events
    case failed
    case closed
}

/// Fetch result
private enum FetchResult {
    case success(events: [NDKEvent], relayURL: String)
    case failure(Error)
}

/// Fetch errors
enum FetchError: LocalizedError {
    case relayError(String, String)
    case insufficientRelays(required: Int, successful: Int)
    case timeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .relayError(url, message):
            return "Relay error at \(url): \(message)"
        case let .insufficientRelays(required, successful):
            return "Insufficient successful relays: \(successful)/\(required)"
        case .timeout:
            return "Fetch operation timed out"
        case .cancelled:
            return "Fetch operation was cancelled"
        }
    }
}
