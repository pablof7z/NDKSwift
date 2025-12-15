import Foundation

/// Core type definitions and constants used throughout the NDKSwift framework.
///
/// This file defines fundamental types, constants, and enumerations that form the basis
/// of the Nostr protocol implementation. It includes:
/// - Type aliases for cryptographic keys and identifiers
/// - Time-related constants and utilities
/// - Event kinds as defined in various NIPs
/// - Common tag types and metadata structures
///
/// ## Type Safety
/// Type aliases like `PublicKey`, `PrivateKey`, and `EventID` provide semantic meaning
/// while maintaining type safety. They are all String types but clearly indicate their purpose.
///
/// ## Constants Organization
/// Constants are grouped into logical enums to provide namespacing and prevent pollution
/// of the global scope.

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
    /// User metadata (NIP-01) - Alias for metadata
    public static let profile = 0
    /// Short text note (NIP-01) - Main content type, like tweets
    public static let textNote = 1
    /// Relay recommendation (NIP-01, deprecated) - Suggests relays to connect to
    public static let recommendRelay = 2
    /// Contact list (NIP-02) - List of pubkeys the user follows
    public static let contacts = 3
    /// Contact list (NIP-02) - Alias for contacts
    public static let contactList = 3
    /// Encrypted direct message (NIP-04)
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

    /// File metadata event (NIP-94) - Contains metadata for files stored on external servers
    public static let fileMetadata = 1063
    /// Generic reply/comment event (NIP-22) - Used for commenting on any addressable content
    public static let genericReply = 1111
    /// Report event (NIP-56) - For reporting inappropriate content or users
    public static let report = 1984

    // MARK: - NIP-60 Cashu Events

    /// Cashu wallet backup event (NIP-60) - Encrypted backup of wallet proofs and state
    public static let cashuWalletBackup = 375
    /// Cashu quote event - Contains mint quotes for token operations
    public static let cashuQuote = 7374
    /// Cashu token event (NIP-60) - Contains ecash tokens for transfer
    public static let cashuToken = 7375
    /// Cashu spending history (NIP-60) - Records of spent tokens for recovery
    public static let cashuSpendingHistory = 7376
    /// Nutzap event (NIP-61) - Ecash-based zap payments
    public static let nutzap = 9321
    /// Cashu wallet configuration (NIP-60) - User preferences and settings for Cashu wallets
    public static let cashuWalletConfig = 17375

    // MARK: - Zap Events

    /// Zap request event (NIP-57) - Request for a Lightning payment to a user
    public static let zapRequest = 9734
    /// Zap receipt event (NIP-57) - Proof of a completed Lightning payment
    public static let zap = 9735
    /// Alias for zap event for clarity in different contexts
    public static let zapReceipt = 9735

    // MARK: - List Events (10000-19999)

    /// Mute list (NIP-51) - List of users, threads, or words to mute
    public static let muteList = 10000
    /// Pin list (NIP-51) - List of events pinned by the user
    public static let pinList = 10001
    /// Relay list (NIP-65) - User's preferred relays for reading and writing
    public static let relayList = 10002
    /// Bookmark list (NIP-51) - List of bookmarked events
    public static let bookmarkList = 10003
    /// Communities list (NIP-51) - List of communities the user is interested in
    public static let communitiesList = 10004
    /// Public chats list (NIP-51) - List of public chat channels
    public static let publicChatsList = 10005
    /// Blocked relays list (NIP-51) - Relays the user wants to avoid
    public static let blockedRelays = 10006
    /// Search relays list (NIP-51) - Specialized relays for search operations
    public static let searchRelays = 10007
    /// Interest list (NIP-51) - Topics or hashtags of interest
    public static let interestList = 10015
    /// User emoji list (NIP-51) - Custom emoji reactions available to the user
    public static let userEmojiList = 10030
    /// Cashu mint list (NIP-60) - List of trusted Cashu mints
    public static let cashuMintList = 10019
    /// Nutzap preferences (NIP-61) - Alias for cashuMintList when used for nutzap configuration
    public static let nutzapPreferences = 10019
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
    public static let articleCurationSet = 30004
    public static let videoCurationSet = 30005
    public static let pictureCurationSet = 30006
    public static let profileBadges = 30008
    public static let badgeDefinition = 30009
    public static let longFormContent = 30023
    public static let draftLongForm = 30024
    public static let blossomServerList = 30063
    public static let applicationSpecificData = 30078
    public static let liveEvent = 30311
    public static let handlerRecommendation = 31989
    public static let handlerInformation = 31990
    public static let blossomServerAnnouncement = 36363 // Blossom server discovery
    public static let mintAnnouncement = 38000 // NIP-87 mint discovery
    public static let cashuMintAnnouncement = 38172 // NIP-87
    public static let followPack = 39089 // NIP-51 follow pack
    public static let mediaFollowPack = 39092 // NIP-51 media follow pack
}

// MARK: - Common Amount Presets

/// Common amounts used for zaps and payments (in sats)
public enum AmountPresets {
    /// Small preset amounts for zaps
    public static let smallZapAmounts = [21, 100, 1000]

    /// Standard preset amounts for zaps and nutzaps
    public static let standardAmounts = [100, 500, 1000, 5000, 10000, 50000]

    /// Extended preset amounts including larger values
    public static let extendedAmounts = [100, 500, 1000, 5000, 10000, 50000, 100_000]

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
    static let regularRange = 0 ..< 1000

    /// Replaceable events (10000-19999)
    static let replaceableRange = 10000 ..< 20000

