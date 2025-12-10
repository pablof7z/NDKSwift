import Foundation

/// Extension to NDK for internal outbox model support
extension NDK {
    // MARK: - Internal Outbox Components


    /// Relay ranker for intelligent selection
    var relayRanker: NDKRelayRanker {
        lazyInit(&_relayRanker) {
            NDKRelayRanker(ndk: self, tracker: outbox)
        }
    }


    /// Publishing strategy for outbox model
    var publishingStrategy: NDKPublishingStrategy {
        lazyInit(&_publishingStrategy) {
            NDKPublishingStrategy(
                ndk: self,
                selector: relaySelector,
                ranker: relayRanker
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

    public init(
        blacklistedRelays: Set<String> = [],
        outboxRelays: Set<String> = RelayConstants.defaultOutboxRelays
    ) {
        self.blacklistedRelays = blacklistedRelays
        self.outboxRelays = outboxRelays
    }

    public static let `default` = NDKOutboxConfig()
}
