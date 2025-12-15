import Foundation

/// Utility for normalizing relay URLs according to Nostr conventions
public enum URLNormalizer {
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
        // Step 1: Clean and validate input
        let cleanedURL = url.trimmed
        try validateURLString(cleanedURL)

        // Step 2: Ensure WebSocket scheme
        let urlWithScheme = ensureWebSocketScheme(cleanedURL)

        // Step 3: Parse and validate components
        var urlComponents = try parseURLComponents(urlWithScheme)

        // Step 4: Normalize components
        normalizeComponents(&urlComponents)

        // Step 5: Build final URL with trailing slash
        return try buildNormalizedURL(from: urlComponents)
    }

    // MARK: - Private Helper Methods

    /// Validates that the URL string meets basic requirements
    private static func validateURLString(_ url: String) throws {
        if url.contains(" ") || url.isEmpty || url.hasPrefix("://") {
            throw URLNormalizationError.invalidURL(url)
        }
    }

    /// Ensures the URL has a WebSocket scheme (ws:// or wss://)
    private static func ensureWebSocketScheme(_ url: String) -> String {
        if RelayConstants.WebSocketScheme.isWebSocketURL(url) {
            return url
        }
        // Default to wss:// for security
        return "\(RelayConstants.WebSocketScheme.secure)\(url)"
    }

    /// Parses URL string into components and validates structure
    private static func parseURLComponents(_ url: String) throws -> URLComponents {
        guard let urlComponents = URLComponents(string: url),
              let host = urlComponents.host,
              !host.isEmpty
        else {
            throw URLNormalizationError.invalidURL(url)
        }
        return urlComponents
    }

    /// Normalizes URL components in place
    private static func normalizeComponents(_ components: inout URLComponents) {
        // Convert to lowercase
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        // Remove authentication
        components.user = nil
        components.password = nil

        // Remove fragment
        components.fragment = nil

        // Remove www. prefix
        removeWWWPrefix(&components)

        // Remove default ports
        removeDefaultPorts(&components)
    }

    // URL normalization constants
    private enum NormalizationConstants {
        static let wwwPrefix = "www."
        static let wwwPrefixLength = 4
        static let defaultWSPort = 80
        static let defaultWSSPort = 443
    }

    /// Removes www. prefix from hostname if present
    private static func removeWWWPrefix(_ components: inout URLComponents) {
        if let host = components.host, host.hasPrefix(NormalizationConstants.wwwPrefix) {
            components.host = String(host.dropFirst(NormalizationConstants.wwwPrefixLength))
        }
    }

    /// Removes default ports (80 for ws, 443 for wss)
    private static func removeDefaultPorts(_ components: inout URLComponents) {
        if let port = components.port {
            if (components.scheme == "ws" && port == NormalizationConstants.defaultWSPort) ||
                (components.scheme == "wss" && port == NormalizationConstants.defaultWSSPort)
            {
                components.port = nil
            }
        }
    }

    /// Builds the final normalized URL with proper trailing slash
    private static func buildNormalizedURL(from components: URLComponents) throws -> String {
        guard let url = components.url else {
            throw URLNormalizationError.invalidURL("")
        }

        var normalizedURL = url.absoluteString

        // Ensure trailing slash, handling query parameters correctly
        normalizedURL = ensureTrailingSlash(normalizedURL)

        return normalizedURL
    }

    /// Ensures the URL has a trailing slash, properly handling query parameters
    private static func ensureTrailingSlash(_ url: String) -> String {
        if let queryRange = url.range(of: "?") {
            let beforeQuery = String(url[..<queryRange.lowerBound])
            let queryAndAfter = String(url[queryRange.lowerBound...])

            if !beforeQuery.hasSuffix("/") {
                return beforeQuery + "/" + queryAndAfter
            }
        } else if !url.hasSuffix("/") {
            return url + "/"
        }

        return url
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

    /// Converts WebSocket schemes to HTTP schemes for non-WebSocket operations
    /// - Parameter url: URL to convert
    /// - Returns: URL with ws:// converted to http:// and wss:// converted to https://
    public static func convertWebSocketToHTTP(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.scheme {
        case "ws":
            components.scheme = "http"
        case "wss":
            components.scheme = "https"
        default:
            return url // Return original URL if not a WebSocket scheme
        }

        return components.url
    }
}

/// Errors that can occur during URL normalization
public enum URLNormalizationError: LocalizedError {
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid relay URL: \(url)"
        }
    }
}
