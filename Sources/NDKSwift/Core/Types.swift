import Foundation

/// 32-byte lowercase hex-encoded public key
public typealias PublicKey = String

/// 32-byte lowercase hex-encoded private key
public typealias PrivateKey = String

/// 32-byte lowercase hex-encoded event ID
public typealias EventID = String

/// 64-byte lowercase hex-encoded signature
public typealias Signature = String

/// Unix timestamp in seconds
public typealias Timestamp = Int64

/// Relay URL
public typealias RelayURL = String

/// Nostr event kind
public typealias Kind = Int

/// Common Nostr event kinds
public enum EventKind {
    public static let metadata = 0
    public static let textNote = 1
    public static let recommendRelay = 2
    public static let contacts = 3
    public static let encryptedDirectMessage = 4
    public static let deletion = 5
    public static let repost = 6
    public static let reaction = 7
    public static let badgeAward = 8
    public static let image = 20
    public static let channelCreation = 40
    public static let channelMetadata = 41
    public static let channelMessage = 42
    public static let channelHideMessage = 43
    public static let channelMuteUser = 44
    public static let fileMetadata = 1063
    public static let zapRequest = 9734
    public static let zap = 9735
    public static let muteList = 10000
    public static let pinList = 10001
    public static let relayList = 10002
    public static let walletInfo = 13194
    public static let clientAuthentication = 22242
    public static let walletRequest = 23194
    public static let walletResponse = 23195
    public static let nostrConnect = 24133
    public static let httpAuth = 27235
    public static let categorizedPeople = 30000
    public static let categorizedBookmarks = 30001
    public static let profileBadges = 30008
    public static let badgeDefinition = 30009
    public static let longFormContent = 30023
    public static let applicationSpecificData = 30078
    // Cashu/NIP-60 kinds
    public static let cashuReserve = 7373
    public static let cashuQuote = 7374
    public static let cashuToken = 7375
    public static let cashuWalletTx = 7376
    public static let cashuWallet = 17375
    public static let cashuWalletBackup = 375
    // NIP-61
    public static let nutzap = 9321
    public static let cashuMintList = 10019
}

/// Tag structure
public typealias Tag = [String]

/// Imeta tag representation
public struct NDKImetaTag {
    public var url: String?
    public var blurhash: String?
    public var dim: String?
    public var alt: String?
    public var m: String?
    public var x: String?
    public var size: String?
    public var fallback: [String]?
    public var additionalFields: [String: String] = [:]

    public init(
        url: String? = nil,
        blurhash: String? = nil,
        dim: String? = nil,
        alt: String? = nil,
        m: String? = nil,
        x: String? = nil,
        size: String? = nil,
        fallback: [String]? = nil,
        additionalFields: [String: String] = [:]
    ) {
        self.url = url
        self.blurhash = blurhash
        self.dim = dim
        self.alt = alt
        self.m = m
        self.x = x
        self.size = size
        self.fallback = fallback
        self.additionalFields = additionalFields
    }
}

/// OK message from relay
public struct OKMessage: Equatable {
    public let accepted: Bool
    public let message: String?
    public let receivedAt: Date
}

