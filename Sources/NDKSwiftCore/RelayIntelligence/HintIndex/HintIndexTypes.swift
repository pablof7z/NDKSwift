import Foundation

/// Source of a relay hint - where we learned about this relay for a user/event
public enum HintSource: Sendable, Equatable, Hashable {
    /// From NIP-19 bech32 encoding (nevent, nprofile, naddr)
    case nip19
    /// Event was observed arriving from this relay
    case eventObserved
    /// From user's NIP-65 relay list
    case userRelayList
    /// Provided by app configuration
    case app
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

/// Represents a relay's mention frequency in the hint index
public struct RelayMention: Sendable, Equatable {
    /// The relay URL
    public let relay: RelayURL
    /// How many times this relay appears in hints
    public let mentionCount: Int

    public init(relay: RelayURL, mentionCount: Int) {
        self.relay = relay
        self.mentionCount = mentionCount
    }
}

/// Statistics about the hint index
public struct HintIndexStatistics: Sendable, Equatable {
    /// Number of unique pubkeys with hints
    public let pubkeyCount: Int
    /// Number of unique event IDs with hints
    public let eventIdCount: Int
    /// Number of unique addresses with hints
    public let addressCount: Int
    /// Total number of hint entries
    public let totalEntries: Int
    /// Number of unique relays across all hints
    public let uniqueRelayCount: Int

    public init(pubkeyCount: Int, eventIdCount: Int, addressCount: Int, totalEntries: Int, uniqueRelayCount: Int) {
        self.pubkeyCount = pubkeyCount
        self.eventIdCount = eventIdCount
        self.addressCount = addressCount
        self.totalEntries = totalEntries
        self.uniqueRelayCount = uniqueRelayCount
    }
}
