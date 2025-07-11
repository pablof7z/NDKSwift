import Foundation

/// Type of zap
public enum ZapType {
    case lightning
    case nutzap
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
    
    public var errorDescription: String? {
        switch self {
        case .recipientDoesNotSupportZaps:
            return "Recipient does not support zaps"
        case .noLNURL:
            return "Recipient has no Lightning address configured"
        case .invalidLNURL(let details):
            return "Invalid LNURL: \(details)"
        case .invoiceFetchFailed(let reason):
            return "Failed to fetch invoice: \(reason)"
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
            return "Failed to connect to mint \(mint): \(reason)"
        case .mintQuoteFailed(let mint, let reason):
            return "Failed to get quote from mint \(mint): \(reason)"
        case .mintTokenCreationFailed(let mint, let reason):
            return "Failed to create tokens at mint \(mint): \(reason)"
        case .allMintsFailed(let attempts):
            return "All \(attempts) mint(s) failed to process the payment"
        case .noCommonMints(let wallet, let recipient):
            return "No common mints between wallet (\(wallet.joined(separator: ", "))) and recipient (\(recipient.joined(separator: ", ")))"
        case .endpointDoesNotSupportZaps:
            return "Endpoint does not support zaps"
        case .amountOutOfRange(let min, let max):
            return "Amount out of range: \(min) - \(max) sats"
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