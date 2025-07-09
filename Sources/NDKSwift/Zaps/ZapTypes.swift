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