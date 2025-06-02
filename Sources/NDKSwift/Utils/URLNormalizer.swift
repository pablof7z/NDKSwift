import Foundation

/// Utility for normalizing relay URLs according to Nostr conventions
public struct URLNormalizer {
    
    /// Normalizes a relay URL by ensuring proper format and consistency
    /// - Parameter url: The URL string to normalize
    /// - Returns: A normalized URL string, or nil if the URL is invalid
    public static func tryNormalizeRelayUrl(_ url: String) -> String? {
        do {
            return try normalizeRelayUrl(url)
        } catch {
            return nil
        }
    }
    
    /// Normalizes a relay URL by ensuring proper format and consistency
    /// - Parameter url: The URL string to normalize
    /// - Returns: A normalized URL string
    /// - Throws: URLNormalizationError if the URL cannot be normalized
    public static func normalizeRelayUrl(_ url: String) throws -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for obviously invalid URLs
        if normalized.contains(" ") || normalized.isEmpty || normalized.hasPrefix("://") {
            throw URLNormalizationError.invalidURL(url)
        }
        
        // Ensure proper protocol
        if !normalized.lowercased().hasPrefix("ws://") && !normalized.lowercased().hasPrefix("wss://") {
            // Default to wss:// for security
            normalized = "wss://\(normalized)"
        }
        
        // Parse URL to ensure validity and perform normalization
        guard var urlComponents = URLComponents(string: normalized),
              let host = urlComponents.host, 
              !host.isEmpty else {
            throw URLNormalizationError.invalidURL(url)
        }
        
        // Convert scheme and host to lowercase
        urlComponents.scheme = urlComponents.scheme?.lowercased()
        urlComponents.host = urlComponents.host?.lowercased()
        
        // Remove authentication (username/password)
        urlComponents.user = nil
        urlComponents.password = nil
        
        // Remove fragment (hash)
        urlComponents.fragment = nil
        
        // Remove www. prefix from hostname if present
        if let host = urlComponents.host, host.hasPrefix("www.") {
            urlComponents.host = String(host.dropFirst(4))
        }
        
        // Remove default ports
        if let port = urlComponents.port {
            if (urlComponents.scheme == "ws" && port == 80) ||
               (urlComponents.scheme == "wss" && port == 443) {
                urlComponents.port = nil
            }
        }
        
        // Reconstruct the URL ensuring proper formatting
        guard let normalizedComponents = urlComponents.url else {
            throw URLNormalizationError.invalidURL(url)
        }
        
        var normalizedURL = normalizedComponents.absoluteString
        
        // Handle query parameters - ensure the slash comes before the query
        if let queryRange = normalizedURL.range(of: "?") {
            let beforeQuery = String(normalizedURL[..<queryRange.lowerBound])
            let queryAndAfter = String(normalizedURL[queryRange.lowerBound...])
            
            if !beforeQuery.hasSuffix("/") {
                normalizedURL = beforeQuery + "/" + queryAndAfter
            }
        } else {
            // No query parameters, just ensure trailing slash
            if !normalizedURL.hasSuffix("/") {
                normalizedURL = normalizedURL + "/"
            }
        }
        
        return normalizedURL
    }
    
    /// Normalizes an array of relay URLs, removing duplicates
    /// - Parameter urls: An array of URL strings to normalize
    /// - Returns: An array of normalized, unique URL strings
    public static func normalize(_ urls: [String]) -> [String] {
        var normalized = Set<String>()
        
        for url in urls {
            if let normalizedURL = tryNormalizeRelayUrl(url) {
                normalized.insert(normalizedURL)
            }
        }
        
        return Array(normalized).sorted()
    }
}

/// Errors that can occur during URL normalization
public enum URLNormalizationError: LocalizedError {
    case invalidURL(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid relay URL: \(url)"
        }
    }
}