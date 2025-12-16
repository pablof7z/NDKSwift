import Foundation

/// Source of a relay hint - where we learned about this relay for a user/event
public enum HintSource: Sendable, Equatable {
    /// From NIP-19 bech32 encoding (nevent, nprofile, naddr)
    case nip19
    /// Event was observed arriving from this relay
    case eventObserved
    /// From user's NIP-65 relay list
    case userRelayList
    /// Explicitly provided by app or user
    case explicit
}

/// A recorded relay hint - represents a learned association between an entity and a relay
public struct HintEntry: Sendable, Equatable {
    /// The relay URL where the entity was observed
    public let relay: RelayURL
    /// How we learned about this relay
    public let source: HintSource
    /// When this hint was recorded
    public let recordedAt: Date

    public init(relay: RelayURL, source: HintSource, recordedAt: Date = Date()) {
        self.relay = relay
        self.source = source
        self.recordedAt = recordedAt
    }
}
