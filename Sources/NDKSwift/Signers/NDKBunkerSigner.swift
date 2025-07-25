import Foundation
import Combine

/// Log prefix constant for bunker signer related logging
private let logPrefix = "[BunkerSigner]"

/// Parser for NIP-46 bunker:// URLs
/// Extracts connection parameters from bunker URLs for remote signing
struct BunkerURLParser {
    /// The bunker URL string to parse
    let urlString: String

    /// Parses the bunker URL and extracts connection parameters
    /// - Returns: A tuple containing:
    ///   - bunkerPubkey: The public key of the bunker service (optional)
    ///   - userPubkey: The user's public key (optional)
    ///   - relays: Array of relay URLs to connect through
    ///   - secret: Connection secret for authentication (optional)
    func parse() -> (bunkerPubkey: String?, userPubkey: String?, relays: [String], secret: String?) {
        guard let url = URL(string: urlString),
              url.scheme == BunkerConstants.urlScheme
        else {
            NDKLogger.log(.error, category: .auth, "\(logPrefix) \(ErrorMessageConstants.invalid("bunker URL format"))")
            return (nil, nil, [], nil)
        }

        // Extract bunker pubkey from hostname or path
        let bunkerPubkey = extractBunkerPubkey(from: url)

        // Parse query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return (bunkerPubkey, nil, [], nil)
        }

        let (userPubkey, relays, secret) = parseQueryParameters(from: components)
        return (bunkerPubkey, userPubkey, relays, secret)
    }

    private func extractBunkerPubkey(from url: URL) -> String? {
        // First check hostname
        if let host = url.host {
            return host
        }

        // Handle bunker://pubkey format
        let path = url.path
        guard path.hasPrefix("//") else { return nil }

        return String(path.dropFirst(2))
    }

    private func parseQueryParameters(from components: URLComponents) -> (userPubkey: String?, relays: [String], secret: String?) {
        var userPubkey: String?
        var relays: [String] = []
        var secret: String?

        let queryItems = components.queryItems ?? []

        for item in queryItems {
            switch item.name {
            case NostrConstants.JSONField.pubkey:
                userPubkey = item.value
            case NostrConstants.JSONField.relay:
                if let relay = item.value {
                    relays.append(relay)
                }
            case NostrConstants.JSONField.secret:
                secret = item.value
            default:
                break
            }
        }

        return (userPubkey, relays, secret)
    }
}

