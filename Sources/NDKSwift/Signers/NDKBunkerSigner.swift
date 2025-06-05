import Combine
import Foundation

/// NIP-46 remote signer implementation supporting both bunker:// and nostrconnect:// flows
public actor NDKBunkerSigner: NDKSigner, @unchecked Sendable {
    private let ndk: NDK
    private var userPubkey: String?
    private var bunkerPubkey: String?
    private var relayUrls: [String]
    private var secret: String?
    private let localSigner: NDKPrivateKeySigner
    private var subscription: NDKSubscription?
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
    public static func bunker(ndk: NDK, connectionToken: String, localSigner: NDKPrivateKeySigner? = nil) -> NDKBunkerSigner {
        let signer = localSigner ?? (try! NDKPrivateKeySigner.generate())
        return NDKBunkerSigner(ndk: ndk, connectionType: .bunker(connectionToken), localSigner: signer)
    }

    /// Create a bunker signer with NIP-05
    public static func nip05(ndk: NDK, nip05: String, localSigner: NDKPrivateKeySigner? = nil) -> NDKBunkerSigner {
        let signer = localSigner ?? (try! NDKPrivateKeySigner.generate())
        return NDKBunkerSigner(ndk: ndk, connectionType: .nip05(nip05), localSigner: signer)
    }

    /// Create a nostrconnect signer
    public static func nostrConnect(ndk: NDK, relay: String, localSigner: NDKPrivateKeySigner? = nil, options: NostrConnectOptions? = nil) -> NDKBunkerSigner {
        let signer = localSigner ?? (try! NDKPrivateKeySigner.generate())
        return NDKBunkerSigner(ndk: ndk, connectionType: .nostrConnect(relay: relay, options: options), localSigner: signer)
    }

    // MARK: - Initialization

    private init(ndk: NDK, connectionType: ConnectionType, localSigner: NDKPrivateKeySigner) {
        self.ndk = ndk
        self.connectionType = connectionType
        self.localSigner = localSigner
        self.relayUrls = []

        switch connectionType {
        case let .bunker(token):
            self.parseBunkerUrl(token)
        case let .nostrConnect(relay, options):
            self.initNostrConnect(relay: relay, options: options)
        case .nip05:
            break // Will be handled in connect()
        }
    }

    private func parseBunkerUrl(_ urlString: String) {
        print("[BunkerSigner] Parsing bunker URL: \(urlString)")

        guard let url = URL(string: urlString),
              url.scheme == "bunker"
        else {
            print("[BunkerSigner] ERROR: Invalid URL scheme or format")
            return
        }

        // Extract bunker pubkey from hostname or path
        if let host = url.host {
            self.bunkerPubkey = host
            print("[BunkerSigner] Extracted bunker pubkey from host: \(host)")
        } else {
            // Handle bunker://pubkey format
            let path = url.path
            if path.hasPrefix("//") {
                self.bunkerPubkey = String(path.dropFirst(2))
                print("[BunkerSigner] Extracted bunker pubkey from path: \(self.bunkerPubkey ?? "nil")")
            }
        }

        // Parse query parameters
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            print("[BunkerSigner] Query items: \(components.queryItems?.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", ") ?? "none")")

            for item in components.queryItems ?? [] {
                switch item.name {
                case "pubkey":
                    self.userPubkey = item.value
                    print("[BunkerSigner] Found user pubkey: \(item.value ?? "nil")")
                case "relay":
                    if let relay = item.value {
                        self.relayUrls.append(relay)
                        print("[BunkerSigner] Added relay: \(relay)")
                    }
                case "secret":
                    self.secret = item.value
                    print("[BunkerSigner] Found secret: \(item.value != nil ? "***" : "nil")")
                default:
                    print("[BunkerSigner] Unknown parameter: \(item.name)=\(item.value ?? "nil")")
                }
            }
        }

        print("[BunkerSigner] Parse complete - bunkerPubkey: \(bunkerPubkey ?? "nil"), userPubkey: \(userPubkey ?? "nil"), relays: \(relayUrls), hasSecret: \(secret != nil)")
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
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
    }

    // MARK: - Connection

    /// Connect and authenticate with the bunker
    public func connect() async throws -> NDKUser {
        print("[BunkerSigner] Starting connection process...")

        if isConnected, let pubkey = userPubkey {
            print("[BunkerSigner] Already connected with pubkey: \(pubkey)")
            return NDKUser(pubkey: pubkey)
        }

        // Handle NIP-05 flow
        if case let .nip05(nip05) = connectionType {
            print("[BunkerSigner] Using NIP-05 flow for: \(nip05)")
            let user = try await NDKUser.fromNip05(nip05, ndk: ndk)
            self.userPubkey = user.pubkey
            if let nip46Urls = user.nip46Urls {
                self.relayUrls = nip46Urls
                print("[BunkerSigner] Found NIP-46 relays from NIP-05: \(nip46Urls)")
            }
            if bunkerPubkey == nil {
                self.bunkerPubkey = user.pubkey
            }
        }

        print("[BunkerSigner] Using relays: \(relayUrls)")

        // Ensure relays are added and connected
        if !relayUrls.isEmpty {
            print("[BunkerSigner] Adding and connecting to bunker relays...")
            for relayUrl in relayUrls {
                let relay = ndk.addRelay(relayUrl)
                print("[BunkerSigner] Added relay: \(relayUrl), current state: \(relay.connectionState)")

                // Connect to the relay if not already connected
                if relay.connectionState != .connected {
                    print("[BunkerSigner] Connecting to relay: \(relayUrl)")
                    do {
                        try await relay.connect()
                        print("[BunkerSigner] Successfully connected to relay: \(relayUrl)")
                    } catch {
                        print("[BunkerSigner] Failed to connect to relay \(relayUrl): \(error)")
                    }
                }
            }

            // Wait a bit for connections to stabilize
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        } else {
            print("[BunkerSigner] WARNING: No relays specified for bunker connection!")
        }

        // Initialize RPC client
        print("[BunkerSigner] Initializing RPC client with relays: \(relayUrls)")
        let rpcClient = NDKNostrRPC(ndk: ndk, localSigner: localSigner, relayUrls: relayUrls)
        self.rpcClient = rpcClient

        // Start listening for responses
        print("[BunkerSigner] Starting to listen for responses...")
        try await startListening()

        // Handle different connection flows
        switch connectionType {
        case .nostrConnect:
            print("[BunkerSigner] Using nostrConnect flow")
            return try await connectNostrConnect()
        default:
            print("[BunkerSigner] Using bunker flow")
            return try await connectBunker()
        }
    }

    private func startListening() async throws {
        guard subscription == nil else {
            print("[BunkerSigner] Already listening for responses")
            return
        }

        let localPubkey = try await localSigner.pubkey
        print("[BunkerSigner] Setting up listener for local pubkey: \(localPubkey)")

        let filter = NDKFilter(
            kinds: [24133], // NostrConnect kind
            tags: ["p": [localPubkey]]
        )

        print("[BunkerSigner] Creating subscription with filter: kinds=[\(filter.kinds?.map { String($0) }.joined(separator: ",") ?? "")], p=\(localPubkey)")

        // Create subscription with specific relays if available
        if !relayUrls.isEmpty {
            var options = NDKSubscriptionOptions()
            let relayObjects = relayUrls.compactMap { url in
                ndk.relays.first { $0.url == url }
            }
            options.relays = Set(relayObjects)
            subscription = ndk.subscribe(filters: [filter], options: options)
            print("[BunkerSigner] Subscription created for specific relays: \(relayUrls)")
        } else {
            subscription = ndk.subscribe(filters: [filter])
            print("[BunkerSigner] Subscription created for all relays")
        }

        // Listen for events
        subscription?.onEvent { [weak self] event in
            Task { [weak self] in
                print("[BunkerSigner] Received event: kind=\(event.kind), from=\(event.pubkey)")
                await self?.handleIncomingEvent(event)
            }
        }

        subscription?.onEOSE {
            print("[BunkerSigner] EOSE received from relay")
        }

        subscription?.start()
        print("[BunkerSigner] Subscription started")
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
            print("[BunkerSigner] ERROR: Bunker pubkey not set!")
            throw NDKError.signerError("Bunker pubkey not set")
        }

        print("[BunkerSigner] Connecting to bunker with pubkey: \(bunkerPubkey)")

        let params = [userPubkey ?? "", secret ?? ""].filter { !$0.isEmpty }
        let maskedParams = params.enumerated().map { index, param in
            index == 1 && !param.isEmpty ? "***" : param
        }
        print("[BunkerSigner] Connect params: \(maskedParams)")

        return try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation

            Task {
                do {
                    print("[BunkerSigner] Sending connect request to bunker...")
                    try await rpcClient?.sendRequest(
                        to: bunkerPubkey,
                        method: "connect",
                        params: params
                    ) { [weak self] response in
                        Task { [weak self] in
                            print("[BunkerSigner] Received response from bunker: result=\(response.result), error=\(response.error ?? "nil")")
                            await self?.handleConnectResponse(response)
                        }
                    }
                } catch {
                    print("[BunkerSigner] ERROR: Failed to send connect request: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func handleIncomingEvent(_ event: NDKEvent) async {
        do {
            guard let rpcClient = rpcClient else { return }
            let parsed = try await rpcClient.parseEvent(event)

            if parsed is NDKRPCRequest {
                // Handle incoming requests (not implemented in this basic version)
            } else if let response = parsed as? NDKRPCResponse {
                await handleResponse(response)
            }
        } catch {
            print("Error parsing event: \(error)")
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
            userPubkey = response.event.pubkey
            bunkerPubkey = response.event.pubkey
            isConnected = true

            let user = NDKUser(pubkey: response.event.pubkey)
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
        if response.result == "ack" {
            do {
                let pubkey = try await getPublicKey()
                self.userPubkey = pubkey
                isConnected = true

                let user = NDKUser(pubkey: pubkey)
                connectionContinuation?.resume(returning: user)
            } catch {
                connectionContinuation?.resume(throwing: error)
            }
        } else {
            let error = NDKError.signerError(response.error ?? "Connection failed")
            connectionContinuation?.resume(throwing: error)
        }
        connectionContinuation = nil
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

    public func sign(_ event: NDKEvent) async throws -> Signature {
        guard let bunkerPubkey = bunkerPubkey else {
            throw NDKError.signerError("Not connected")
        }

        let eventJson = try event.serialize()

        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: "sign_event",
            params: [eventJson]
        )

        guard let response = response,
              response.error == nil,
              let resultData = response.result.data(using: String.Encoding.utf8),
              let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
              let sig = json["sig"] as? String
        else {
            throw NDKError.signerError("Failed to sign event")
        }

        return sig
    }

    public func sign(event: inout NDKEvent) async throws {
        guard let bunkerPubkey = bunkerPubkey else {
            throw NDKError.signerError("Not connected")
        }

        let eventJson = try event.serialize()

        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: "sign_event",
            params: [eventJson]
        )

        guard let response = response,
              response.error == nil,
              let resultData = response.result.data(using: String.Encoding.utf8),
              let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
              let sig = json["sig"] as? String
        else {
            throw NDKError.signerError("Failed to sign event")
        }

        event.sig = sig
    }

    public func getPublicKey() async throws -> String {
        if let pubkey = userPubkey {
            return pubkey
        }

        guard let bunkerPubkey = bunkerPubkey else {
            throw NDKError.signerError("Not connected")
        }

        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: "get_public_key",
            params: []
        )

        guard let response = response,
              response.error == nil
        else {
            throw NDKError.signerError("Failed to get public key")
        }

        return response.result
    }

    public func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        guard let bunkerPubkey = bunkerPubkey else {
            throw NDKError.signerError("Not connected")
        }

        let method = scheme == .nip04 ? "nip04_encrypt" : "nip44_encrypt"

        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: method,
            params: [recipient.pubkey, value]
        )

        guard let response = response,
              response.error == nil
        else {
            throw NDKError.signerError("Failed to encrypt")
        }

        return response.result
    }

    public func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        guard let bunkerPubkey = bunkerPubkey else {
            throw NDKError.signerError("Not connected")
        }

        let method = scheme == .nip04 ? "nip04_decrypt" : "nip44_decrypt"

        let response = try await rpcClient?.sendRequest(
            to: bunkerPubkey,
            method: method,
            params: [sender.pubkey, value]
        )

        guard let response = response,
              response.error == nil
        else {
            throw NDKError.signerError("Failed to decrypt")
        }

        return response.result
    }

    public func user() async throws -> NDKUser {
        if let pubkey = userPubkey {
            return NDKUser(pubkey: pubkey)
        }
        return try await connect()
    }

    // MARK: - Cleanup

    public func disconnect() {
        subscription = nil // This will automatically clean up
        rpcClient = nil
        isConnected = false
    }

    deinit {
        // Clean up synchronously
        subscription = nil
        rpcClient = nil
        isConnected = false
    }
}

