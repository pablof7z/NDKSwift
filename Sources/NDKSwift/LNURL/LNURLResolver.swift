import Foundation

/// Protocol for LNURL resolution
/// This allows easy replacement with a library implementation in the future
public protocol LNURLResolving {
    /// Resolve an LNURL or LUD16 address to get provider information
    func resolve(_ lnurlOrAddress: String) async throws -> LNURLResolutionResult
}

/// Protocol for URL data fetching (allows mocking in tests)
public protocol URLDataFetching {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

/// Extension to make URLSession conform to our protocol
extension URLSession: URLDataFetching {}

/// Default implementation of LNURL resolver
public class LNURLResolver: LNURLResolving {
    private let dataFetcher: URLDataFetching

    public init(dataFetcher: URLDataFetching = URLSession.shared) {
        self.dataFetcher = dataFetcher
    }

    /// Resolve an LNURL or LUD16 address
    public func resolve(_ lnurlOrAddress: String) async throws -> LNURLResolutionResult {
        let url = try getLNURLEndpoint(from: lnurlOrAddress)

        // Fetch the LNURL metadata
        let payResponse = try await fetchLNURLPayMetadata(from: url)

        // Parse metadata JSON
        let metadata = try parseMetadata(payResponse.metadata)

        // Extract provider pubkey (either from nostrPubkey field or metadata)
        let providerPubkey = extractProviderPubkey(from: payResponse, metadata: metadata)

        return LNURLResolutionResult(
            providerPubkey: providerPubkey,
            payResponse: payResponse,
            metadata: metadata
        )
    }

    // MARK: - Private Methods

    /// Convert LUD16 or LNURL to actual endpoint URL
    private func getLNURLEndpoint(from input: String) throws -> URL {
        // Check if it's a LUD16 (email-like format)
        if input.contains("@") {
            return try resolveLUD16(input)
        }

        // Check if it's already a URL
        if let url = URL(string: input), url.scheme != nil {
            return url
        }

        // Try to decode as bech32 LNURL
        if input.lowercased().hasPrefix(Bech32HRP.lnurl) {
            return try decodeLNURL(input)
        }

        throw LNURLError.invalidFormat("Input is neither LUD16 nor valid LNURL")
    }

    /// Resolve LUD16 (Lightning Address) to URL
    private func resolveLUD16(_ address: String) throws -> URL {
        let parts = address.split(separator: "@")
        guard parts.count == 2 else {
            throw LNURLError.invalidFormat("Invalid LUD16 format")
        }

        let username = String(parts[0])
        let domain = String(parts[1])

        // Construct the well-known URL
        let urlString = "https://\(domain)\(WellKnownPath.lnurlp)\(username)"

        guard let url = URL(string: urlString) else {
            throw LNURLError.invalidFormat(ErrorMessageConstants.failedTo("construct URL from LUD16"))
        }

        return url
    }

    /// Decode bech32-encoded LNURL
    private func decodeLNURL(_ lnurl: String) throws -> URL {
        // For now, we'll throw unsupported since bech32 decoding requires additional implementation
        // In a real implementation, this would decode the bech32 string to get the URL
        throw LNURLError.unsupportedProtocol
    }

    /// Fetch LNURL pay metadata from endpoint
    private func fetchLNURLPayMetadata(from url: URL) async throws -> LNURLPayResponse {
        do {
            let (data, response) = try await dataFetcher.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == HTTPStatusCode.ok else {
                throw LNURLError.invalidResponse("HTTP request failed")
            }

            return try JSONCoding.decode(LNURLPayResponse.self, from: data)

        } catch let error as LNURLError {
            throw error
        } catch {
            throw LNURLError.networkError(error)
        }
    }

    /// Parse metadata JSON string into structured entries
    private func parseMetadata(_ metadataString: String) throws -> [LNURLMetadataEntry] {
        guard let data = metadataString.data(using: .utf8) else {
            throw LNURLError.decodingError("Invalid metadata string")
        }

        do {
            // Metadata is a JSON array of arrays: [["type", "value"], ...]
            let rawMetadata = try JSONSerialization.jsonObject(with: data) as? [[Any]]

            return rawMetadata?.compactMap { entry in
                guard entry.count >= 2,
                      let type = entry[0] as? String,
                      let value = entry[1] as? String else {
                    return nil
                }
                return LNURLMetadataEntry(type: type, value: value)
            } ?? []

        } catch {
            throw LNURLError.decodingError(ErrorMessageConstants.failedTo("parse metadata JSON") + ": \(error)")
        }
    }

    /// Extract provider pubkey from response or metadata
    private func extractProviderPubkey(from response: LNURLPayResponse, metadata: [LNURLMetadataEntry]) -> String? {
        // First check if nostrPubkey field is present
        if let pubkey = response.nostrPubkey, !pubkey.isEmpty {
            return pubkey
        }

        // Otherwise look for it in metadata
        // Some services include it as ["text/nostr+pubkey", "pubkey_here"]
        for entry in metadata {
            if entry.type == "text/nostr+pubkey" || entry.type == "nostr+pubkey" {
                return entry.value
            }
        }

        return nil
    }
}

/// Convenience extension for NDK
public extension NDK {
    /// Default LNURL resolver instance
    /// Can be replaced with a custom implementation if needed
    var lnurlResolver: LNURLResolving {
        // In the future, this could be made configurable
        return LNURLResolver()
    }
}