/// NIP-46 remote signer implementation supporting both bunker:// and nostrconnect:// flows
public actor NDKBunkerSigner: NDKSigner, Sendable {
    private let ndk: NDK
    private var userPubkey: String?
    private var bunkerPubkey: String?
    private var relayUrls: [String]
    private var secret: String?
    private let localSigner: NDKPrivateKeySigner
    private var subscriptionTask: Task<Void, Never>?
    private var subscriptionId: String?
    private var rpcClient: NDKNostrRPC?

    /// For nostrconnect:// flow
    private var nostrConnectSecret: String?
    public private(set) var nostrConnectUri: String?

    /// Authentication URL emitted when user needs to authorize
    public let authUrlPublisher = PassthroughSubject<String, Never>()

    /// Connection state
    private var isConnected = false
    private var connectionContinuation: CheckedContinuation<NDKUser, Error>?

    private enum ConnectionType {
        case bunker(String)
        case nostrConnect(relay: String, options: NostrConnectOptions?)
        case nip05(String)

        var rawValue: String {
            switch self {
            case .bunker:
                return BunkerConstants.urlScheme
            case .nostrConnect:
                return "nostrConnect"
            case .nip05:
                return "nip05"
            }
        }
    }

    private let connectionType: ConnectionType

    /// Options for nostrconnect:// URI generation
    public struct NostrConnectOptions {
        public let name: String?
        public let url: String?
        public let image: String?
        public let perms: String?

        public init(name: String? = nil, url: String? = nil, image: String? = nil, perms: String? = nil) {
            self.name = name
            self.url = url
            self.image = image
            self.perms = perms
        }
    }

    // MARK: - Static Factory Methods

    /// Create a bunker signer with bunker:// connection string
    public static func bunker(ndk: NDK, connectionToken: String, localSigner: NDKPrivateKeySigner? = nil) throws -> NDKBunkerSigner {
        let signer = try localSigner ?? NDKPrivateKeySigner.generate()
        return NDKBunkerSigner(ndk: ndk, connectionType: .bunker(connectionToken), localSigner: signer)
    }

    /// Create a bunker signer with NIP-05
    public static func nip05(ndk: NDK, nip05: String, localSigner: NDKPrivateKeySigner? = nil) throws -> NDKBunkerSigner {
        let signer = try localSigner ?? NDKPrivateKeySigner.generate()
        return NDKBunkerSigner(ndk: ndk, connectionType: .nip05(nip05), localSigner: signer)
    }

    /// Create a nostrconnect signer
    public static func nostrConnect(ndk: NDK, relay: String, localSigner: NDKPrivateKeySigner? = nil, options: NostrConnectOptions? = nil) throws -> NDKBunkerSigner {
        let signer = try localSigner ?? NDKPrivateKeySigner.generate()
        return NDKBunkerSigner(ndk: ndk, connectionType: .nostrConnect(relay: relay, options: options), localSigner: signer)
    }

    // MARK: - Initialization

    private init(ndk: NDK, connectionType: ConnectionType, localSigner: NDKPrivateKeySigner) {
        self.ndk = ndk
        self.connectionType = connectionType
        self.localSigner = localSigner
        self.relayUrls = []

        Task { @MainActor in
            switch connectionType {
            case let .bunker(token):
                await self.parseBunkerUrl(token)
            case let .nostrConnect(relay, options):
                await self.initNostrConnect(relay: relay, options: options)
            case .nip05:
                break // Will be handled in connect()
            }
        }
    }

    private func parseBunkerUrl(_ urlString: String) {
        let parser = BunkerURLParser(urlString: urlString)
        let (bunkerPubkey, userPubkey, relays, secret) = parser.parse()
        self.bunkerPubkey = bunkerPubkey
        self.userPubkey = userPubkey
        self.relayUrls = relays
        self.secret = secret
    }

    private func initNostrConnect(relay: String, options: NostrConnectOptions?) {
        self.relayUrls = [relay]
        self.nostrConnectSecret = generateNostrConnectSecret()

        // Generate nostrconnect:// URI - Note: pubkey will be set later
        Task { @MainActor in
            let pubkey = try? await localSigner.pubkey
            await self.generateNostrConnectUri(pubkey: pubkey ?? "", relay: relay, options: options)
        }
    }

    private func generateNostrConnectUri(pubkey: String, relay: String, options: NostrConnectOptions?) {
        var uri = "nostrconnect://\(pubkey)"
        var params: [String] = []

        if let name = options?.name {
            params.append("name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if let url = options?.url {
            params.append("url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if let image = options?.image {
            params.append("image=\(image.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if let perms = options?.perms {
            params.append("perms=\(perms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if let secret = nostrConnectSecret {
            params.append("secret=\(secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        params.append("relay=\(relay.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")

        if !params.isEmpty {
            uri += "?" + params.joined(separator: "&")
        }

        self.nostrConnectUri = uri
    }

    private func generateNostrConnectSecret() -> String {
        return IDGenerator.randomId(length: 16)
    }

    // MARK: - Connection

    /// Connect and authenticate with the bunker
    public func connect() async throws -> NDKUser {
        if isConnected, let pubkey = userPubkey {
            return NDKUser(pubkey: pubkey)
        }

        // Handle NIP-05 flow
        if case let .nip05(nip05) = connectionType {
            let user = try await NDKUser.fromNip05(nip05, ndk: ndk)
            self.userPubkey = user.pubkey
            let nip46Urls = await user.nip46Urls
            if let nip46Urls = nip46Urls {
                self.relayUrls = nip46Urls
            }
            if bunkerPubkey == nil {
                self.bunkerPubkey = user.pubkey
            }
        }

        // Ensure relays are added and connected
        if !relayUrls.isEmpty {
            NDKLogger.log(.info, category: .auth, "\(logPrefix) Connecting to bunker relays: \(relayUrls)")
            for relayUrl in relayUrls {
                let relay = await ndk.addRelay(relayUrl)

                // Connect to the relay if not already connected
                if await relay.connectionState != .connected {
                    do {
                        try await relay.connect()
                    } catch {
                        NDKLogger.log(.error, category: .auth, "\(logPrefix) Failed to connect to relay \(relayUrl): \(error)")
                    }
                }
            }
        } else {
            NDKLogger.log(.warning, category: .auth, "\(logPrefix) No relays specified for bunker connection")
        }

        // Initialize RPC client
        let rpcClient = NDKNostrRPC(ndk: ndk, localSigner: localSigner, relayUrls: relayUrls)
        self.rpcClient = rpcClient

        // Start listening for responses
        try await startListening()

        // Handle different connection flows
        switch connectionType {
        case .nostrConnect:
            return try await connectNostrConnect()
        default:
            return try await connectBunker()
        }
    }

    private func startListening() async throws {
        guard subscriptionTask == nil else {
            return
        }

        let localPubkey = try await localSigner.pubkey

        let filter = NDKFilter(
            kinds: [EventKind.nostrConnect], // NostrConnect kind
            tags: [NostrConstants.TagName.pubkey: [localPubkey]]
        )

        // Create subscription with specific relays if available
        // Create data source for bunker communication
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Always fresh for real-time bunker communication
            cachePolicy: .networkOnly, // Skip cache for bunker messages
            relays: relayUrls.setOrNil
        )

        // DataSource created

        // Start listening to events
        subscriptionTask = Task { [weak self] in
            for await event in dataSource.events {
                await self?.handleIncomingEvent(event)
            }
        }
    }

    private func connectNostrConnect() async throws -> NDKUser {
        return try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation

            Task {
                // Wait for connect response with our secret
                // The response handler will resume the continuation
            }
        }
    }

    private func connectBunker() async throws -> NDKUser {
        guard let bunkerPubkey = bunkerPubkey else {
            NDKLogger.log(.error, category: .auth, "\(logPrefix) ERROR: Bunker pubkey not set!")
            throw NDKError.configurationError("Bunker pubkey not set")
        }

        // According to NIP-46, connect params are: [<remote-signer-pubkey>, <optional_secret>, <optional_requested_permissions>]
        var params: [String] = [bunkerPubkey]
        if let secret = secret, !secret.isEmpty {
            params.append(secret)
        }

        // Send connect request and wait for response
        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: "connect",
            params: params
        )

        guard let response = response else {
            throw NDKError.connectionLost(relay: BunkerConstants.relayName, message: "No response received")
        }

        if response.result == "ack" {
            // Now get the public key
            let pubkey = try await getPublicKey()
            self.userPubkey = pubkey
            isConnected = true

            let user = NDKUser(pubkey: pubkey)
            NDKLogger.log(.info, category: .auth, "\(logPrefix) Successfully connected as \(pubkey)")
            return user
        } else {
            let error = NDKError.networkError(for: BunkerConstants.relayName, operation: "connect", error: NSError(domain: BunkerConstants.errorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: response.error ?? ErrorMessageConstants.Messages.connectionFailed]))
            throw error
        }
    }

    private func handleIncomingEvent(_ event: NDKEvent) async {
        do {
            guard let rpcClient = rpcClient else { return }
            let parsed = try await rpcClient.parseEvent(event)

            if parsed is NDKRPCRequest {
                // Handle incoming requests (not implemented in this basic version)
            } else if let response = parsed as? NDKRPCResponse {
                // Note: parseEvent already handles resuming continuations for matching IDs
                // We only need to handle special cases here
                await handleResponse(response)
            }
        } catch {
            NDKLogger.log(.error, category: .auth, "Error parsing event: \(error)")
        }
    }

    private func handleResponse(_ response: NDKRPCResponse) async {
        // Handle auth_url
        if response.result == "auth_url", let error = response.error {
            authUrlPublisher.send(error)
            return
        }

        // Handle nostrconnect flow
        if let secret = nostrConnectSecret, response.result == secret {
            let responsePubkey = response.event.pubkey
            userPubkey = responsePubkey
            bunkerPubkey = responsePubkey
            isConnected = true

            let user = NDKUser(pubkey: responsePubkey)
            connectionContinuation?.resume(returning: user)
            connectionContinuation = nil
            return
        }

        // Handle connect response
        if response.result == "ack" {
            await handleConnectResponse(response)
        }
    }

    private func handleConnectResponse(_ response: NDKRPCResponse) async {
        // This is now only used for special response handling in the nostrconnect flow
        // The bunker flow handles responses directly in connectBunker()

        // Handle auth_url
        if response.result == "auth_url", let error = response.error {
            authUrlPublisher.send(error)
            return
        }
    }

    // MARK: - NDKSigner Protocol

    public var pubkey: String {
        get async throws {
            if let pubkey = userPubkey {
                return pubkey
            }
            let user = try await connect()
            return user.pubkey
        }
    }

    private func performSign(_ event: NDKEvent) async throws -> Signature {
        guard let bunkerPubkey = bunkerPubkey else {
            throw NDKError.missingRequired("bunker connection")
        }

        let eventJson = try event.serialize()

        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: "sign_event",
            params: [eventJson]
        )

        guard let response = response,
              response.error == nil,
              let json = try? JSONCoding.parseDictionary(from: response.result),
              let sig = json["sig"] as? String
        else {
            throw NDKError.failedTo("sign event", message: response?.error)
        }

        return sig
    }

    public func sign(_ event: NDKEvent) async throws -> Signature {
        return try await performSign(event)
    }

    public func getPublicKey() async throws -> String {
        if let pubkey = userPubkey {
            return pubkey
        }

        guard let bunkerPubkey = bunkerPubkey else {
            throw NDKError.connectionLost(relay: BunkerConstants.relayName, message: ErrorMessageConstants.Messages.notConnected)
        }

        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: "get_public_key",
            params: []
        )

        guard let response = response,
              response.error == nil
        else {
            throw NDKError.cryptoOperation("get public key", nip: CryptoConstants.NIP.nip46, error: NSError(domain: BunkerConstants.errorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: response?.error ?? ErrorMessageConstants.failedTo("get public key")]))
        }

        return response.result
    }

    private func performCrypto(method: String, params: [String], errorMessage: String) async throws -> String {
        guard let bunkerPubkey = bunkerPubkey else {
            throw NDKError.connectionLost(relay: BunkerConstants.relayName, message: ErrorMessageConstants.Messages.notConnected)
        }

        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: method,
            params: params
        )

        guard let response = response,
              response.error == nil
        else {
            throw NDKError.cryptoOperation(method, nip: CryptoConstants.NIP.nip46, error: NSError(domain: BunkerConstants.errorDomain, code: -1, userInfo: [NSLocalizedDescriptionKey: response?.error ?? errorMessage]))
        }

        return response.result
    }

    public func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        let method = scheme == .nip04 ? "nip04_encrypt" : "nip44_encrypt"
        return try await performCrypto(method: method, params: [recipient.pubkey, value], errorMessage: ErrorMessageConstants.Messages.encryptionFailed)
    }

    public func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        let method = scheme == .nip04 ? "nip04_decrypt" : "nip44_decrypt"
        return try await performCrypto(method: method, params: [sender.pubkey, value], errorMessage: ErrorMessageConstants.Messages.decryptionFailed)
    }

    public func user() async throws -> NDKUser {
        if let pubkey = userPubkey {
            return NDKUser(pubkey: pubkey)
        }
        return try await connect()
    }

    // MARK: - Cleanup

    public func disconnect() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        rpcClient = nil
        isConnected = false
    }

    deinit {
        // Clean up synchronously
        subscriptionTask?.cancel()
        rpcClient = nil
        isConnected = false
    }

    // MARK: - Serialization (NDKSigner Protocol)

    public static var signerType: String {
        return BunkerConstants.urlScheme
    }

    public func serialize() async throws -> Data {
        let payload: [String: Any] = [
            "bunkerPubkey": bunkerPubkey ?? "",
            "userPubkey": userPubkey ?? "",
            "relayUrls": relayUrls,
            NostrConstants.JSONField.secret: secret ?? "",
            "localSignerData": try await localSigner.serialize(),
            "connectionType": connectionType.rawValue
        ]
        return try NDKSignerSerialization.createContainer(type: Self.signerType, payload: payload)
    }

    public static func deserialize(_ data: Data, ndk: NDK?) throws -> NDKBunkerSigner {
        // The registry already extracted the payload, so we decode it directly
        let payload = try JSONCoding.parseDictionary(from: data)

        guard let ndk = ndk else {
            throw NDKSignerRegistryError.deserializationError("NDK instance required for bunker signer")
        }

        guard let bunkerPubkey = payload["bunkerPubkey"] as? String,
              let userPubkey = payload["userPubkey"] as? String,
              let relayUrls = payload["relayUrls"] as? [String],
              let secret = payload[NostrConstants.JSONField.secret] as? String,
              let localSignerData = payload["localSignerData"] as? Data,
              let connectionTypeRaw = payload["connectionType"] as? String else {
            throw NDKSignerRegistryError.deserializationError(ErrorMessageConstants.missing("required bunker signer data"))
        }

        // Deserialize local signer (it also expects just the payload data)
        let localSigner = try NDKPrivateKeySigner.deserialize(localSignerData, ndk: ndk)

        // Create appropriate connection type
        let connectionType: ConnectionType
        switch connectionTypeRaw {
        case BunkerConstants.urlScheme:
            // Reconstruct bunker URL
            let bunkerUrl = "\(BunkerConstants.urlScheme)://\(bunkerPubkey)?pubkey=\(userPubkey)&secret=\(secret)" +
                           relayUrls.map { "&relay=\($0)" }.joined()
            connectionType = .bunker(bunkerUrl)
        case "nostrConnect":
            connectionType = .nostrConnect(relay: relayUrls.first ?? "", options: nil)
        case "nip05":
            connectionType = .nip05(userPubkey)
        default:
            throw NDKSignerRegistryError.deserializationError("Unknown connection type: \(connectionTypeRaw)")
        }

        return NDKBunkerSigner(ndk: ndk, connectionType: connectionType, localSigner: localSigner)
    }
}