    /// Ephemeral events (20000-29999)
    static let ephemeralRange = 20000 ..< 30000

    /// Parameterized replaceable events (30000-39999)
    static let parameterizedReplaceableRange = 30000 ..< 40000

    /// Check if a kind is replaceable (matching ndk-core logic)
    /// Includes kinds 0, 3, and 10000-19999, 30000-39999
    static func isReplaceable(_ kind: Int) -> Bool {
        return [0, 3].contains(kind) ||
            replaceableRange.contains(kind) ||
            parameterizedReplaceableRange.contains(kind)
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
    case walletInsufficientBalance(amount: Int64, available: Int64)
    case walletInvalidProof(details: String)

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
        case let .invalidPublicKey(key):
            return "Invalid public key: \(key)"
        case let .invalidPrivateKey(key):
            return "Invalid private key: \(key)"
        case let .invalidEventID(id):
            return "Invalid event ID: \(id)"
        case let .invalidSignature(sig):
            return "Invalid signature: \(sig)"
        case let .invalidFilter(filter):
            return "Invalid filter: \(filter)"
        case let .invalidInput(message):
            return message
        // Crypto
        case let .signingFailed(message, underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case let .verificationFailed(message, underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case let .encryptionFailed(message, underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case let .decryptionFailed(message, underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case let .keyDerivationFailed(message, underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        // Network
        case let .connectionFailed(relay, message, underlying):
            return underlying.map { "Connection to \(relay) failed: \(message) - \($0.localizedDescription)" } ?? "Connection to \(relay) failed: \(message)"
        case let .connectionLost(relay, message):
            return "Connection to \(relay) lost: \(message)"
        case let .timeout(operation, seconds):
            return "\(operation) timed out after \(seconds) seconds"
        case let .serverError(relay, code, message):
            return "Server error from \(relay) (\(code)): \(message ?? "Unknown error")"
        case let .unauthorized(relay, message):
            return "Unauthorized on \(relay): \(message)"
        case let .relayError(relay, message):
            return "Relay error from \(relay): \(message)"
        // Storage
        case let .cacheFailed(operation, underlying):
            return underlying.map { "Cache \(operation) failed: \($0.localizedDescription)" } ?? "Cache \(operation) failed"
        case .diskFull:
            return "Insufficient storage space"
        case let .fileNotFound(path):
            return "File not found: \(path)"
        case let .corruptedData(path):
            return "Corrupted data at: \(path)"
        // Protocol
        case let .invalidMessage(message):
            return "Invalid protocol message: \(message)"
        case let .unsupportedVersion(version):
            return "Unsupported protocol version: \(version)"
        case let .subscriptionFailed(reason):
            return "Subscription failed: \(reason)"
        case let .protocolViolation(message):
            return "Protocol violation: \(message)"
        // Configuration
        case let .notConfigured(component):
            return "\(component) is not configured"
        case let .invalidConfiguration(message):
            return "Invalid configuration: \(message)"
        // Runtime
        case let .notImplemented(feature):
            return "\(feature) is not implemented"
        case .cancelled:
            return "Operation was cancelled"
        case let .unknown(message, underlying):
            return underlying.map { "\(message): \($0.localizedDescription)" } ?? message
        case let .internalError(message):
            return "Internal error: \(message)"
        case let .publishFailed(relay, message):
            return "Failed to publish to \(relay): \(message)"
        case let .rateLimited(message):
            return message
        // Wallet
        case let .walletRateLimited(retryAfter):
            return retryAfter.map { "Too many requests. Retry after \($0) seconds." } ?? "Too many requests. Please try again later."
        case let .walletNotImplemented(method):
            return "\(method) is not supported by the wallet"
        case let .insufficientBalance(amount):
            return amount.map { "Insufficient balance (need \($0) sats)" } ?? "Insufficient balance"
        case .walletQuotaExceeded:
            return "Spending quota exceeded"
        case let .walletRestricted(reason):
            return "Wallet restricted: \(reason)"
        case .walletUnauthorized:
            return "No wallet connected or invalid credentials"
        case let .paymentFailed(reason):
            return "Payment failed: \(reason)"
        case let .walletNotFound(resource):
            return "Wallet resource not found: \(resource)"
        case let .walletError(message):
            return message
        case let .paymentRequired(message):
            return message
        case let .walletInsufficientBalance(amount, available):
            return "Insufficient balance: need \(amount) sats, have \(available) sats"
        case let .walletInvalidProof(details):
            return "Invalid proof: \(details)"
        // Cashu
        case let .invalidRequest(message):
            return "Invalid request: \(message)"
        case let .noMintAvailable(message):
            return "No mint available: \(message)"
        case let .encodingError(message):
            return "Encoding error: \(message)"
        case let .invalidContent(message):
            return "Invalid content: \(message)"
        // File/Blossom
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        case let .invalidResponse(from):
            return "Invalid response from \(from)"
        case let .fileTooLarge(maxSize):
            return "File exceeds maximum size of \(maxSize) bytes"
        case let .unsupportedMimeType(type):
            return "Unsupported MIME type: \(type)"
        case let .blobNotFound(sha256):
            return "Blob not found: \(sha256)"
        case let .uploadFailed(reason):
            return "Upload failed: \(reason)"
        case let .invalidSHA256(hash):
            return "Invalid SHA256 hash: \(hash)"
        case let .serializationFailed(message):
            return "Serialization failed: \(message)"
        }
    }
}

// MARK: - Subscription State

enum NDKSubscriptionState: Equatable, Sendable {
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
