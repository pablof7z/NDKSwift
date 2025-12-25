import CashuSwift
import Foundation
import NDKSwiftCore

// MARK: - Payment Types

/// Mint quote for Lightning deposits
public struct CashuMintQuote: Codable, Sendable {
    public let quoteId: String
    public let mintURL: String
    public let amount: Int64
    public let invoice: String
    public let expiry: Date
    public let requestedAt: Date

    public init(quoteId: String, mintURL: String, amount: Int64, invoice: String, expiry: Date, requestedAt: Date) {
        self.quoteId = quoteId
        self.mintURL = mintURL
        self.amount = amount
        self.invoice = invoice
        self.expiry = expiry
        self.requestedAt = requestedAt
    }
}

/// Deposit status for monitoring Lightning deposits to mint
public enum DepositStatus: Sendable, Equatable {
    case pending
    case minted(amount: Int64) // Amount successfully minted after deposit
    case expired
    case cancelled
}

// MARK: - Error Extensions

extension NDKError {
    static func invalidProof(_ message: String) -> NDKError {
        return NDKError.walletError(message: "Invalid proof: \(message)")
    }

    static func depositNotReady(_ message: String) -> NDKError {
        return NDKError.walletError(message: "Deposit not ready: \(message)")
    }
}
