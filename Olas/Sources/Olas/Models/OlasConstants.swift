import Foundation
import NDKSwift

public enum OlasConstants {
    public static let defaultRelays: [String] = [
        "wss://relay.damus.io",
        "wss://relay.primal.net",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ]

    public static let blossomServers: [String] = [
        "https://blossom.primal.net",
        "https://nostr.build"
    ]

    public enum EventKinds {
        public static let image: Kind = 20
        public static let reaction: Kind = 7
        public static let comment: Kind = 1111
    }
}
