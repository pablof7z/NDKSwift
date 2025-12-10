import Foundation

enum FeedMode: Equatable, Hashable {
    case following
    case relay(url: String)

    var displayName: String {
        switch self {
        case .following:
            return "Following"
        case .relay:
            return "Relay"
        }
    }
}

struct DiscoveryRelays {
    public static let relays = [
        "wss://relay.divine.video"
    ]
}
