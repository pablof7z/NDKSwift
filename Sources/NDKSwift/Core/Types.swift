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

// MARK: - Time Constants

/// Constants for time conversion and common intervals
public enum TimeConstants {
    /// Nanoseconds per second (for Task.sleep conversion)
    public static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    /// Nanoseconds per millisecond (for Task.sleep conversion)
    public static let nanosecondsPerMillisecond: UInt64 = 1_000_000

    // MARK: - Common Time Intervals

    /// One minute in seconds
    public static let minute: TimeInterval = 60

    /// One hour in seconds
    public static let hour: TimeInterval = 60 * minute

    /// One day in seconds
    public static let day: TimeInterval = 24 * hour

    /// One week in seconds
    public static let week: TimeInterval = 7 * day

    /// One month in seconds (30 days)
    public static let month: TimeInterval = 30 * day

    /// One year in seconds (365 days)
    public static let year: TimeInterval = 365 * day

    // MARK: - Cache TTLs

    /// Default cache TTL for profiles and metadata (1 hour)
    public static let defaultCacheTTL: TimeInterval = hour

    /// Default TTL for NIP-05 verification cache (24 hours)
    public static let nip05CacheTTL: TimeInterval = day

    /// Default TTL for relay list cache (24 hours)
    public static let relayListCacheTTL: TimeInterval = day

    /// Default TTL for unpublished events retry window (1 hour)
    public static let unpublishedEventRetryWindow: TimeInterval = hour

    /// Default TTL for mint info cache (7 days)
    public static let mintInfoCacheTTL: TimeInterval = week

    /// Default TTL for keysets cache (3 days)
    public static let keysetsCacheTTL: TimeInterval = 3 * day
}

// MARK: - Timestamp utilities
public extension Timestamp {
    /// Get the current timestamp
    static var now: Timestamp {
        return Date.currentNostrTimestamp
    }

    /// Create a timestamp from a Date
    static func from(_ date: Date) -> Timestamp {
        return Timestamp(date.timeIntervalSince1970)
    }

    /// Convert to Date
    var date: Date {
        return Date(timeIntervalSince1970: TimeInterval(self))
    }
}

/// Relay URL
public typealias RelayURL = String

/// Nostr event kind
public typealias Kind = Int

/// Common Nostr event kinds as defined in various NIPs
public enum EventKind {
    // MARK: - Core Events (0-999)
    /// User metadata (NIP-01) - Contains profile information like name, picture, about
    public static let metadata = 0
    /// Short text note (NIP-01) - Main content type, like tweets
    public static let textNote = 1
    /// Relay recommendation (NIP-01, deprecated) - Suggests relays to connect to
    public static let recommendRelay = 2
    /// Contact list (NIP-02) - List of pubkeys the user follows
    public static let contacts = 3
    /// Encrypted direct message (NIP-04, deprecated) - Use NIP-44 instead
    public static let encryptedDirectMessage = 4
    /// Event deletion (NIP-09) - Requests deletion of previous events
    public static let deletion = 5
    /// Repost (NIP-18) - Shares another event
    public static let repost = 6
    /// Reaction (NIP-25) - Like, emoji reaction, or upvote
    public static let reaction = 7
    /// Generic repost (NIP-18) - Repost any event kind
    public static let genericRepost = 16
    /// Image event (NIP-68) - Picture-first content for Instagram-like feeds
    public static let image = 20
    /// Channel creation (NIP-28) - Creates a chat channel
    public static let channel = 40
    /// Channel metadata (NIP-28) - Updates channel information
    public static let channelMetadata = 41
    /// Channel message (NIP-28) - Message sent to a channel
    public static let channelMessage = 42

    // MARK: - Extended Events (1000-9999)
    public static let fileMetadata = 1063
    public static let genericReply = 1111  // NIP-22 comment
    public static let report = 1984  // NIP-56 Report

    // MARK: - NIP-60 Cashu Events
    public static let cashuWalletBackup = 375  // Wallet backup event (NIP-60)
    public static let cashuQuote = 7374
    public static let cashuToken = 7375  // Token event (NIP-60)
    public static let cashuSpendingHistory = 7376  // Spending history (NIP-60)
    public static let nutzap = 9321
    public static let cashuWalletConfig = 17375  // Wallet configuration (NIP-60)

    // MARK: - Zap Events
    public static let zapRequest = 9734
    public static let zap = 9735
    public static let zapReceipt = 9735  // Alias for clarity

