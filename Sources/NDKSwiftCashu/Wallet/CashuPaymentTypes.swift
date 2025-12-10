import Foundation
import NDKSwiftCore

// MARK: - Payment Route Types

/// Represents a payment route decision
public enum PaymentRoute {
    /// Direct payment using a mint that both parties accept
    case direct(mint: String)

    /// Cross-mint transfer required
    case crossMint(sourceMint: String, targetMint: String, estimatedFee: Int64?)

    /// Payment is impossible
    case impossible(reason: String)

    /// Check if this route requires a cross-mint transfer
    public var requiresTransfer: Bool {
        if case .crossMint = self {
            return true
        }
        return false
    }

    /// Get the mint to use for payment (nil if impossible)
    public var paymentMint: String? {
        switch self {
        case .direct(let mint):
            return mint
        case .crossMint(_, let targetMint, _):
            return targetMint
        case .impossible:
            return nil
        }
    }
}

/// Result of a cross-mint transfer operation
public struct TransferResult {
    public let amountTransferred: Int64
    public let feePaid: Int64
    public let preimage: String
    public let sourceMint: URL
    public let destinationMint: URL

    public init(amountTransferred: Int64, feePaid: Int64, preimage: String, sourceMint: URL, destinationMint: URL) {
        self.amountTransferred = amountTransferred
        self.feePaid = feePaid
        self.preimage = preimage
        self.sourceMint = sourceMint
        self.destinationMint = destinationMint
    }
}