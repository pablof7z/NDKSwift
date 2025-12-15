import CashuSwift
import Foundation
import NDKSwiftCore

/// Status of a nutzap redemption attempt
public enum NutzapRedemptionStatus: Sendable, Codable, Equatable {
    case pending
    case redeemed(at: Timestamp, proofsCount: Int)
    case failed(error: NutzapRedemptionError, attempts: Int, lastAttempt: Timestamp)

    private enum CodingKeys: String, CodingKey {
        case type
        case redeemedAt
        case proofsCount
        case error
        case attempts
        case lastAttempt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "pending":
            self = .pending
        case "redeemed":
            let at = try container.decode(Timestamp.self, forKey: .redeemedAt)
            let count = try container.decode(Int.self, forKey: .proofsCount)
            self = .redeemed(at: at, proofsCount: count)
        case "failed":
            let error = try container.decode(NutzapRedemptionError.self, forKey: .error)
            let attempts = try container.decode(Int.self, forKey: .attempts)
            let lastAttempt = try container.decode(Timestamp.self, forKey: .lastAttempt)
            self = .failed(error: error, attempts: attempts, lastAttempt: lastAttempt)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown status type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .pending:
            try container.encode("pending", forKey: .type)
        case let .redeemed(at, proofsCount):
            try container.encode("redeemed", forKey: .type)
            try container.encode(at, forKey: .redeemedAt)
            try container.encode(proofsCount, forKey: .proofsCount)
        case let .failed(error, attempts, lastAttempt):
            try container.encode("failed", forKey: .type)
            try container.encode(error, forKey: .error)
            try container.encode(attempts, forKey: .attempts)
            try container.encode(lastAttempt, forKey: .lastAttempt)
        }
    }
}

/// Detailed error types for nutzap redemption failures
public enum NutzapRedemptionError: Error, Sendable, Codable, Equatable {
    // Permanent errors (not retryable)
    case invalidProofs(reason: String)
    case p2pkLockedToUnknownKey(expectedPubkey: String, actualPubkey: String)
    case alreadySpent(proofIds: [String])
    case dleqVerificationFailed
    case invalidEventSignature
    case insufficientAmount(expected: Int64, actual: Int64)

    // Transient errors (retryable)
    case mintUnavailable(mint: String, error: String)
    case networkError(String)
    case temporaryMintError(String)

    // Other
    case unknownError(String)

    /// Whether this error is worth retrying
    public var isRetryable: Bool {
        switch self {
        case .mintUnavailable, .networkError, .temporaryMintError:
            return true
        default:
            return false
        }
    }

    /// User-friendly error message
    public var userFriendlyMessage: String {
        switch self {
        case let .invalidProofs(reason):
            return "Invalid proofs: \(reason)"
        case .p2pkLockedToUnknownKey:
            return "This nutzap is locked to a different key"
        case .alreadySpent:
            return "These proofs have already been spent"
        case .dleqVerificationFailed:
            return "Proof verification failed"
        case .invalidEventSignature:
            return "Invalid nutzap signature"
        case let .insufficientAmount(expected, actual):
            return "Insufficient amount: expected \(expected) sats, got \(actual) sats"
        case let .mintUnavailable(mint, _):
            return "Mint \(mint) is currently unavailable"
        case let .networkError(message):
            return "Network error: \(message)"
        case let .temporaryMintError(message):
            return "Temporary mint error: \(message)"
        case let .unknownError(message):
            return "Unknown error: \(message)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case reason
        case expectedPubkey
        case actualPubkey
        case proofIds
        case mint
        case error
        case expected
        case actual
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "invalidProofs":
            let reason = try container.decode(String.self, forKey: .reason)
            self = .invalidProofs(reason: reason)
        case "p2pkLockedToUnknownKey":
            let expected = try container.decode(String.self, forKey: .expectedPubkey)
            let actual = try container.decode(String.self, forKey: .actualPubkey)
            self = .p2pkLockedToUnknownKey(expectedPubkey: expected, actualPubkey: actual)
        case "alreadySpent":
            let proofIds = try container.decode([String].self, forKey: .proofIds)
            self = .alreadySpent(proofIds: proofIds)
        case "dleqVerificationFailed":
            self = .dleqVerificationFailed
        case "invalidEventSignature":
            self = .invalidEventSignature
        case "insufficientAmount":
            let expected = try container.decode(Int64.self, forKey: .expected)
            let actual = try container.decode(Int64.self, forKey: .actual)
            self = .insufficientAmount(expected: expected, actual: actual)
        case "mintUnavailable":
            let mint = try container.decode(String.self, forKey: .mint)
            let error = try container.decode(String.self, forKey: .error)
            self = .mintUnavailable(mint: mint, error: error)
        case "networkError":
            let error = try container.decode(String.self, forKey: .error)
            self = .networkError(error)
        case "temporaryMintError":
            let error = try container.decode(String.self, forKey: .error)
            self = .temporaryMintError(error)
        case "unknownError":
            let error = try container.decode(String.self, forKey: .error)
            self = .unknownError(error)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown error type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .invalidProofs(reason):
            try container.encode("invalidProofs", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case let .p2pkLockedToUnknownKey(expected, actual):
            try container.encode("p2pkLockedToUnknownKey", forKey: .type)
            try container.encode(expected, forKey: .expectedPubkey)
            try container.encode(actual, forKey: .actualPubkey)
        case let .alreadySpent(proofIds):
            try container.encode("alreadySpent", forKey: .type)
            try container.encode(proofIds, forKey: .proofIds)
        case .dleqVerificationFailed:
            try container.encode("dleqVerificationFailed", forKey: .type)
        case .invalidEventSignature:
            try container.encode("invalidEventSignature", forKey: .type)
        case let .insufficientAmount(expected, actual):
            try container.encode("insufficientAmount", forKey: .type)
            try container.encode(expected, forKey: .expected)
            try container.encode(actual, forKey: .actual)
        case let .mintUnavailable(mint, error):
            try container.encode("mintUnavailable", forKey: .type)
            try container.encode(mint, forKey: .mint)
            try container.encode(error, forKey: .error)
        case let .networkError(error):
            try container.encode("networkError", forKey: .type)
            try container.encode(error, forKey: .error)
        case let .temporaryMintError(error):
            try container.encode("temporaryMintError", forKey: .type)
            try container.encode(error, forKey: .error)
        case let .unknownError(error):
            try container.encode("unknownError", forKey: .type)
            try container.encode(error, forKey: .error)
        }
    }
}

/// Result of a nutzap redemption attempt
public struct NutzapRedemptionResult: Sendable {
    public let success: Bool
    public let proofsRedeemed: [CashuSwift.Proof]?
    public let error: NutzapRedemptionError?
    public let amount: Int64

    public init(success: Bool, proofsRedeemed: [CashuSwift.Proof]?, error: NutzapRedemptionError?, amount: Int64) {
        self.success = success
        self.proofsRedeemed = proofsRedeemed
        self.error = error
        self.amount = amount
    }
}

/// Filter for querying nutzaps by status
public enum NutzapStatusFilter: Sendable {
    case all
    case pending
    case redeemed
    case failed
    case retryableFailed
}

// MARK: - LocalizedError conformance

extension NutzapRedemptionError: LocalizedError {
    public var errorDescription: String? {
        return userFriendlyMessage
    }
}
