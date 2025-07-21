import Foundation

/// LNURL Error types
public enum LNURLError: LocalizedError {
    case invalidFormat(String)
    case networkError(Error)
    case invalidResponse(String)
    case decodingError(String)
    case unsupportedProtocol
    case noProviderPubkey
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let detail):
            return "Invalid LNURL format: \(detail)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let detail):
            return "Invalid LNURL response: \(detail)"
        case .decodingError(let detail):
            return "Failed to decode LNURL data: \(detail)"
        case .unsupportedProtocol:
            return "LNURL protocol not supported"
        case .noProviderPubkey:
            return "No provider pubkey found in LNURL metadata"
        }
    }
}

/// LNURL Pay Request response from the service
public struct LNURLPayResponse: Codable {
    /// URL to make the payment request to
    public let callback: String
    
    /// Maximum sendable amount in millisatoshis
    public let maxSendable: Int64
    
    /// Minimum sendable amount in millisatoshis
    public let minSendable: Int64
    
    /// Metadata about the payment
    public let metadata: String
    
    /// Comment allowed length (optional)
    public let commentAllowed: Int?
    
    /// Tag indicating this is a payRequest
    public let tag: String
    
    /// Whether this service allows Nostr integration
    public let allowsNostr: Bool?
    
    /// Nostr pubkey of the provider (optional)
    public let nostrPubkey: String?
}

/// Parsed LNURL metadata entry
public struct LNURLMetadataEntry {
    public let type: String
    public let value: String
}

/// Result of LNURL resolution
public struct LNURLResolutionResult {
    /// The provider's Nostr pubkey if available
    public let providerPubkey: String?
    
    /// The full LNURL pay response
    public let payResponse: LNURLPayResponse
    
    /// Parsed metadata entries
    public let metadata: [LNURLMetadataEntry]
}