import Foundation

/// Extension to NDK for outbox model support
extension NDK {
    
    // MARK: - Outbox Components
    
    /// Outbox tracker for relay information
    public var outboxTracker: NDKOutboxTracker {
        if _outboxTracker == nil {
            _outboxTracker = NDKOutboxTracker(
                ndk: self,
                blacklistedRelays: outboxConfig.blacklistedRelays
            )
        }
        return _outboxTracker!
    }
    
    /// Relay ranker for intelligent selection
    public var relayRanker: NDKRelayRanker {
        if _relayRanker == nil {
            _relayRanker = NDKRelayRanker(ndk: self, tracker: outboxTracker)
        }
        return _relayRanker!
    }
    
    /// Relay selector for choosing optimal relays
    public var relaySelector: NDKRelaySelector {
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
    public var publishingStrategy: NDKPublishingStrategy {
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
    public var fetchingStrategy: NDKFetchingStrategy {
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
    public func publishWithOutbox(
        _ event: NDKEvent,
        config: OutboxPublishConfig? = nil
    ) async throws -> PublishResult {
        // Sign event if needed
        if event.sig == nil {
            guard let signer = signer else {
                throw NDKError.signingFailed
            }
            
            if event.id == nil {
                _ = try event.generateID()
            }
            
            event.sig = try await signer.sign(event)
        }
        
        // Validate event
        try event.validate()
        
        // Store in cache if available
        if let cache = cacheAdapter as? NDKOutboxCacheAdapter {
            let selection = await relaySelector.selectRelaysForPublishing(
                event: event,
                config: config?.selectionConfig ?? .default
            )
            await cache.storeUnpublishedEvent(
                event,
                targetRelays: selection.relays,
                publishConfig: config
            )
        }
        
        // Publish using outbox strategy
        return try await publishingStrategy.publish(
            event,
            config: config ?? outboxConfig.defaultPublishConfig
        )
    }
    
    /// Retry publishing failed events
    public func retryFailedPublishes(olderThan interval: TimeInterval = 300) async {
        guard let cache = cacheAdapter as? NDKOutboxCacheAdapter else { return }
        
        let eventsToRetry = await cache.getEventsForRetry(olderThan: interval)
        
        for record in eventsToRetry {
            let config = record.publishConfig.map { publishConfig in
                OutboxPublishConfig(
                    minSuccessfulRelays: publishConfig.minSuccessfulRelays,
                    maxRetries: publishConfig.maxRetries,
                    enablePow: publishConfig.enablePow,
                    maxPowDifficulty: publishConfig.maxPowDifficulty
                )
            }
            
            _ = try? await publishingStrategy.publish(
                record.event,
                config: config ?? outboxConfig.defaultPublishConfig
            )
        }
    }
    
    // MARK: - Enhanced Fetching Methods
    
    /// Fetch events using the outbox model
    public func fetchEventsWithOutbox(
        filter: NDKFilter,
        config: OutboxFetchConfig? = nil
    ) async throws -> [NDKEvent] {
        return try await fetchingStrategy.fetchEvents(
            filter: filter,
            config: config ?? outboxConfig.defaultFetchConfig
        )
    }
    
    /// Subscribe to events using the outbox model
    public func subscribeWithOutbox(
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
    public func trackUser(_ pubkey: String) async throws {
        _ = try await outboxTracker.getRelaysFor(pubkey: pubkey)
    }
    
    /// Manually set relay information for a user
    public func setRelaysForUser(
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
    public func updateRelayPerformance(
        url: String,
        success: Bool,
        responseTime: TimeInterval? = nil
    ) async {
        await relayRanker.updateRelayPerformance(
            url,
            success: success,
            responseTime: responseTime
        )
        
        // Update in cache if available
        if let cache = cacheAdapter as? NDKOutboxCacheAdapter {
            let healthScore = await relayRanker.getRelayHealthScore(url)
            let metrics = RelayHealthMetrics(
                url: url,
                successRate: healthScore,
                avgResponseTime: responseTime ?? 0,
                lastSuccessAt: success ? Date() : nil,
                lastFailureAt: success ? nil : Date()
            )
            await cache.updateRelayHealth(url: url, health: metrics)
        }
    }
    
    // MARK: - Cleanup
    
    /// Clean up outbox resources
    public func cleanupOutbox() async {
        // Clean up tracker
        await outboxTracker.cleanupExpired()
        
        // Clean up publishing strategy
        await publishingStrategy.cleanupCompleted()
        
        // Clean up cache
        if let cache = cacheAdapter as? NDKOutboxCacheAdapter {
            await cache.cleanupPublishedEvents(olderThan: 3600)
        }
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