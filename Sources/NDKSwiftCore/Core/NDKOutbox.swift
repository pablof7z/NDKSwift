import Foundation

/// NDK Discovery Configuration - relays used for discovering user relay lists
public struct NDKDiscoveryConfig {
    /// Relays to blocklist from outbox selection
    public let blocklistedRelays: Set<String>

    /// Dedicated relays for fetching relay lists (kind:10002)
    /// These relays should be optimized for metadata queries (e.g., purplepag.es)
    public let discoveryRelays: Set<String>

    public init(
        blocklistedRelays: Set<String> = [],
        discoveryRelays: Set<String> = RelayConstants.defaultDiscoveryRelays
    ) {
        self.blocklistedRelays = blocklistedRelays
        self.discoveryRelays = discoveryRelays
    }

    public static let `default` = NDKDiscoveryConfig()
}
