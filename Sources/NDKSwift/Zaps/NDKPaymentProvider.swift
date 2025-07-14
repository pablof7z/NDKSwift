import Foundation
import CashuSwift

// MARK: - Payment Request Types

/// An abstract request for payment, created by a Zap Protocol handler
public protocol PaymentRequest { 
    /// The amount in satoshis
    var amountSats: Int64 { get }
}

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

/// A request for funding a Nutzap - includes all accepted mints so payment provider can choose
public struct NutzapFundingRequest: PaymentRequest {
    public let amountSats: Int64
    public let recipientP2PK: String
    public let acceptedMints: [URL]  // All mints the recipient accepts
    public let comment: String?
    
    public init(amountSats: Int64, recipientP2PK: String, acceptedMints: [URL], comment: String? = nil) {
        self.amountSats = amountSats
        self.recipientP2PK = recipientP2PK
        self.acceptedMints = acceptedMints
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
    public let proofs: [CashuSwift.Proof]
    public let change: [CashuSwift.Proof]?
    public let mintURL: URL  // The mint that was actually used
    
    public init(proofs: [CashuSwift.Proof], change: [CashuSwift.Proof]? = nil, mintURL: URL) {
        self.proofs = proofs
        self.change = change
        self.mintURL = mintURL
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