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

    // MARK: - Spark Wallet

    /// Breez API key for Spark wallet
    /// Request your key at: https://breez.technology/request-api-key
    public static let breezApiKey: String = "MIIBbzCCASGgAwIBAgIHPrdM6+5v5zAFBgMrZXAwEDEOMAwGA1UEAxMFQnJlZXowHhcNMjUxMjA5MTY0OTE1WhcNMzUxMjA3MTY0OTE1WjAyMRYwFAYDVQQKEw1TYW5pdHkgSXNsYW5kMRgwFgYDVQQDEw9QYWJsbyBGZXJuYW5kZXowKjAFBgMrZXADIQDQg/XL3yA8HKIgyimHU/Qbpxy0tvzris1fDUtEs6ldd6N4MHYwDgYDVR0PAQH/BAQDAgWgMAwGA1UdEwEB/wQCMAAwHQYDVR0OBBYEFNo5o+5ea0sNMlW/75VgGJCv2AcJMB8GA1UdIwQYMBaAFN6q1pJW843ndJIW/Ey2ILJrKJhrMBYGA1UdEQQPMA2BC3BmZXJAbWUuY29tMAUGAytlcANBAIXuxPsRXhdsnJGuzTHBu/5+gKlspwkCmUa0LUNvasjMRf6kpHkEUEL+4LptlVcVhz5kB+TRpDbHJhaYQu0dEAI="
}
