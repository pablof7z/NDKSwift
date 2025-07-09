import Foundation

// MARK: - Core Error Type

/// Idiomatic Swift error enum for NDKSwift
public enum NDKError: LocalizedError {
    // Validation errors
    case invalidPublicKey(String)
    case invalidPrivateKey(String)
    case invalidEventID(String)
    case invalidSignature(String)
    case invalidFilter(String)
    case invalidInput(message: String)
    
    // Crypto errors
    case signingFailed(String, underlying: Error? = nil)
    case verificationFailed(String, underlying: Error? = nil)
    case encryptionFailed(String, underlying: Error? = nil)
    case decryptionFailed(String, underlying: Error? = nil)
    case keyDerivationFailed(String, underlying: Error? = nil)
    
    // Network errors
    case connectionFailed(relay: String, message: String, underlying: Error? = nil)
    case connectionLost(relay: String, message: String)
    case timeout(operation: String, seconds: Int)
    case serverError(relay: String, code: Int, message: String?)
    case unauthorized(relay: String, message: String)
    case relayError(relay: String, message: String)
    
    // Storage errors
    case cacheFailed(operation: String, underlying: Error? = nil)
    case diskFull
    case fileNotFound(path: String)
    case corruptedData(path: String)
    
    // Protocol errors
    case invalidMessage(String)
    case unsupportedVersion(String)
    case subscriptionFailed(String)
    case protocolViolation(String)
    
    // Configuration errors
    case notConfigured(String)
    case invalidConfiguration(String)
    
    // Runtime errors
    case notImplemented(String)
    case cancelled
    case unknown(String, underlying: Error? = nil)
    
    // Wallet errors (NWC)
    case walletRateLimited(retryAfter: Int?)
    case walletNotImplemented(method: String)
    case insufficientBalance(amount: Int64?)
    case walletQuotaExceeded
    case walletRestricted(reason: String)
    case walletUnauthorized
    case paymentFailed(reason: String)
    case walletNotFound(resource: String)
    case walletError(message: String)
    
    // File/Blossom errors
    case invalidURL(String)
    case invalidResponse(from: String)
    case fileTooLarge(maxSize: Int64)
    case unsupportedMimeType(String)
    case blobNotFound(sha256: String)
    case uploadFailed(reason: String)
    case invalidSHA256(String)
    
    // Serialization errors
    case serializationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        // Validation
        case .invalidPublicKey(let key):
            return "Invalid public key: \(key)"
        case .invalidPrivateKey(let key):
            return "Invalid private key: \(key)"
        case .invalidEventID(let id):
            return "Invalid event ID: \(id)"
        case .invalidSignature(let sig):
            return "Invalid signature: \(sig)"
        case .invalidFilter(let filter):
            return "Invalid filter: \(filter)"
        case .invalidInput(let message):
            return message
            
        // Crypto
        case .signingFailed(let message, let underlying):
            return underlying != nil ? "\(message): \(underlying!.localizedDescription)" : message
        case .verificationFailed(let message, let underlying):
            return underlying != nil ? "\(message): \(underlying!.localizedDescription)" : message
        case .encryptionFailed(let message, let underlying):
            return underlying != nil ? "\(message): \(underlying!.localizedDescription)" : message
        case .decryptionFailed(let message, let underlying):
            return underlying != nil ? "\(message): \(underlying!.localizedDescription)" : message
        case .keyDerivationFailed(let message, let underlying):
            return underlying != nil ? "\(message): \(underlying!.localizedDescription)" : message
            
        // Network
        case .connectionFailed(let relay, let message, let underlying):
            return underlying != nil ? "Connection to \(relay) failed: \(message) - \(underlying!.localizedDescription)" : "Connection to \(relay) failed: \(message)"
        case .connectionLost(let relay, let message):
            return "Connection to \(relay) lost: \(message)"
        case .timeout(let operation, let seconds):
            return "\(operation) timed out after \(seconds) seconds"
        case .serverError(let relay, let code, let message):
            return "Server error from \(relay) (\(code)): \(message ?? "Unknown error")"
        case .unauthorized(let relay, let message):
            return "Unauthorized on \(relay): \(message)"
        case .relayError(let relay, let message):
            return "Relay error from \(relay): \(message)"
            
        // Storage
        case .cacheFailed(let operation, let underlying):
            return underlying != nil ? "Cache \(operation) failed: \(underlying!.localizedDescription)" : "Cache \(operation) failed"
        case .diskFull:
            return "Insufficient storage space"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .corruptedData(let path):
            return "Corrupted data at: \(path)"
            
        // Protocol
        case .invalidMessage(let message):
            return "Invalid protocol message: \(message)"
        case .unsupportedVersion(let version):
            return "Unsupported protocol version: \(version)"
        case .subscriptionFailed(let reason):
            return "Subscription failed: \(reason)"
        case .protocolViolation(let message):
            return "Protocol violation: \(message)"
            
        // Configuration
        case .notConfigured(let component):
            return "\(component) is not configured"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
            
        // Runtime
        case .notImplemented(let feature):
            return "\(feature) is not implemented"
        case .cancelled:
            return "Operation was cancelled"
        case .unknown(let message, let underlying):
            return underlying != nil ? "\(message): \(underlying!.localizedDescription)" : message
            
        // Wallet
        case .walletRateLimited(let retryAfter):
            return retryAfter != nil ? "Too many requests. Retry after \(retryAfter!) seconds." : "Too many requests. Please try again later."
        case .walletNotImplemented(let method):
            return "\(method) is not supported by the wallet"
        case .insufficientBalance(let amount):
            return amount != nil ? "Insufficient balance (need \(amount!) sats)" : "Insufficient balance"
        case .walletQuotaExceeded:
            return "Spending quota exceeded"
        case .walletRestricted(let reason):
            return "Wallet restricted: \(reason)"
        case .walletUnauthorized:
            return "No wallet connected or invalid credentials"
        case .paymentFailed(let reason):
            return "Payment failed: \(reason)"
        case .walletNotFound(let resource):
            return "Wallet resource not found: \(resource)"
        case .walletError(let message):
            return message
            
        // File/Blossom
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse(let from):
            return "Invalid response from \(from)"
        case .fileTooLarge(let maxSize):
            return "File exceeds maximum size of \(maxSize) bytes"
        case .unsupportedMimeType(let type):
            return "Unsupported MIME type: \(type)"
        case .blobNotFound(let sha256):
            return "Blob not found: \(sha256)"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .invalidSHA256(let hash):
            return "Invalid SHA256 hash: \(hash)"
        case .serializationFailed(let message):
            return "Serialization failed: \(message)"
        }
    }
}

// MARK: - Subscription State

public enum NDKSubscriptionState: Equatable, Sendable {
    case pending
    case active
    case inactive
    case closed
}

// MARK: - Publication Status

public enum PublicationStatus: Equatable, Sendable {
    case notPublished
    case publishing
    case published
    case failed(String)
}
