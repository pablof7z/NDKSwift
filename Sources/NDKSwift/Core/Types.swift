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

/// NDK Error types
public enum NDKError: Error, LocalizedError, Equatable {
    case invalidPublicKey
    case invalidPrivateKey
    case invalidEventID
    case invalidSignature
    case signingFailed
    case verificationFailed
    case invalidFilter
    case relayConnectionFailed(String)
    case subscriptionFailed(String)
    case cacheFailed(String)
    case timeout
    case cancelled
    case notImplemented
    case custom(String)
    case validation(String)
    case walletNotConfigured
    case insufficientBalance
    case powGenerationFailed
    case invalidPaymentRequest
    case signerError(String)
    case invalidEvent(String)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPublicKey:
            return "Invalid public key format"
        case .invalidPrivateKey:
            return "Invalid private key format"
        case .invalidEventID:
            return "Invalid event ID"
        case .invalidSignature:
            return "Invalid signature"
        case .signingFailed:
            return "Failed to sign event"
        case .verificationFailed:
            return "Failed to verify signature"
        case .invalidFilter:
            return "Invalid filter configuration"
        case let .relayConnectionFailed(message):
            return "Relay connection failed: \(message)"
        case let .subscriptionFailed(message):
            return "Subscription failed: \(message)"
        case let .cacheFailed(message):
            return "Cache operation failed: \(message)"
        case .timeout:
            return "Operation timed out"
        case .cancelled:
            return "Operation was cancelled"
        case .notImplemented:
            return "Feature not implemented"
        case let .custom(message):
            return message
        case let .validation(message):
            return "Validation error: \(message)"
        case .walletNotConfigured:
            return "Wallet not configured"
        case .insufficientBalance:
            return "Insufficient balance"
        case .powGenerationFailed:
            return "Failed to generate proof of work"
        case .invalidPaymentRequest:
            return "Invalid payment request"
        case let .signerError(message):
            return "Signer error: \(message)"
        case let .invalidEvent(message):
            return "Invalid event: \(message)"
        case let .invalidInput(message):
            return "Invalid input: \(message)"
        }
    }
}