    // MARK: - List Events (10000-19999)
    public static let muteList = 10000
    public static let pinList = 10001
    public static let relayList = 10002
    public static let bookmarkList = 10003
    public static let communitiesList = 10004
    public static let publicChatsList = 10005
    public static let blockedRelays = 10006
    public static let searchRelays = 10007
    public static let interestList = 10015
    public static let userEmojiList = 10030
    public static let cashuMintList = 10019
    public static let nutzapPreferences = 10019  // Alias for NIP-61
    public static let blockedMints = 10020

    // MARK: - Authentication Events (20000-29999)
    public static let clientAuthentication = 22242
    public static let nwcRequest = 23194
    public static let nwcResponse = 23195
    public static let nostrConnect = 24133
    public static let blossomAuth = 24242
    public static let httpAuth = 27235

    // MARK: - Parameterized Replaceable Events (30000-39999)
    public static let categorizedPeopleList = 30000
    public static let categorizedBookmarkList = 30001
    public static let relayListMetadata = 30002
    public static let profileBadges = 30008
    public static let badgeDefinition = 30009
    public static let longFormContent = 30023
    public static let draftLongForm = 30024
    public static let blossomServerList = 30063
    public static let applicationSpecificData = 30078
    public static let liveEvent = 30311
    public static let handlerRecommendation = 31989
    public static let handlerInformation = 31990
    public static let blossomServerAnnouncement = 36363  // Blossom server discovery
    public static let mintAnnouncement = 38000  // NIP-87 mint discovery
    public static let cashuMintAnnouncement = 38172  // NIP-87
    public static let followPack = 39089  // NIP-51 follow pack
    public static let mediaFollowPack = 39092  // NIP-51 media follow pack
}

// MARK: - Common Amount Presets

/// Common amounts used for zaps and payments (in sats)
public enum AmountPresets {
    /// Small preset amounts for zaps
    public static let smallZapAmounts = [21, 100, 1000]

    /// Standard preset amounts for zaps and nutzaps
    public static let standardAmounts = [100, 500, 1000, 5000, 10000, 50000]

    /// Extended preset amounts including larger values
    public static let extendedAmounts = [100, 500, 1000, 5000, 10000, 50000, 100000]

    /// Common nutzap preset amounts
    public static let nutzapAmounts = [1000, 5000, 10000, 50000]

    /// Default zap amount
    public static let defaultZapAmount = 21

    /// Minimum zap amount
    public static let minimumZapAmount = 1
}

// MARK: - Event Kind Ranges

public extension EventKind {
    /// Regular events (0-999)
    static let regularRange = 0..<1000

    /// Replaceable events (10000-19999)
    static let replaceableRange = 10000..<20000

    /// Ephemeral events (20000-29999)
    static let ephemeralRange = 20000..<30000

    /// Parameterized replaceable events (30000-39999)
    static let parameterizedReplaceableRange = 30000..<40000

    /// Check if a kind is replaceable
    static func isReplaceable(_ kind: Int) -> Bool {
        return replaceableRange.contains(kind)
    }

    /// Check if a kind is ephemeral
    static func isEphemeral(_ kind: Int) -> Bool {
        return ephemeralRange.contains(kind)
    }

    /// Check if a kind is parameterized replaceable
    static func isParameterizedReplaceable(_ kind: Int) -> Bool {
        return parameterizedReplaceableRange.contains(kind)
    }

    /// Check if a kind is regular
    static func isRegular(_ kind: Int) -> Bool {
        return regularRange.contains(kind)
    }
}

/// Tag structure
public typealias Tag = [String]

/// Imeta tag representation for NIP-92 media attachments
///
/// This structure represents media metadata tags used to describe images, videos,
/// and other media attachments in Nostr events. It follows the NIP-92 specification
/// for inline media metadata.
///
/// Example usage:
/// ```swift
/// let imeta = NDKImetaTag(
///     url: "https://example.com/image.jpg",
///     blurhash: "eHF$@-4mR*t7t7WB",
///     dim: "1024x768",
///     alt: "A beautiful sunset"
/// )
/// ```
public struct NDKImetaTag: Sendable {
    /// The URL of the media file
    public var url: String?
    
    /// Blurhash representation for progressive loading
    public var blurhash: String?
    
    /// Dimensions in format "widthxheight" (e.g., "1024x768")
    public var dim: String?
    
    /// Alternative text description for accessibility
    public var alt: String?
    
    /// MIME type of the media (e.g., "image/jpeg", "video/mp4")
    public var m: String?
    
    /// SHA256 hash of the file content
    public var x: String?
    
