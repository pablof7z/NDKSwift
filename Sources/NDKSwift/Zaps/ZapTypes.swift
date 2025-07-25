import Foundation

/// Type of zap
public enum ZapType {
    case lightning
    case nutzap
}

// MARK: - Unified Payment Types

/// Payment request protocol - represents any payment request in the system
public protocol PaymentRequest {
    /// The amount in satoshis
    var amountSats: Int64 { get }
    /// Optional comment/message with the payment
    var comment: String? { get }
}

/// Lightning invoice payment request
public struct LightningInvoiceRequest: PaymentRequest {
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

/// Nutzap payment request - includes accepted mints
public struct NutzapPaymentRequest: PaymentRequest {
    public let amountSats: Int64
    public let recipientPubkey: String  // Nostr pubkey for the p tag
    public let recipientP2PK: String    // P2PK key for locking proofs
    public let acceptedMints: [URL]     // All mints the recipient accepts
    public let comment: String?

    public init(amountSats: Int64, recipientPubkey: String, recipientP2PK: String, acceptedMints: [URL], comment: String? = nil) {
        self.amountSats = amountSats
        self.recipientPubkey = recipientPubkey  // Nostr pubkey
        self.recipientP2PK = recipientP2PK      // P2PK key
        self.acceptedMints = acceptedMints
        self.comment = comment
    }
}

/// Payment confirmation protocol - represents confirmation of a completed payment
public protocol PaymentConfirmation {
    /// Amount paid in satoshis
    var amountSats: Int64 { get }
    /// Timestamp of the payment
    var timestamp: Date { get }
}

/// Lightning payment confirmation
public struct LightningPaymentConfirmation: PaymentConfirmation {
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

/// Nutzap payment confirmation
public struct NutzapConfirmation: PaymentConfirmation {
    public let amountSats: Int64
    public let timestamp: Date
    public let nutzapEvent: NDKEvent
    public let mintUsed: URL

    public init(amountSats: Int64, timestamp: Date, nutzapEvent: NDKEvent, mintUsed: URL) {
        self.amountSats = amountSats
        self.timestamp = timestamp
        self.nutzapEvent = nutzapEvent
        self.mintUsed = mintUsed
    }
}

/// Errors that can occur during zapping
public enum ZapError: LocalizedError {
    case recipientDoesNotSupportZaps
    case noLNURL
    case invalidLNURL(String)
    case invoiceFetchFailed(String)
    case lnurlProviderError(String)
    case nutzapPreferencesNotFound
    case invalidMint
    case invalidPaymentRequest
    case invalidPaymentConfirmation
    case noWalletConfigured
    case paymentFailed(String)
    case timeoutWaitingForReceipt
    case invalidZapReceipt
    // Mint-specific errors
    case mintConnectionFailed(mint: String, reason: String)
    case mintQuoteFailed(mint: String, reason: String)
    case mintTokenCreationFailed(mint: String, reason: String)
    case allMintsFailed(attempts: Int)
    case noCommonMints(wallet: [String], recipient: [String])
    case endpointDoesNotSupportZaps
    case amountOutOfRange(min: Int64, max: Int64)
    case signerNotAvailable

    public var errorDescription: String? {
        switch self {
        case .recipientDoesNotSupportZaps:
            return "Recipient does not support zaps"
        case .noLNURL:
            return "Recipient has no Lightning address configured"
        case .invalidLNURL(let details):
            return "Invalid LNURL: \(details)"
        case .invoiceFetchFailed(let reason):
            return ErrorMessageConstants.operationFailed("fetch invoice", reason: reason)
        case .lnurlProviderError(let message):
            return "LNURL provider error: \(message)"
        case .nutzapPreferencesNotFound:
            return "Recipient has not configured Nutzap preferences"
        case .invalidMint:
            return "No valid mint found"
        case .invalidPaymentRequest:
            return "Invalid payment request"
        case .invalidPaymentConfirmation:
            return "Invalid payment confirmation"
        case .noWalletConfigured:
            return "No wallet configured for payment"
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        case .timeoutWaitingForReceipt:
            return "Timeout waiting for zap receipt"
        case .invalidZapReceipt:
            return "Invalid zap receipt"
        case .mintConnectionFailed(let mint, let reason):
            return ErrorMessageConstants.operationFailed("connect to mint \(mint)", reason: reason)
        case .mintQuoteFailed(let mint, let reason):
            return ErrorMessageConstants.operationFailed("get quote from mint \(mint)", reason: reason)
        case .mintTokenCreationFailed(let mint, let reason):
            return ErrorMessageConstants.operationFailed("create tokens at mint \(mint)", reason: reason)
        case .allMintsFailed(let attempts):
            return "All \(attempts) mint(s) failed to process the payment"
        case .noCommonMints(let wallet, let recipient):
            return "No common mints between wallet (\(wallet.joined(separator: ", "))) and recipient (\(recipient.joined(separator: ", ")))"
        case .endpointDoesNotSupportZaps:
            return "Endpoint does not support zaps"
        case .amountOutOfRange(let min, let max):
            return "Amount out of range: \(min) - \(max) sats"
        case .signerNotAvailable:
            return "No signer available to create zap request"
        }
    }
}

/// Result of a zap operation
public struct ZapResult {
    public let type: ZapType
    public let amountSats: Int64
    public let receiptEvent: NDKEvent?
    public let nutzapEvent: NDKEvent?

    public init(
        type: ZapType,
        amountSats: Int64,
        receiptEvent: NDKEvent? = nil,
        nutzapEvent: NDKEvent? = nil
    ) {
        self.type = type
        self.amountSats = amountSats
        self.receiptEvent = receiptEvent
        self.nutzapEvent = nutzapEvent
    }
}