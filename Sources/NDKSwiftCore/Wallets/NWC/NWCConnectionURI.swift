import Foundation

/// Represents a parsed Nostr Wallet Connect connection URI
public struct NWCConnectionURI {
    /// The wallet service's public key (hex encoded)
    public let walletPubkey: String

    /// The relay URLs where the wallet service is listening
    public let relayURLs: [String]

    /// The client secret key (hex encoded) for signing events
    public let secret: String

    /// Optional Lightning address for profile setup
    public let lud16: String?

    /// The original URI string
    public let uri: String

    /// Initialize from a nostr+walletconnect:// URI string
    public init(uri: String) throws {
        self.uri = uri

        // Parse the URL
        guard let url = URL(string: uri) else {
            throw NDKError.parseError(for: "NWC connection URI", details: "Invalid URI format: \(uri)")
        }

        // Validate scheme
        guard url.scheme == "nostr+walletconnect" else {
            throw NDKError.parseError(for: "URI scheme", details: "Expected 'nostr+walletconnect' but got '\(url.scheme ?? "nil")'")
        }

        // Extract wallet pubkey from host or path
        let pubkey: String
        if let host = url.host, !host.isEmpty {
            pubkey = host
        } else {
            // Remove leading slash if present
            let path = url.path
            pubkey = path.hasPrefix("/") ? String(path.dropFirst()) : path
        }

        // Validate pubkey format
        guard HexValidator.isValid32ByteHex(pubkey) else {
            throw NDKError.invalidDataFormat("wallet public key", details: ValidationConstants.expectedHex64Got(pubkey.count))
        }
        walletPubkey = pubkey.lowercased()

        // Parse query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            throw NDKError.missingRequired("query parameters", in: "NWC URI")
        }

        // Extract relay URLs
        let relays = queryItems.filter { $0.name == NostrConstants.JSONField.relay }.compactMap { $0.value }
        guard !relays.isEmpty else {
            throw NDKError.missingRequired(NostrConstants.JSONField.relay, in: "NWC URI")
        }

        // Validate relay URLs. NWC carries wallet credentials and encrypted
        // payment traffic, so non-local relays must use secure WebSockets.
        try Self.validateRelayURLs(relays)
        relayURLs = relays

        // Extract secret
        guard let secret = queryItems.first(where: { $0.name == NostrConstants.JSONField.secret })?.value else {
            throw NDKError.missingRequired(NostrConstants.JSONField.secret, in: "NWC URI")
        }

        // Validate secret format
        guard HexValidator.isValid32ByteHex(secret) else {
            throw NDKError.invalidDataFormat("client secret", details: ValidationConstants.expectedHex64Got(secret.count))
        }
        self.secret = secret.lowercased()

        // Extract optional lud16
        lud16 = queryItems.first(where: { $0.name == "lud16" })?.value
    }

    /// Initialize with individual components
    public init(walletPubkey: String, relayURLs: [String], secret: String, lud16: String? = nil) throws {
        // Validate inputs
        guard HexValidator.isValid32ByteHex(walletPubkey) else {
            throw NDKError.invalidDataFormat("wallet public key", details: ValidationConstants.publicKeyRequirement)
        }

        guard HexValidator.isValid32ByteHex(secret) else {
            throw NDKError.invalidDataFormat("client secret", details: ValidationConstants.publicKeyRequirement)
        }

        guard !relayURLs.isEmpty else {
            throw NDKError.missingRequired("relayURLs")
        }

        try Self.validateRelayURLs(relayURLs)

        self.walletPubkey = walletPubkey.lowercased()
        self.relayURLs = relayURLs
        self.secret = secret.lowercased()
        self.lud16 = lud16

        // Construct the URI
        var components = URLComponents()
        components.scheme = "nostr+walletconnect"
        components.host = self.walletPubkey

        var queryItems = [URLQueryItem]()
        for relay in relayURLs {
            queryItems.append(URLQueryItem(name: NostrConstants.JSONField.relay, value: relay))
        }
        queryItems.append(URLQueryItem(name: NostrConstants.JSONField.secret, value: self.secret))
        if let lud16 = lud16 {
            queryItems.append(URLQueryItem(name: "lud16", value: lud16))
        }
        components.queryItems = queryItems

        guard let uri = components.string else {
            throw NDKError.failedTo("construct URI from components")
        }
        self.uri = uri
    }

    /// Get the client's public key derived from the secret
    public func clientPubkey() throws -> String {
        return try Crypto.getPublicKey(from: secret)
    }

    /// Create a signer for this NWC connection
    public func createSigner() throws -> NDKPrivateKeySigner {
        return try NDKPrivateKeySigner(privateKey: secret)
    }

    /// Normalize relay URLs according to NDKSwift conventions
    public func normalizedRelayURLs() -> Set<String> {
        return Set(relayURLs.compactMap { urlString in
            URLNormalizer.tryNormalizeRelayUrl(urlString) ?? urlString
        })
    }

    private static func validateRelayURLs(_ relayURLs: [String]) throws {
        for relay in relayURLs {
            guard let components = URLComponents(string: relay),
                  let scheme = components.scheme?.lowercased(),
                  let host = components.host,
                  !host.isEmpty
            else {
                throw NDKError.invalidDataFormat("relay URL", details: "Invalid URL: \(relay)")
            }

            switch scheme {
            case "wss":
                continue
            case "ws" where isLocalhost(host):
                continue
            case "ws":
                throw NDKError.invalidDataFormat(
                    "relay URL",
                    details: "NWC relay URL must use wss:// unless it is localhost: \(relay)"
                )
            default:
                throw NDKError.invalidDataFormat("relay URL", details: "NWC relay URL must use wss://: \(relay)")
            }
        }
    }

    private static func isLocalhost(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        return lowercased == "localhost" || lowercased == "127.0.0.1" || lowercased == "::1"
    }
}

// MARK: - Convenience Extensions

extension NWCConnectionURI: CustomStringConvertible {
    /// Redacted description suitable for logs / error messages / debug printing.
    /// The raw `uri` contains `?secret=<hex>` which is the wallet client's
    /// private key; emitting it via `description` (and therefore via every
    /// `print(uri)`, string interpolation, or default error log) leaks the key.
    /// Callers that need the full URI for serialization must use ``fullURI``
    /// explicitly.
    public var description: String {
        let walletPrefix = walletPubkey.prefix(8)
        let relayCount = relayURLs.count
        return "NWCConnectionURI(wallet: \(walletPrefix)…, relays: \(relayCount), secret: <redacted>)"
    }

    /// The full `nostr+walletconnect://…` URI including the secret. Use this
    /// only when you actually need to round-trip the URI (e.g. persisting it
    /// to the keychain) — never in logs.
    public var fullURI: String {
        return uri
    }
}

extension NWCConnectionURI: Codable {
    enum CodingKeys: String, CodingKey {
        case uri
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let uri = try container.decode(String.self)
        try self.init(uri: uri)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uri)
    }
}