    /// File size in bytes
    public var size: String?
    
    /// Fallback URLs if the primary URL is unavailable
    public var fallback: [String]?
    
    /// User annotations for tagging people in images
    public var userAnnotations: [UserAnnotation]?
    
    /// Additional non-standard fields
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
        userAnnotations: [UserAnnotation]? = nil,
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
        self.userAnnotations = userAnnotations
        self.additionalFields = additionalFields
    }
}

/// User annotation for tagging people in images (NIP-68)
///
/// Represents a coordinate-based tag of a user in an image, allowing
/// social media-style face tagging functionality.
///
/// Example usage:
/// ```swift
/// let annotation = UserAnnotation(
///     pubkey: "abc123...",
///     x: 150,  // X coordinate in pixels
///     y: 200   // Y coordinate in pixels
/// )
/// ```
public struct UserAnnotation: Sendable {
    /// The public key of the tagged user
    public let pubkey: PublicKey
    
    /// X coordinate of the tag position in pixels
    public let x: Int
    
    /// Y coordinate of the tag position in pixels
    public let y: Int

    public init(pubkey: PublicKey, x: Int, y: Int) {
        self.pubkey = pubkey
        self.x = x
        self.y = y
    }
}

/// OK message from relay
public struct OKMessage: Equatable, Sendable {
    public let accepted: Bool
    public let message: String?
    public let receivedAt: Date
}

// MARK: - Core Error Type

/// Idiomatic Swift error enum for NDKSwift
public enum NDKError: LocalizedError {
    // Validation errors
    case invalidPublicKey(String)
    case invalidPrivateKey(String)
    case invalidEventID(String)
    case invalidSignature(String)
    case invalidFilter(String)
    case invalidInput(message: String)

    // Crypto errors
    case signingFailed(String, underlying: Error? = nil)
    case verificationFailed(String, underlying: Error? = nil)
    case encryptionFailed(String, underlying: Error? = nil)
    case decryptionFailed(String, underlying: Error? = nil)
    case keyDerivationFailed(String, underlying: Error? = nil)

    // Network errors
    case connectionFailed(relay: String, message: String, underlying: Error? = nil)
    case connectionLost(relay: String, message: String)
    case timeout(operation: String, seconds: Int)
    case serverError(relay: String, code: Int, message: String?)
    case unauthorized(relay: String, message: String)
    case relayError(relay: String, message: String)
    case publishFailed(relay: String, message: String)
    case rateLimited(message: String)

    // Storage errors
    case cacheFailed(operation: String, underlying: Error? = nil)
    case diskFull
    case fileNotFound(path: String)
    case corruptedData(path: String)

    // Protocol errors
    case invalidMessage(String)
    case unsupportedVersion(String)
    case subscriptionFailed(String)
    case protocolViolation(String)

    // Configuration errors
    case notConfigured(String)
    case invalidConfiguration(String)

    // Runtime errors
    case notImplemented(String)
    case cancelled
    case unknown(String, underlying: Error? = nil)
    case internalError(String)

    // Wallet errors (NWC)
    case walletRateLimited(retryAfter: Int?)
    case walletNotImplemented(method: String)
    case insufficientBalance(amount: Int64?)
    case walletQuotaExceeded
    case walletRestricted(reason: String)
    case walletUnauthorized
    case paymentFailed(reason: String)
    case walletNotFound(resource: String)
    case walletError(message: String)
    case paymentRequired(String)

    // Cashu errors
    case invalidRequest(String)
    case noMintAvailable(String)
    case encodingError(String)
    case invalidContent(String)

    // File/Blossom errors
    case invalidURL(String)
    case invalidResponse(from: String)
    case fileTooLarge(maxSize: Int64)
    case unsupportedMimeType(String)
    case blobNotFound(sha256: String)
    case uploadFailed(reason: String)
    case invalidSHA256(String)

    // Serialization errors
    case serializationFailed(String)

