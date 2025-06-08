import Foundation

/// Base protocol for all NDK errors
public protocol NDKErrorProtocol: LocalizedError {
    var errorCode: String { get }
    var errorContext: [String: Any] { get }
    var underlyingError: Error? { get }
}

/// Unified error system for NDKSwift
public struct NDKUnifiedError: NDKErrorProtocol {
    public let category: ErrorCategory
    public let specific: SpecificError
    public let context: [String: Any]
    public let underlying: Error?
    
    public var errorCode: String {
        "\(category.rawValue).\(specific.code)"
    }
    
    public var errorContext: [String: Any] {
        context
    }
    
    public var underlyingError: Error? {
        underlying
    }
    
    public var errorDescription: String? {
        var description = specific.message
        
        // Add context if available
        if !context.isEmpty {
            let contextStr = context.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            description += " [\(contextStr)]"
        }
        
        // Add underlying error if available
        if let underlying = underlying {
            description += " Caused by: \(underlying.localizedDescription)"
        }
        
        return description
    }
    
    /// Error categories for grouping related errors
    public enum ErrorCategory: String {
        case validation = "validation"
        case crypto = "crypto"
        case network = "network"
        case storage = "storage"
        case `protocol` = "protocol"
        case configuration = "config"
        case runtime = "runtime"
    }
    
    /// Specific error types
    public struct SpecificError {
        public let code: String
        public let message: String
        
        // MARK: - Validation Errors
        public static let invalidPublicKey = SpecificError(
            code: "invalid_public_key",
            message: "Invalid public key format"
        )
        
        public static let invalidPrivateKey = SpecificError(
            code: "invalid_private_key",
            message: "Invalid private key format"
        )
        
        public static let invalidEventID = SpecificError(
            code: "invalid_event_id",
            message: "Invalid event ID"
        )
        
        public static let invalidSignature = SpecificError(
            code: "invalid_signature",
            message: "Invalid signature"
        )
        
        public static let invalidInput = SpecificError(
            code: "invalid_input",
            message: "Invalid input provided"
        )
        
        public static let invalidFilter = SpecificError(
            code: "invalid_filter",
            message: "Invalid filter configuration"
        )
        
        // MARK: - Crypto Errors
        public static let signingFailed = SpecificError(
            code: "signing_failed",
            message: "Failed to sign data"
        )
        
        public static let verificationFailed = SpecificError(
            code: "verification_failed",
            message: "Failed to verify signature"
        )
        
        public static let encryptionFailed = SpecificError(
            code: "encryption_failed",
            message: "Failed to encrypt data"
        )
        
        public static let decryptionFailed = SpecificError(
            code: "decryption_failed",
            message: "Failed to decrypt data"
        )
        
        public static let keyDerivationFailed = SpecificError(
            code: "key_derivation_failed",
            message: "Failed to derive key"
        )
        
        // MARK: - Network Errors
        public static let connectionFailed = SpecificError(
            code: "connection_failed",
            message: "Failed to establish connection"
        )
        
        public static let connectionLost = SpecificError(
            code: "connection_lost",
            message: "Connection was lost"
        )
        
        public static let timeout = SpecificError(
            code: "timeout",
            message: "Operation timed out"
        )
        
        public static let serverError = SpecificError(
            code: "server_error",
            message: "Server returned an error"
        )
        
        public static let unauthorized = SpecificError(
            code: "unauthorized",
            message: "Unauthorized access"
        )
        
        // MARK: - Storage Errors
        public static let cacheFailed = SpecificError(
            code: "cache_failed",
            message: "Cache operation failed"
        )
        
        public static let diskFull = SpecificError(
            code: "disk_full",
            message: "Insufficient storage space"
        )
        
        public static let fileNotFound = SpecificError(
            code: "file_not_found",
            message: "File not found"
        )
        
        public static let corruptedData = SpecificError(
            code: "corrupted_data",
            message: "Data is corrupted"
        )
        
        // MARK: - Protocol Errors
        public static let invalidMessage = SpecificError(
            code: "invalid_message",
            message: "Invalid protocol message"
        )
        
        public static let unsupportedVersion = SpecificError(
            code: "unsupported_version",
            message: "Protocol version not supported"
        )
        
        public static let subscriptionFailed = SpecificError(
            code: "subscription_failed",
            message: "Failed to create subscription"
        )
        
        // MARK: - Configuration Errors
        public static let notConfigured = SpecificError(
            code: "not_configured",
            message: "Required configuration is missing"
        )
        
        public static let invalidConfiguration = SpecificError(
            code: "invalid_configuration",
            message: "Configuration is invalid"
        )
        
        // MARK: - Runtime Errors
        public static let notImplemented = SpecificError(
            code: "not_implemented",
            message: "Feature not implemented"
        )
        
        public static let cancelled = SpecificError(
            code: "cancelled",
            message: "Operation was cancelled"
        )
        
        public static let unknown = SpecificError(
            code: "unknown",
            message: "An unknown error occurred"
        )
    }
    
    // MARK: - Convenience Initializers
    
    public static func validation(
        _ specific: SpecificError,
        context: [String: Any] = [:],
        underlying: Error? = nil
    ) -> NDKUnifiedError {
        NDKUnifiedError(
            category: .validation,
            specific: specific,
            context: context,
            underlying: underlying
        )
    }
    
