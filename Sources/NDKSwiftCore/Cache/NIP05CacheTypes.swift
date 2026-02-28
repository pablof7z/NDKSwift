import Foundation

// MARK: - NIP-05 Cache Types

/// Verification status for NIP-05 identifiers
public enum NIP05VerificationStatus: String, Codable, Sendable {
    /// Claimed in kind:0 but not yet verified
    case unverified
    /// Verified and matches the claiming pubkey
    case verified
    /// Verified but belongs to a different pubkey
    case invalid
    /// Was verified but needs re-verification
    case expired
    /// Verification attempt failed (network/DNS error)
    case failed
}

/// Cache entry for NIP-05 identifiers
public struct NIP05CacheEntry: Codable, Sendable, Equatable {
    /// The full NIP-05 identifier (e.g., "satoshi@bitcoin.org")
    public let identifier: String
    /// The public key associated with this identifier
    public let pubkey: String
    /// Current verification status
    public var status: NIP05VerificationStatus
    /// Optional NIP-46 relay URLs from verification
    public var nip46Relays: [String]?
    /// When this identifier was first seen
    public let claimedAt: Date
    /// When last successfully verified
    public var verifiedAt: Date?
    /// When last verification was attempted
    public var lastCheckAt: Date?
    /// Error message if verification failed
    public var errorMessage: String?
    /// HTTP status code from last verification attempt
    public var httpStatusCode: Int?

    public init(
        identifier: String,
        pubkey: String,
        status: NIP05VerificationStatus,
        nip46Relays: [String]? = nil,
        claimedAt: Date = Date(),
        verifiedAt: Date? = nil,
        lastCheckAt: Date? = nil,
        errorMessage: String? = nil,
        httpStatusCode: Int? = nil
    ) {
        self.identifier = identifier
        self.pubkey = pubkey
        self.status = status
        self.nip46Relays = nip46Relays
        self.claimedAt = claimedAt
        self.verifiedAt = verifiedAt
        self.lastCheckAt = lastCheckAt
        self.errorMessage = errorMessage
        self.httpStatusCode = httpStatusCode
    }
}