// MARK: - RPC Types

public struct NDKRPCRequest {
    let id: String
    let pubkey: String
    let method: String
    let params: [String]
    let event: NDKEvent
}

public struct NDKRPCResponse {
    let id: String
    let result: String
    let error: String?
    let event: NDKEvent
}

// MARK: - Nostr RPC Client

public actor NDKNostrRPC {
    private let ndk: NDK
    private let localSigner: NDKPrivateKeySigner
    private let relayUrls: [String]
    private var encryptionScheme: NDKEncryptionScheme = .nip04
    private var pendingRequests: [String: CheckedContinuation<NDKRPCResponse, Error>] = [:]

    init(ndk: NDK, localSigner: NDKPrivateKeySigner, relayUrls: [String]) {
        self.ndk = ndk
        self.localSigner = localSigner
        self.relayUrls = relayUrls
    }

    func parseEvent(_ event: NDKEvent) async throws -> Any {
        let remoteUser = NDKUser(pubkey: event.pubkey)

        var decryptedContent: String
        do {
            decryptedContent = try await localSigner.decrypt(sender: remoteUser, value: event.content, scheme: encryptionScheme)
        } catch {
            // Try other encryption scheme
            let otherScheme: NDKEncryptionScheme = encryptionScheme == .nip04 ? .nip44 : .nip04
            decryptedContent = try await localSigner.decrypt(sender: remoteUser, value: event.content, scheme: otherScheme)
            encryptionScheme = otherScheme
        }

        guard let data = decryptedContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw NDKError.invalidEvent("Failed to parse RPC content")
        }

        let id = json["id"] as? String ?? ""

        if let method = json["method"] as? String,
           let params = json["params"] as? [String]
        {
            return NDKRPCRequest(
                id: id,
                pubkey: event.pubkey,
                method: method,
                params: params,
                event: event
            )
        } else {
            let result = json["result"] as? String ?? ""
            let error = json["error"] as? String

            let response = NDKRPCResponse(
                id: id,
                result: result,
                error: error,
                event: event
            )

            // Resume any waiting continuation
            if let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }

            return response
        }
    }

    func sendRequest(to pubkey: String, method: String, params: [String], handler: ((NDKRPCResponse) -> Void)? = nil) async throws {
        let id = UUID().uuidString.prefix(8).lowercased()
        print("[RPC] Creating request - id: \(id), method: \(method), to: \(pubkey)")

        let request: [String: Any] = [
            "id": id,
            "method": method,
            "params": params,
        ]

        let requestData = try JSONSerialization.data(withJSONObject: request)
        let requestString = String(data: requestData, encoding: .utf8) ?? ""
        print("[RPC] Request JSON: \(requestString)")

        let remoteUser = NDKUser(pubkey: pubkey)
        let encryptedContent = try await localSigner.encrypt(recipient: remoteUser, value: requestString, scheme: encryptionScheme)
        print("[RPC] Encrypted content using scheme: \(encryptionScheme)")

        let localPubkey = try await localSigner.pubkey
        var event = NDKEvent(
            pubkey: localPubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 24133,
            tags: [["p", pubkey]],
            content: encryptedContent
        )

        try await localSigner.sign(event: &event)
        print("[RPC] Created and signed event - id: \(event.id ?? "nil")")

        // Publish to specific relays if available
        if !relayUrls.isEmpty {
            print("[RPC] Publishing to specific relays: \(relayUrls)")
            let publishedRelays = try await ndk.publish(event: event, to: Set(relayUrls))
            print("[RPC] Published to relays: \(publishedRelays.map { $0.url })")

            if publishedRelays.isEmpty {
                print("[RPC] WARNING: Failed to publish to any relay!")
                // Try direct send as fallback
                for url in relayUrls {
                    if let relay = ndk.relays.first(where: { $0.url == url }) {
                        print("[RPC] Attempting direct send to \(url)")
                        do {
                            let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
                            try await relay.send(eventMessage.serialize())
                            print("[RPC] Direct send successful to \(url)")
                        } catch {
                            print("[RPC] Direct send failed to \(url): \(error)")
                        }
                    }
                }
            }
        } else {
            print("[RPC] Publishing to all connected relays")
            let publishedRelays = try await ndk.publish(event)
            print("[RPC] Published to relays: \(publishedRelays.map { $0.url })")
        }

        // If handler provided, call it when response arrives
        if let handler = handler {
            Task {
                print("[RPC] Waiting for response with id: \(id)")
                let response = try await waitForResponse(id: id)
                handler(response)
            }
        }
    }

    func sendRequest(to pubkey: String, method: String, params: [String]) async throws -> NDKRPCResponse {
        let id = UUID().uuidString.prefix(8).lowercased()

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            Task {
                do {
                    try await sendRequest(to: pubkey, method: method, params: params) { _ in
                        // Response is handled in parseEvent
                    }

                    // Set a timeout
                    Task {
                        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                        await self.handleTimeout(id: id, continuation: continuation)
                    }
                } catch {
                    self.pendingRequests.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func waitForResponse(id: String) async throws -> NDKRPCResponse {
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            // Set a timeout
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                await self.handleTimeout(id: id, continuation: continuation)
            }
        }
    }

    private func handleTimeout(id: String, continuation: CheckedContinuation<NDKRPCResponse, Error>) {
        if pendingRequests.removeValue(forKey: id) != nil {
            continuation.resume(throwing: NDKError.timeout)
        }
    }
}