    public static func crypto(
        _ specific: SpecificError,
        context: [String: Any] = [:],
        underlying: Error? = nil
    ) -> NDKUnifiedError {
        NDKUnifiedError(
            category: .crypto,
            specific: specific,
            context: context,
            underlying: underlying
        )
    }
    
    public static func network(
        _ specific: SpecificError,
        context: [String: Any] = [:],
        underlying: Error? = nil
    ) -> NDKUnifiedError {
        NDKUnifiedError(
            category: .network,
            specific: specific,
            context: context,
            underlying: underlying
        )
    }
    
    public static func storage(
        _ specific: SpecificError,
        context: [String: Any] = [:],
        underlying: Error? = nil
    ) -> NDKUnifiedError {
        NDKUnifiedError(
            category: .storage,
            specific: specific,
            context: context,
            underlying: underlying
        )
    }
    
    public static func runtime(
        _ specific: SpecificError,
        context: [String: Any] = [:],
        underlying: Error? = nil
    ) -> NDKUnifiedError {
        NDKUnifiedError(
            category: .runtime,
            specific: specific,
            context: context,
            underlying: underlying
        )
    }
}

/// Error recovery suggestions
public struct ErrorRecovery {
    public let action: String
    public let handler: () async throws -> Void
    
    public init(action: String, handler: @escaping () async throws -> Void) {
        self.action = action
        self.handler = handler
    }
}

/// Extension to add recovery suggestions to errors
extension NDKUnifiedError {
    public func withRecovery(_ suggestions: [ErrorRecovery]) -> RecoverableError {
        RecoverableError(error: self, recoverySuggestions: suggestions)
    }
}

/// Wrapper for errors with recovery suggestions
public struct RecoverableError: NDKErrorProtocol {
    public let error: NDKUnifiedError
    public let recoverySuggestions: [ErrorRecovery]
    
    public var errorCode: String { error.errorCode }
    public var errorContext: [String: Any] { error.errorContext }
    public var underlyingError: Error? { error.underlyingError }
    
    public var errorDescription: String? {
        var description = error.errorDescription ?? ""
        if !recoverySuggestions.isEmpty {
            description += "\n\nRecovery options:"
            for (index, suggestion) in recoverySuggestions.enumerated() {
                description += "\n  \(index + 1). \(suggestion.action)"
            }
        }
        return description
    }
}

/// Backward compatibility bridge for existing NDKError
extension NDKError {
    /// Convert legacy NDKError to unified error
    public var unified: NDKUnifiedError {
        switch self {
        case .invalidPublicKey:
            return .validation(.invalidPublicKey)
        case .invalidPrivateKey:
            return .validation(.invalidPrivateKey)
        case .invalidEventID:
            return .validation(.invalidEventID)
        case .invalidSignature:
            return .validation(.invalidSignature)
        case .signingFailed:
            return .crypto(.signingFailed)
        case .verificationFailed:
            return .crypto(.verificationFailed)
        case .invalidFilter:
            return .validation(.invalidFilter)
        case let .relayConnectionFailed(message):
            return .network(.connectionFailed, context: ["message": message])
        case let .subscriptionFailed(message):
            return .network(.subscriptionFailed, context: ["message": message])
        case let .cacheFailed(message):
            return .storage(.cacheFailed, context: ["message": message])
        case .timeout:
            return .network(.timeout)
        case .cancelled:
            return .runtime(.cancelled)
        case .notImplemented:
            return .runtime(.notImplemented)
        case let .custom(message):
            return .runtime(.unknown, context: ["message": message])
        case let .validation(message):
            return .validation(.invalidInput, context: ["message": message])
        case .walletNotConfigured:
            return .runtime(.notConfigured, context: ["component": "wallet"])
        case .insufficientBalance:
            return .validation(.invalidInput, context: ["reason": "insufficient_balance"])
        case .powGenerationFailed:
            return .crypto(.signingFailed, context: ["operation": "pow_generation"])
        case .invalidPaymentRequest:
            return .validation(.invalidInput, context: ["type": "payment_request"])
        case let .signerError(message):
            return .crypto(.signingFailed, context: ["message": message])
        case let .invalidEvent(message):
            return .validation(.invalidInput, context: ["type": "event", "message": message])
        case let .invalidInput(message):
            return .validation(.invalidInput, context: ["message": message])
        }
    }
}

/// Convenience type alias for Result types
public typealias NDKResult<T> = Result<T, NDKUnifiedError>

/// Extension for better error handling in async contexts
extension Result where Failure == NDKUnifiedError {
    /// Map the success value asynchronously
    public func asyncMap<U>(_ transform: (Success) async throws -> U) async -> Result<U, NDKUnifiedError> {
        switch self {
        case let .success(value):
            do {
                let transformed = try await transform(value)
                return .success(transformed)
            } catch let error as NDKUnifiedError {
                return .failure(error)
            } catch {
                return .failure(.runtime(.unknown, underlying: error))
            }
        case let .failure(error):
            return .failure(error)
        }
    }
    
    /// Recover from specific errors
    public func recover(from category: NDKUnifiedError.ErrorCategory, with recovery: () async throws -> Success) async -> Result<Success, NDKUnifiedError> {
        switch self {
        case .success:
            return self
        case let .failure(error) where error.category == category:
            do {
                let recovered = try await recovery()
                return .success(recovered)
            } catch let error as NDKUnifiedError {
                return .failure(error)
            } catch {
                return .failure(.runtime(.unknown, underlying: error))
            }
        case .failure:
            return self
        }
    }
}