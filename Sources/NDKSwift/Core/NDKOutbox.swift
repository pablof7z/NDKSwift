import Foundation

/// Extension to NDK for internal outbox model support
extension NDK {
    // MARK: - Internal Outbox Components

    /// Outbox tracker for relay information
    var outboxTracker: NDKOutboxTracker {
        lazyInit(&_outboxTracker) {
            NDKOutboxTracker(
                ndk: self,
                blacklistedRelays: outboxConfig.blacklistedRelays
            )
        }
    }

    /// Relay ranker for intelligent selection
    var relayRanker: NDKRelayRanker {
        lazyInit(&_relayRanker) {
            NDKRelayRanker(ndk: self, tracker: outboxTracker)
        }
    }


    /// Publishing strategy for outbox model
    var publishingStrategy: NDKPublishingStrategy {
        lazyInit(&_publishingStrategy) {
            NDKPublishingStrategy(
                ndk: self,
                selector: relaySelector,
                tracker: outboxTracker
            )
        }
    }

}

/// NDK Outbox Configuration
public struct NDKOutboxConfig {
    /// Relays to blacklist from outbox selection
    public let blacklistedRelays: Set<String>

    /// Dedicated relays for fetching relay lists (kind:10002)
    /// These relays should be optimized for metadata queries
    public let outboxRelays: Set<String>

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
        outboxRelays: Set<String> = RelayConstants.defaultOutboxRelays,
        defaultPublishConfig: OutboxPublishConfig = .default,
        defaultFetchConfig: OutboxFetchConfig = .default,
        defaultSubscriptionConfig: OutboxSubscriptionConfig = .default,
        autoRetryFailedPublishes: Bool = true,
        retryInterval: TimeInterval = NetworkConstants.timeoutResource
    ) {
        self.blacklistedRelays = blacklistedRelays
        self.outboxRelays = outboxRelays
        self.defaultPublishConfig = defaultPublishConfig
        self.defaultFetchConfig = defaultFetchConfig
        self.defaultSubscriptionConfig = defaultSubscriptionConfig
        self.autoRetryFailedPublishes = autoRetryFailedPublishes
        self.retryInterval = retryInterval
    }

    public static let `default` = NDKOutboxConfig()
}