    public var errorDescription: String? {
        switch self {
        // Validation
        case .invalidPublicKey(let key):
            return "Invalid public key: \(key)"
        case .invalidPrivateKey(let key):
            return "Invalid private key: \(key)"
        case .invalidEventID(let id):
            return "Invalid event ID: \(id)"
        case .invalidSignature(let sig):
            return "Invalid signature: \(sig)"
        case .invalidFilter(let filter):
            return "Invalid filter: \(filter)"
        case .invalidInput(let message):
            return message

        // Crypto
        case .signingFailed(let message, let underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case .verificationFailed(let message, let underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case .encryptionFailed(let message, let underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case .decryptionFailed(let message, let underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case .keyDerivationFailed(let message, let underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message

        // Network
        case .connectionFailed(let relay, let message, let underlying):
            return underlying.map { "Connection to \(relay) failed: \(message) - \($0.localizedDescription)" } ?? "Connection to \(relay) failed: \(message)"
        case .connectionLost(let relay, let message):
            return "Connection to \(relay) lost: \(message)"
        case .timeout(let operation, let seconds):
            return "\(operation) timed out after \(seconds) seconds"
        case .serverError(let relay, let code, let message):
            return "Server error from \(relay) (\(code)): \(message ?? "Unknown error")"
        case .unauthorized(let relay, let message):
            return "Unauthorized on \(relay): \(message)"
        case .relayError(let relay, let message):
            return "Relay error from \(relay): \(message)"

        // Storage
        case .cacheFailed(let operation, let underlying):
            return underlying.map { "Cache \(operation) failed: \($0.localizedDescription)" } ?? "Cache \(operation) failed"
        case .diskFull:
            return "Insufficient storage space"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .corruptedData(let path):
            return "Corrupted data at: \(path)"

        // Protocol
        case .invalidMessage(let message):
            return "Invalid protocol message: \(message)"
        case .unsupportedVersion(let version):
            return "Unsupported protocol version: \(version)"
        case .subscriptionFailed(let reason):
            return "Subscription failed: \(reason)"
        case .protocolViolation(let message):
            return "Protocol violation: \(message)"

        // Configuration
        case .notConfigured(let component):
            return "\(component) is not configured"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"

        // Runtime
        case .notImplemented(let feature):
            return "\(feature) is not implemented"
        case .cancelled:
            return "Operation was cancelled"
        case .unknown(let message, let underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case .internalError(let message):
            return "Internal error: \(message)"
        case .publishFailed(let relay, let message):
            return "Failed to publish to \(relay): \(message)"
        case .rateLimited(let message):
            return message

        // Wallet
        case .walletRateLimited(let retryAfter):
            return retryAfter.map { "Too many requests. Retry after \($0) seconds." } ?? "Too many requests. Please try again later."
        case .walletNotImplemented(let method):
            return "\(method) is not supported by the wallet"
        case .insufficientBalance(let amount):
            return amount.map { "Insufficient balance (need \($0) sats)" } ?? "Insufficient balance"
        case .walletQuotaExceeded:
            return "Spending quota exceeded"
        case .walletRestricted(let reason):
            return "Wallet restricted: \(reason)"
        case .walletUnauthorized:
            return "No wallet connected or invalid credentials"
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        case .walletNotFound(let resource):
            return "Wallet resource not found: \(resource)"
        case .walletError(let message):
            return message
        case .paymentRequired(let message):
            return message

        // Cashu
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .noMintAvailable(let message):
            return "No mint available: \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .invalidContent(let message):
            return "Invalid content: \(message)"

        // File/Blossom
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse(let from):
            return "Invalid response from \(from)"
        case .fileTooLarge(let maxSize):
            return "File exceeds maximum size of \(maxSize) bytes"
        case .unsupportedMimeType(let type):
            return "Unsupported MIME type: \(type)"
        case .blobNotFound(let sha256):
            return "Blob not found: \(sha256)"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .invalidSHA256(let hash):
            return "Invalid SHA256 hash: \(hash)"
        case .serializationFailed(let message):
            return "Serialization failed: \(message)"
        }
    }
}

// MARK: - Subscription State

internal enum NDKSubscriptionState: Equatable, Sendable {
    case pending
    case active
    case inactive
    case closed
}

// MARK: - Publication Status

public enum PublicationStatus: Equatable, Sendable {
    case notPublished
    case publishing
    case published
    case failed(String)
}

// MARK: - Event Source

/// Represents the source of an event for optimistic publishing
public enum EventSource: Sendable {
    /// Event was generated optimistically during local publish
    case optimistic
    /// Event was received from a specific relay
    case relay(RelayProtocol)
    /// Event was loaded from cache
    case cache
}

// MARK: - Event Confirmation State

/// Tracks the confirmation state of events for optimistic publishing
public enum EventConfirmationState: Equatable, Sendable {
    /// Event was published optimistically but not yet confirmed
    case optimistic
    /// Event was confirmed by a relay
    case confirmed(fromRelay: String)

    public var isConfirmed: Bool {
        switch self {
        case .optimistic:
            return false
        case .confirmed:
            return true
        }
    }
}
