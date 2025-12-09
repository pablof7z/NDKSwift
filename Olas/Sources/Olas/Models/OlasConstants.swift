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

    /// Breez API key for Spark wallet
    /// Request your own at https://breez.technology/request-api-key
    public static let breezApiKey = "YOUR_BREEZ_API_KEY"

    public enum EventKinds {
        public static let image: Kind = 20
        public static let shortVideo: Kind = 22  // NIP-71 short-form video
        public static let reaction: Kind = 7
        public static let comment: Kind = 1111
        public static let report: Kind = 1984
        public static let muteList: Kind = 10000
    }

    public enum ReportType: String, CaseIterable, Identifiable {
        case nudity
        case spam
        case illegal
        case impersonation
        case profanity
        case malware
        case other

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .nudity: return "Nudity"
            case .spam: return "Spam"
            case .illegal: return "Illegal content"
            case .impersonation: return "Impersonation"
            case .profanity: return "Hate speech"
            case .malware: return "Malware"
            case .other: return "Other"
            }
        }

        public var description: String {
            switch self {
            case .nudity: return "Contains explicit or adult content"
            case .spam: return "Unwanted promotional content"
            case .illegal: return "Potentially illegal content"
            case .impersonation: return "Pretending to be someone else"
            case .profanity: return "Hateful or offensive language"
            case .malware: return "Contains malicious links or software"
            case .other: return "Other violation"
            }
        }
    }
}
