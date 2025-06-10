import Foundation

/// Extension to NDK for outbox model support
public extension NDK {
    // MARK: - Outbox Components

    /// Outbox tracker for relay information
    var outboxTracker: NDKOutboxTracker {
        if _outboxTracker == nil {
            _outboxTracker = NDKOutboxTracker(
                ndk: self,
                blacklistedRelays: outboxConfig.blacklistedRelays
            )
        }
        return _outboxTracker!
    }

    /// Relay ranker for intelligent selection
    var relayRanker: NDKRelayRanker {
        if _relayRanker == nil {
            _relayRanker = NDKRelayRanker(ndk: self, tracker: outboxTracker)
        }
        return _relayRanker!
    }

    /// Relay selector for choosing optimal relays
    var relaySelector: NDKRelaySelector {
        if _relaySelector == nil {
            _relaySelector = NDKRelaySelector(
                ndk: self,
                tracker: outboxTracker,
                ranker: relayRanker
            )
        }
        return _relaySelector!
    }

    /// Publishing strategy for outbox model
    var publishingStrategy: NDKPublishingStrategy {
        if _publishingStrategy == nil {
            _publishingStrategy = NDKPublishingStrategy(
                ndk: self,
                selector: relaySelector,
                ranker: relayRanker
            )
        }
        return _publishingStrategy!
    }

    /// Fetching strategy for outbox model
    var fetchingStrategy: NDKFetchingStrategy {
        if _fetchingStrategy == nil {
            _fetchingStrategy = NDKFetchingStrategy(
                ndk: self,
                selector: relaySelector,
                ranker: relayRanker
            )
        }
        return _fetchingStrategy!
    }

    // MARK: - Outbox Configuration

    // MARK: - Enhanced Publishing Methods

    /// Publish an event using the outbox model
    @discardableResult
    func publishWithOutbox(
        _ event: NDKEvent,
        config: OutboxPublishConfig? = nil
    ) async throws -> PublishResult {
        // Sign event if needed
        if event.sig == nil {
            guard let signer = signer else {
                throw NDKError.crypto("no_signer", "No signer configured")
            }

            if event.id == nil {
                _ = try event.generateID()
            }

            event.sig = try await signer.sign(event)
        }

        // Validate event
        try event.validate()

        // Store in cache if available
        if let cache = cache {
            try? await cache.saveEvent(event)
        }

        // Publish using outbox strategy
        return try await publishingStrategy.publish(
            event,
            config: config ?? outboxConfig.defaultPublishConfig
        )
    }

    /// Retry publishing failed events
    func retryFailedPublishes(olderThan interval: TimeInterval = 300) async {
        // Note: Retry logic needs to be implemented with event tracking
        // For now, this is a no-op as the new cache doesn't track unpublished events yet
    }

    // MARK: - Enhanced Fetching Methods

    /// Fetch events using the outbox model
    func fetchEventsWithOutbox(
        filter: NDKFilter,
        config: OutboxFetchConfig? = nil
    ) async throws -> [NDKEvent] {
        return try await fetchingStrategy.fetchEvents(
            filter: filter,
            config: config ?? outboxConfig.defaultFetchConfig
        )
    }

    /// Subscribe to events using the outbox model
    func subscribeWithOutbox(
        filters: [NDKFilter],
        config: OutboxSubscriptionConfig? = nil,
        eventHandler: @escaping (NDKEvent) -> Void
    ) async throws -> OutboxSubscription {
        return try await fetchingStrategy.subscribe(
            filters: filters,
            config: config ?? outboxConfig.defaultSubscriptionConfig,
            eventHandler: eventHandler
        )
    }

    // MARK: - Relay Information Management

    /// Fetch and cache relay information for a user
    func trackUser(_ pubkey: String) async throws {
        _ = try await outboxTracker.getRelaysFor(pubkey: pubkey)
    }

    /// Manually set relay information for a user
    func setRelaysForUser(
        pubkey: String,
        readRelays: Set<String>,
        writeRelays: Set<String>
    ) async {
        await outboxTracker.track(
            pubkey: pubkey,
            readRelays: readRelays,
            writeRelays: writeRelays,
            source: .manual
        )
    }

    /// Update relay health metrics
    func updateRelayPerformance(
        url: String,
        success: Bool,
        responseTime: TimeInterval? = nil
    ) async {
        await relayRanker.updateRelayPerformance(
            url,
            success: success,
            responseTime: responseTime
        )

        // Note: Relay health metrics are tracked by the ranker and tracker components
    }

    // MARK: - Cleanup

    /// Clean up outbox resources
    func cleanupOutbox() async {
        // Clean up tracker
        await outboxTracker.cleanupExpired()

        // Clean up publishing strategy
        await publishingStrategy.cleanupCompleted()

        // Note: Cache cleanup for published events can be handled by the cache's TTL mechanisms
    }
}

/// NDK Outbox Configuration
public struct NDKOutboxConfig {
    /// Relays to blacklist from outbox selection
    public let blacklistedRelays: Set<String>

    /// Default publish configuration
    public let defaultPublishConfig: OutboxPublishConfig

    /// Default fetch configuration
    public let defaultFetchConfig: OutboxFetchConfig

    /// Default subscription configuration
    public let defaultSubscriptionConfig: OutboxSubscriptionConfig

    /// Whether to automatically retry failed publishes
    public let autoRetryFailedPublishes: Bool

    /// Interval for automatic retry
    public let retryInterval: TimeInterval

    public init(
        blacklistedRelays: Set<String> = [],
        defaultPublishConfig: OutboxPublishConfig = .default,
        defaultFetchConfig: OutboxFetchConfig = .default,
        defaultSubscriptionConfig: OutboxSubscriptionConfig = .default,
        autoRetryFailedPublishes: Bool = true,
        retryInterval: TimeInterval = 300
    ) {
        self.blacklistedRelays = blacklistedRelays
        self.defaultPublishConfig = defaultPublishConfig
        self.defaultFetchConfig = defaultFetchConfig
        self.defaultSubscriptionConfig = defaultSubscriptionConfig
        self.autoRetryFailedPublishes = autoRetryFailedPublishes
        self.retryInterval = retryInterval
    }

    public static let `default` = NDKOutboxConfig()
}
