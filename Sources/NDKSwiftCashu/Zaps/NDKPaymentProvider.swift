import CashuSwift
import Foundation
import NDKSwiftCore

// Core payment types (PaymentRequest, PaymentConfirmation, NDKPaymentProvider, PaymentError)
// are defined in NDKSwiftCore/Payment/PaymentTypes.swift

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
    public let mintURL: URL // The mint that was actually used

    public init(proofs: [CashuSwift.Proof], change: [CashuSwift.Proof]? = nil, mintURL: URL) {
        amountSats = proofs.reduce(Int64(0)) { $0 + Int64($1.amount) }
        timestamp = Date()
        self.proofs = proofs
        self.change = change
        self.mintURL = mintURL
    }
}
