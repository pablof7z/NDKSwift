import Foundation

/// URL utility functions for common URL operations
public enum URLUtils {
    /// Validates a URL string and returns a URL instance, throwing NDKError.invalidURL if invalid
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A valid URL instance
    /// - Throws: NDKError.invalidURL if the URL string is invalid
    public static func validateURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString) else {
            throw NDKError.invalidURL(urlString)
        }
        return url
    }
    
    /// Safely creates a URL from a string, returning nil if invalid
    /// - Parameter urlString: The URL string to convert
    /// - Returns: A URL instance or nil if invalid
    public static func safeURL(_ urlString: String) -> URL? {
        return URL(string: urlString)
    }
}