import Foundation

// MARK: - Feed Source

/// Represents a source of content for the main feed
public enum FeedSource: Identifiable, Equatable, Hashable {
    case follows
    case pack(SavedPack)
    case relay(SavedRelay)

    public var id: String {
        switch self {
        case .follows:
            return "follows"
        case .pack(let pack):
            return "pack-\(pack.id)"
        case .relay(let relay):
            return "relay-\(relay.url)"
        }
    }

    public var displayName: String {
        switch self {
        case .follows:
            return "Feed"
        case .pack(let pack):
            return pack.name
        case .relay(let relay):
            return relay.displayName
        }
    }

    public var icon: String {
        switch self {
        case .follows:
            return "house"
        case .pack:
            return "person.3"
        case .relay:
            return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Codable Conformance

extension FeedSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, pack, relay
    }

    private enum SourceType: String, Codable {
        case follows, pack, relay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SourceType.self, forKey: .type)

        switch type {
        case .follows:
            self = .follows
        case .pack:
            let pack = try container.decode(SavedPack.self, forKey: .pack)
            self = .pack(pack)
        case .relay:
            let relay = try container.decode(SavedRelay.self, forKey: .relay)
            self = .relay(relay)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .follows:
            try container.encode(SourceType.follows, forKey: .type)
        case .pack(let pack):
            try container.encode(SourceType.pack, forKey: .type)
            try container.encode(pack, forKey: .pack)
        case .relay(let relay):
            try container.encode(SourceType.relay, forKey: .type)
            try container.encode(relay, forKey: .relay)
        }
    }
}

// MARK: - Saved Pack

/// A serializable version of FollowPack for persistence
public struct SavedPack: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let description: String?
    public let imageURL: URL?
    public let pubkeys: [String]
    public let creatorPubkey: String

    public var memberCount: Int { pubkeys.count }
}

// MARK: - Saved Relay

/// A saved relay for feed filtering
public struct SavedRelay: Identifiable, Codable, Equatable, Hashable {
    public var id: String { url }
    public let url: String
    public let displayName: String
    public let description: String?
    public let iconURL: String?
}
