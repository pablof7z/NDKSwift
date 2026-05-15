import Foundation

/// URL utility functions for common URL operations.
///
/// This utility provides generic URL validation for any URL type.
/// For Nostr relay-specific URL normalization (ws://, wss://), use URLNormalizer instead.
///
/// ## Transport security policy
///
/// NDKSwift **intentionally accepts both `http://` and `https://`** (and likewise
/// `ws://` and `wss://`) for external services — Blossom servers, Cashu mints,
/// LNURL endpoints, NIP-05 well-known fetches, NWC relays, etc. This keeps
/// development against local services painless and lets callers run against
/// non-TLS endpoints on internal networks.
///
/// The audit (`docs/audits/04-encryption-wallets-zaps.md` H4) flagged this as
/// "HTTPS not enforced anywhere." That is the documented behavior, not a bug:
/// app integrators who require TLS should enforce it themselves (e.g. App
/// Transport Security on iOS plus an explicit scheme check at the call site).
public enum URLUtils {
    /// Validates a URL string and returns a URL instance, throwing NDKError.invalidURL if invalid.
    ///
    /// Performs only syntactic validation via `URL(string:)`; **does not** filter
    /// by scheme. Callers requiring `https://` must check `url.scheme` themselves.
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A valid URL instance
    /// - Throws: NDKError.invalidURL if the URL string is invalid
    public static func validateURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString) else {
            throw NDKError.invalidURL(urlString)
        }
        return url
    }

    /// Safely creates a URL from a string, returning nil if invalid.
    ///
    /// Same permissive policy as ``validateURL(_:)``: accepts any syntactically
    /// valid URL regardless of scheme.
    /// - Parameter urlString: The URL string to convert
    /// - Returns: A URL instance or nil if invalid
    public static func safeURL(_ urlString: String) -> URL? {
        return URL(string: urlString)
    }
}
