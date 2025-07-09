import Foundation

// MARK: - Payment Request Types

/// An abstract request for payment, created by a Zap Protocol handler
public protocol PaymentRequest { }

/// A concrete request to pay a BOLT11 invoice
public struct LightningInvoiceRequest: PaymentRequest {
    public let invoice: String
    public let amountSats: Int64
    public let recipient: String // For display/logging
    
    public init(invoice: String, amountSats: Int64, recipient: String) {
        self.invoice = invoice
        self.amountSats = amountSats
        self.recipient = recipient
    }
}

/// A concrete request to generate Cashu proofs for a nutzap
public struct CashuProofRequest: PaymentRequest {
    public let amountSats: Int64
    public let mintURL: URL
    public let recipientP2PK: String
    public let comment: String?
    
    public init(amountSats: Int64, mintURL: URL, recipientP2PK: String, comment: String? = nil) {
        self.amountSats = amountSats
        self.mintURL = mintURL
        self.recipientP2PK = recipientP2PK
        self.comment = comment
    }
}

// MARK: - Payment Confirmation Types

/// An abstract confirmation of payment, returned by a Payment Provider
public protocol PaymentConfirmation { }

/// A concrete confirmation for a Lightning payment
public struct LightningPaymentConfirmation: PaymentConfirmation {
    public let preimage: String
    public let paymentHash: String?
    public let feePaid: Int64?
    
    public init(preimage: String, paymentHash: String? = nil, feePaid: Int64? = nil) {
        self.preimage = preimage
        self.paymentHash = paymentHash
        self.feePaid = feePaid
    }
}

/// A concrete confirmation for a Cashu payment
public struct CashuPaymentConfirmation: PaymentConfirmation {
    public let proofs: [CashuProof]
    public let change: [CashuProof]?
    
    public init(proofs: [CashuProof], change: [CashuProof]? = nil) {
        self.proofs = proofs
        self.change = change
    }
}

// MARK: - Payment Provider Protocol

/// Handles the financial transaction (funding the payment)
public protocol NDKPaymentProvider {
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

public enum PaymentError: LocalizedError {
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
        case .insufficientBalance(let available, let required):
            return "Insufficient balance: \(available) sats available, \(required) required"
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        case .userCancelled:
            return "Payment was cancelled by user"
        case .timeout:
            return "Payment timed out"
        }
    }
}