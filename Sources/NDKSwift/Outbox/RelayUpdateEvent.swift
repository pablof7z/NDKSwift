import Foundation

/// Event that represents a relay update for a user
public struct RelayUpdateEvent: Sendable {
    public let pubkey: String
    public let relays: (readRelays: Set<RelayURL>, writeRelays: Set<RelayURL>)
    public let affectedSubscriptionIds: Set<String>
    public let timestamp: Date
    
    public init(
        pubkey: String,
        relays: (readRelays: Set<RelayURL>, writeRelays: Set<RelayURL>),
        affectedSubscriptionIds: Set<String>,
        timestamp: Date = Date()
    ) {
        self.pubkey = pubkey
        self.relays = relays
        self.affectedSubscriptionIds = affectedSubscriptionIds
        self.timestamp = timestamp
    }
}