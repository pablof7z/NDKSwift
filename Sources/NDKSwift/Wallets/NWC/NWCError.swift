import Foundation

// MARK: - NWC Error Codes

public enum NWCErrorCode: String {
    case rateLimited = "RATE_LIMITED"
    case notImplemented = "NOT_IMPLEMENTED"
    case insufficientBalance = "INSUFFICIENT_BALANCE"
    case quotaExceeded = "QUOTA_EXCEEDED"
    case restricted = "RESTRICTED"
    case unauthorized = "UNAUTHORIZED"
    case paymentFailed = "PAYMENT_FAILED"
    case notFound = "NOT_FOUND"
    case `internal` = "INTERNAL"
    case other = "OTHER"
    
    public var userMessage: String {
        switch self {
        case .rateLimited:
            return "Too many requests. Please try again in a few seconds."
        case .notImplemented:
            return "This operation is not supported by the wallet."
        case .insufficientBalance:
            return "Insufficient balance to complete the transaction."
        case .quotaExceeded:
            return "Spending quota exceeded."
        case .restricted:
            return "You are not authorized to perform this operation."
        case .unauthorized:
            return "No wallet connected or invalid credentials."
        case .paymentFailed:
            return "Payment failed. Please check the invoice and try again."
        case .notFound:
            return "The requested resource was not found."
        case .internal:
            return "An internal error occurred."
        case .other:
            return "An unknown error occurred."
        }
    }
}

// MARK: - NWC Error

public struct NWCError: Error, LocalizedError {
    public let code: NWCErrorCode
    public let message: String
    public let context: [String: Any]
    
    public init(code: NWCErrorCode, message: String? = nil, context: [String: Any] = [:]) {
        self.code = code
        self.message = message ?? code.userMessage
        self.context = context
    }
    
    public init(responseError: NWCResponseError) {
        self.code = NWCErrorCode(rawValue: responseError.code) ?? .other
        self.message = responseError.message
        self.context = [:]
    }
    
    public var errorDescription: String? {
        return message
    }
    
    // Convert to NDKError
    public func toNDKError() -> NDKError {
        switch code {
        case .rateLimited:
            return NDKError.network("NWC_RATE_LIMITED", message, context: context)
        case .notImplemented, .restricted:
            return NDKError.protocol("NWC_NOT_SUPPORTED", message, context: context)
        case .insufficientBalance, .quotaExceeded:
            return NDKError.runtime("NWC_WALLET_ERROR", message, context: context)
        case .unauthorized:
            return NDKError.configuration("NWC_UNAUTHORIZED", message, context: context)
        case .paymentFailed:
            return NDKError.runtime("NWC_PAYMENT_FAILED", message, context: context)
        case .notFound:
            return NDKError.runtime("NWC_NOT_FOUND", message, context: context)
        case .internal, .other:
            return NDKError.runtime("NWC_INTERNAL", message, context: context)
        }
    }
    
    // Static factory methods
    public static func rateLimited(retryAfter: Int? = nil) -> NWCError {
        var context: [String: Any] = [:]
        if let retryAfter = retryAfter {
            context["retryAfter"] = retryAfter
        }
        return NWCError(code: .rateLimited, context: context)
    }
    
    public static func paymentFailed(reason: String? = nil) -> NWCError {
        return NWCError(
            code: .paymentFailed,
            message: reason ?? NWCErrorCode.paymentFailed.userMessage
        )
    }
    
    public static func invalidInvoice(_ invoice: String) -> NWCError {
        return NWCError(
            code: .other,
            message: "Invalid invoice format",
            context: ["invoice": invoice]
        )
    }
    
    public static func connectionFailed(url: String, underlyingError: Error? = nil) -> NWCError {
        var context: [String: Any] = ["url": url]
        if let error = underlyingError {
            context["underlyingError"] = error.localizedDescription
        }
        return NWCError(
            code: .internal,
            message: "Failed to connect to wallet service",
            context: context
        )
    }
    
    public static func timeout(method: String, timeoutSeconds: Int) -> NWCError {
        return NWCError(
            code: .internal,
            message: "Request timed out after \(timeoutSeconds) seconds",
            context: ["method": method, "timeout": timeoutSeconds]
        )
    }
    
    public static func invalidResponse(reason: String) -> NWCError {
        return NWCError(
            code: .internal,
            message: "Invalid response from wallet: \(reason)"
        )
    }
    
    public static func missingRequiredParameter(_ parameter: String) -> NWCError {
        return NWCError(
            code: .other,
            message: "Missing required parameter: \(parameter)",
            context: ["parameter": parameter]
        )
    }
}