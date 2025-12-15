import Foundation

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
