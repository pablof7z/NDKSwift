import Foundation

/// Manages fetching events using the outbox model with intelligent relay selection
actor NDKFetchingStrategy {
    private let ndk: NDK
    private let selector: NDKRelaySelector
    private let ranker: NDKRelayRanker

    /// Active fetch operations
    private var activeFetches: [String: FetchOperation] = [:]

    /// Subscription management
    private var activeSubscriptions: [String: OutboxSubscription] = [:]

    init(ndk: NDK, selector: NDKRelaySelector) {
        self.ndk = ndk
        self.selector = selector
        self.ranker = NDKRelayRanker(ndk: ndk, tracker: selector.tracker)
    }

    /// Create a data source for observing events using outbox model
    func observe(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .networkOnly,
        config: OutboxFetchConfig = .default,
        customStrategy: RelaySelectionStrategy? = nil
    ) async -> NDKDataSource<NDKEvent> {
        // Select source relays
        let selection: RelaySelectionResult
        if let customStrategy = customStrategy {
            let pubkey = filter.authors?.first ?? ""
            let customRelays = await customStrategy.selectRelays(pubkey)
            selection = RelaySelectionResult(
                relays: Set(customRelays),
                missingRelayInfoPubkeys: [],
                selectionMethod: .outbox
            )
        } else {
            selection = await selector.selectRelaysForFetching(
                filter: filter,
                config: config.selectionConfig
            )
        }

        // Create and return data source with selected relays
        return NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: selection.relays
        )
    }

    /// Subscribe to events using outbox model
    func subscribe(
        filters: [NDKFilter],
        config: OutboxSubscriptionConfig = .default,
        eventHandler: @escaping (NDKEvent) -> Void
    ) async throws -> OutboxSubscription {
        let subscriptionId = await sharedIDGenerator.nextSubscriptionId()

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
    func closeSubscription(_ subscriptionId: String) async {
        guard let subscription = activeSubscriptions[subscriptionId] else { return }

        // Close all relay data sources
        for _ in subscription.relayDataSources.values {
            // DataSource cleanup happens automatically in deinit
            // Just remove references
        }

        subscription.status = .closed
        activeSubscriptions.removeValue(forKey: subscriptionId)
    }

    /// Get active subscriptions
    func getActiveSubscriptions() -> [OutboxSubscription] {
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
                        let eventId = event.id
                        collectedEvents[eventId] = event
                    }

                    // Update relay performance
                    await ranker.updateRelayPerformance(relayURL, success: true)

                case let .failure(error):
                    errors.append(error)
                    if let fetchError = error as? FetchError,
                       case let .relayError(relayURL, _) = fetchError {
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

        // Sort events by timestamp
        let eventsArray = Array(collectedEvents.values)
        var eventSnapshots: [(event: NDKEvent, createdAt: Timestamp)] = []

        for event in eventsArray {
            eventSnapshots.append((event, event.createdAt))
        }

        return eventSnapshots
            .sorted { $0.createdAt > $1.createdAt }
            .map { $0.event }
    }

    private func fetchFromRelay(
        relayURL: String,
        filter: NDKFilter,
        config: OutboxFetchConfig
    ) async -> FetchResult {
        do {
            // Get or connect to relay
            guard await getOrConnectRelay(url: relayURL) != nil else {
                return .failure(FetchError.relayError(relayURL, ErrorMessageConstants.Messages.connectionFailed))
            }

            // Create data source for this specific relay with timeout
            let relaySet = Set([relayURL])
            let dataSource = NDKDataSource(
                ndk: ndk,
                filter: filter,
                maxAge: 0, // Always fresh for outbox fetching
                cachePolicy: .networkOnly, // Skip cache for relay-specific queries
                relays: relaySet
            )

            // Fetch events with timeout
            let events = try await withTimeout(seconds: config.timeoutInterval) {
                await dataSource.collect(timeout: config.timeoutInterval)
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
        let connectedCount = subscription.relayDataSources.count
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
        guard await getOrConnectRelay(url: relayURL) != nil else {
            subscription.updateRelayStatus(relayURL, status: .failed)
            return
        }

        // Create data source for this specific relay
        let relaySet = Set([relayURL])

        // Create data sources for each filter
        var dataSources: [NDKDataSource<NDKEvent>] = []
        for filter in subscription.filters {
            let dataSource = NDKDataSource(
                ndk: ndk,
                filter: filter,
                maxAge: 0, // Always fresh for outbox fetching
                cachePolicy: .cacheWithNetwork, // Use cache but also fetch from network
                relays: relaySet
            )
            dataSources.append(dataSource)
        }

        // Start async event handling
        Task { [weak subscription] in
            guard let subscription = subscription else { return }

            // Process events from all data sources
            await withTaskGroup(of: Void.self) { group in
                for dataSource in dataSources {
                    group.addTask {
                        for await event in dataSource.events {
                            // Deduplicate events
                            let eventId = event.id
                            if !subscription.seenEventIds.contains(eventId) {
                                subscription.seenEventIds.insert(eventId)
                                subscription.eventCount += 1
                                subscription.eventHandler(event)
                            }
                        }
                        // If loop completes normally, we got EOSE
                        subscription.updateRelayStatus(relayURL, status: .eose)
                    }
                }
            }
        }

        // Store data sources for cleanup later
        subscription.relayDataSources[relayURL] = dataSources.first
        subscription.updateRelayStatus(relayURL, status: .active)
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

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * TimeConstants.nanosecondsPerSecond)
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
        timeoutInterval: TimeInterval = NetworkConstants.timeoutStandardRequest,
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
        reconnectDelay: TimeInterval = NetworkConstants.timeoutSubscription
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
class OutboxSubscription {
    public let id: String
    public let filters: [NDKFilter]
    public let targetRelays: Set<String>
    public let config: OutboxSubscriptionConfig
    public let eventHandler: (NDKEvent) -> Void

    public var status: SubscriptionStatus = .pending
    public var relayStatuses: [String: SubscriptionRelayStatus] = [:]
    public var relayDataSources: [String: NDKDataSource<NDKEvent>] = [:]
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
enum SubscriptionStatus {
    case pending
    case connecting
    case active(connectedRelays: Int)
    case failed
    case closed
}

/// Subscription relay status
enum SubscriptionRelayStatus {
    case pending
    case connecting
    case active
    case eose // End of stored events
    case error
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
