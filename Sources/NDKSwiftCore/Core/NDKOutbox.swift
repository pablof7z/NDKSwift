import Foundation

/// NDK Outbox Configuration
public struct NDKOutboxConfig {
    /// Relays to blocklist from outbox selection
    public let blocklistedRelays: Set<String>

    /// Dedicated relays for fetching relay lists (kind:10002)
    /// These relays should be optimized for metadata queries
    public let outboxRelays: Set<String>

    public init(
        blocklistedRelays: Set<String> = [],
        outboxRelays: Set<String> = RelayConstants.defaultOutboxRelays
    ) {
        self.blocklistedRelays = blocklistedRelays
        self.outboxRelays = outboxRelays
    }

    public static let `default` = NDKOutboxConfig()
}
