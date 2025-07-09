import Foundation

/// Extension to NDK for internal outbox model support
extension NDK {
    // MARK: - Internal Outbox Components

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
                tracker: outboxTracker
            )
        }
        return _publishingStrategy!
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
