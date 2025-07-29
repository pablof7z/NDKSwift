import Foundation
import CashuSwift

// Payment types are now unified in ZapTypes.swift


/// Cashu-specific proof request implementation
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

/// Cashu payment confirmation with proof details
public struct CashuPaymentConfirmation: PaymentConfirmation {
    public let amountSats: Int64
    public let timestamp: Date
    public let proofs: [CashuSwift.Proof]
    public let change: [CashuSwift.Proof]?
    public let mintURL: URL  // The mint that was actually used

    public init(proofs: [CashuSwift.Proof], change: [CashuSwift.Proof]? = nil, mintURL: URL) {
        self.amountSats = proofs.reduce(Int64(0)) { $0 + Int64($1.amount) }
        self.timestamp = Date()
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