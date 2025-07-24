import Foundation

/// Centralized error message constants and helpers to ensure consistency
public enum ErrorMessageConstants {
    
    // MARK: - Common Error Prefixes
    
    /// Failed to perform an operation
    /// - Parameter operation: The operation that failed
    /// - Returns: Error message like "Failed to {operation}"
    public static func failedTo(_ operation: String) -> String {
        "Failed to \(operation)"
    }
    
    /// Invalid resource or parameter
    /// - Parameter what: What is invalid
    /// - Returns: Error message like "Invalid {what}"
    public static func invalid(_ what: String) -> String {
        "Invalid \(what)"
    }
    
    /// Missing resource or parameter
    /// - Parameter what: What is missing
    /// - Returns: Error message like "Missing {what}"
    public static func missing(_ what: String) -> String {
        "Missing \(what)"
    }
    
    /// Unable to perform an operation
    /// - Parameter operation: The operation that couldn't be performed
    /// - Returns: Error message like "Unable to {operation}"
    public static func unableTo(_ operation: String) -> String {
        "Unable to \(operation)"
    }
    
    /// Not found error
    /// - Parameter what: What was not found
    /// - Returns: Error message like "{what} not found"
    public static func notFound(_ what: String) -> String {
        "\(what) not found"
    }
    
    /// Failed to parse
    public static let failedToParse = "Failed to parse"
    
    // MARK: - Specific Error Messages
    
    /// Common error messages used throughout the codebase
    public struct Messages {
        /// Signer-related errors
        public static let noSignerConfigured = "No signer configured"
        public static let noSignerAvailable = "No signer available"
        public static let signerNotAvailable = "Signer not available"
        
        /// Connection errors
        public static let notConnected = "Not connected"
        public static let connectionFailed = "Connection failed"
        public static let connectionLost = "Connection lost"
        public static let notConnectedToRelay = "Not connected to relay"
        public static let connectionClosed = "Connection closed"
        
        /// Configuration errors
        public static let notConfigured = "Not configured"
        public static let invalidConfiguration = "Invalid configuration"
        public static let missingConfiguration = "Missing configuration"
        
        /// Validation errors
        public static let invalidFormat = "Invalid format"
        public static let invalidInput = "Invalid input"
        public static let invalidData = "Invalid data"
        public static let invalidResponse = "Invalid response"
        public static let invalidRequest = "Invalid request"
        public static let invalidContent = "Invalid content"
        
        /// Network errors
        public static let networkError = "Network error"
        public static let requestFailed = "Request failed"
        public static let timeout = "Request timed out"
        public static let serverError = "Server error"
        
        /// Authentication errors
        public static let authenticationFailed = "Authentication failed"
        
        /// Crypto errors
        public static let signingFailed = "Signing failed"
        public static let verificationFailed = "Verification failed"
        public static let encryptionFailed = "Encryption failed"
        public static let decryptionFailed = "Decryption failed"
        
        /// Storage errors
        public static let diskFull = "Insufficient storage space"
        public static let cacheFailed = "Cache operation failed"
        public static let fileNotFound = "File not found"
        public static let corruptedData = "Corrupted data"
        
        /// Wallet errors
        public static let insufficientBalance = "Insufficient balance"
        public static let walletNotConnected = "Wallet not connected"
        public static let paymentFailed = "Payment failed"
        public static let quotaExceeded = "Quota exceeded"
        
        /// General errors
        public static let unknownError = "Unknown error"
        public static let cancelled = "Operation cancelled"
    }
    
    // MARK: - Error Context Helpers
    
    /// Create an error message with context
    /// - Parameters:
    ///   - message: The base error message
    ///   - context: Additional context
    /// - Returns: Formatted error message
    public static func withContext(_ message: String, context: String) -> String {
        "\(message): \(context)"
    }
    
    /// Create an error message with a reason
    /// - Parameters:
    ///   - message: The base error message
    ///   - reason: The reason for the error
    /// - Returns: Formatted error message
    public static func withReason(_ message: String, reason: String) -> String {
        "\(message) - \(reason)"
    }
    
    /// Create an error message for relay-specific errors
    /// - Parameters:
    ///   - relay: The relay URL
    ///   - message: The error message
    /// - Returns: Formatted error message
    public static func relayError(relay: String, message: String) -> String {
        "Relay \(relay): \(message)"
    }
    
    /// Create an error message for operation failures
    /// - Parameters:
    ///   - operation: The operation that failed
    ///   - reason: The reason for failure (optional)
    /// - Returns: Formatted error message
    public static func operationFailed(_ operation: String, reason: String? = nil) -> String {
        if let reason = reason {
            return failedTo(operation) + " - \(reason)"
        }
        return failedTo(operation)
    }
}