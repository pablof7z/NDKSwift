import Foundation

// MARK: - Unified Payment Types

/// Payment request protocol - represents any payment request in the system
public protocol PaymentRequest: Sendable {
    /// The amount in satoshis
    var amountSats: Int64 { get }
    /// Optional comment/message with the payment
    var comment: String? { get }
}

/// Lightning invoice payment request
public struct LightningInvoiceRequest: PaymentRequest, Sendable {
    public let invoice: String
    public let amountSats: Int64
    public let recipient: String // For display/logging
    public let comment: String?

    public init(invoice: String, amountSats: Int64, recipient: String, comment: String? = nil) {
        self.invoice = invoice
        self.amountSats = amountSats
        self.recipient = recipient
        self.comment = comment
    }
}

/// Payment confirmation protocol - represents confirmation of a completed payment
public protocol PaymentConfirmation: Sendable {
    /// Amount paid in satoshis
    var amountSats: Int64 { get }
    /// Timestamp of the payment
    var timestamp: Date { get }
}

/// Lightning payment confirmation
public struct LightningPaymentConfirmation: PaymentConfirmation, Sendable {
    public let amountSats: Int64
    public let timestamp: Date
    public let preimage: String
    public let paymentHash: String?
    public let feePaid: Int64?

    public init(amountSats: Int64, timestamp: Date, preimage: String, paymentHash: String? = nil, feePaid: Int64? = nil) {
        self.amountSats = amountSats
        self.timestamp = timestamp
        self.preimage = preimage
        self.paymentHash = paymentHash
        self.feePaid = feePaid
    }
}

// MARK: - Payment Provider Protocol

/// Handles the financial transaction (funding the payment)
public protocol NDKPaymentProvider: Sendable {
    /// A unique identifier for the provider (e.g., "nwc_wallet", "cashu_wallet", "qr_code")
    var id: String { get }

    /// Human-readable name for UI display
    var displayName: String { get }

    /// Check if this provider is currently available/configured
    func isAvailable() async -> Bool

    /// Check if this provider can fulfill the given payment request
    func canFulfill(_ request: PaymentRequest) async -> Bool

    /// Fulfill the payment request and return confirmation data
    func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation

    /// Get the current balance (optional)
    func getBalance() async throws -> Int64?
}

// MARK: - Payment Errors

public enum PaymentError: LocalizedError, Sendable {
    case providerNotAvailable
    case cannotFulfillRequest
    case insufficientBalance(available: Int64, required: Int64)
    case paymentFailed(reason: String)
    case userCancelled
    case timeout

    public var errorDescription: String? {
        switch self {
        case .providerNotAvailable:
            return "Payment provider is not available"
        case .cannotFulfillRequest:
            return "Provider cannot fulfill this payment request"
        case let .insufficientBalance(available, required):
            return "Insufficient balance: \(available) sats available, \(required) required"
        case let .paymentFailed(reason):
            return "Payment failed: \(reason)"
        case .userCancelled:
            return "Payment was cancelled by user"
        case .timeout:
            return "Payment timed out"
        }
    }
}
