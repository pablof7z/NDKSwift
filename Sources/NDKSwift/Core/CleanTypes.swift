import Foundation

// MARK: - Core Error Type (replacing NDKError entirely)

/// Unified error system for NDKSwift
public struct NDKError: LocalizedError {
    public let category: ErrorCategory
    public let code: String
    public let message: String
    public let context: [String: Any]
    public let underlying: Error?
    
    public var errorDescription: String? {
        var description = message
        
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
    
    // MARK: - Factory Methods
    
    public static func validation(_ code: String, _ message: String, context: [String: Any] = [:], underlying: Error? = nil) -> NDKError {
        NDKError(category: .validation, code: code, message: message, context: context, underlying: underlying)
    }
    
    public static func crypto(_ code: String, _ message: String, context: [String: Any] = [:], underlying: Error? = nil) -> NDKError {
        NDKError(category: .crypto, code: code, message: message, context: context, underlying: underlying)
    }
    
    public static func network(_ code: String, _ message: String, context: [String: Any] = [:], underlying: Error? = nil) -> NDKError {
        NDKError(category: .network, code: code, message: message, context: context, underlying: underlying)
    }
    
    public static func storage(_ code: String, _ message: String, context: [String: Any] = [:], underlying: Error? = nil) -> NDKError {
        NDKError(category: .storage, code: code, message: message, context: context, underlying: underlying)
    }
    
    public static func `protocol`(_ code: String, _ message: String, context: [String: Any] = [:], underlying: Error? = nil) -> NDKError {
        NDKError(category: .protocol, code: code, message: message, context: context, underlying: underlying)
    }
    
    public static func configuration(_ code: String, _ message: String, context: [String: Any] = [:], underlying: Error? = nil) -> NDKError {
        NDKError(category: .configuration, code: code, message: message, context: context, underlying: underlying)
    }
    
    public static func runtime(_ code: String, _ message: String, context: [String: Any] = [:], underlying: Error? = nil) -> NDKError {
        NDKError(category: .runtime, code: code, message: message, context: context, underlying: underlying)
    }
}

// MARK: - Subscription State

public enum NDKSubscriptionState: Equatable {
    case pending
    case active
    case inactive
    case closed
}

// MARK: - Cache Strategy

public enum CacheStrategy {
    case cacheOnly
    case relayOnly
    case cacheFirst
    case relayFirst
}

// MARK: - Publication Status

public enum PublicationStatus: Equatable {
    case notPublished
    case publishing
    case published
    case failed(String)
}