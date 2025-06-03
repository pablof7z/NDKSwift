import Foundation
import Combine

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
        case .bunker(let token):
            parseBunkerUrl(token)
        case .nostrConnect(let relay, let options):
            initNostrConnect(relay: relay, options: options)
        case .nip05:
            break // Will be handled in connect()
        }
    }
    
    private func parseBunkerUrl(_ urlString: String) {
        guard let url = URL(string: urlString),
              url.scheme == "bunker" else { return }
        
        // Extract bunker pubkey from hostname or path
        if let host = url.host {
            self.bunkerPubkey = host
        } else {
            // Handle bunker://pubkey format
            let path = url.path
            if path.hasPrefix("//") {
                self.bunkerPubkey = String(path.dropFirst(2))
            }
        }
        
        // Parse query parameters
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                switch item.name {
                case "pubkey":
                    self.userPubkey = item.value
                case "relay":
                    if let relay = item.value {
                        self.relayUrls.append(relay)
                    }
                case "secret":
                    self.secret = item.value
                default:
                    break
                }
            }
        }
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
        if isConnected, let pubkey = userPubkey {
            return NDKUser(pubkey: pubkey)
        }
        
        // Handle NIP-05 flow
        if case .nip05(let nip05) = connectionType {
            let user = try await NDKUser.fromNip05(nip05, ndk: ndk)
            self.userPubkey = user.pubkey
            if let nip46Urls = user.nip46Urls {
                self.relayUrls = nip46Urls
            }
            if bunkerPubkey == nil {
                self.bunkerPubkey = user.pubkey
            }
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
        guard subscription == nil else { return }
        
        let localPubkey = try await localSigner.pubkey
        let filter = NDKFilter(
            kinds: [24133], // NostrConnect kind
            tags: ["p": [localPubkey]]
        )
        
        subscription = ndk.subscribe(filters: [filter])
        
        // Listen for events
        subscription?.onEvent { [weak self] event in
            Task {
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
            throw NDKError.signerError("Bunker pubkey not set")
        }
        
        let params = [userPubkey ?? "", secret ?? ""].filter { !$0.isEmpty }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation
            
            Task {
                do {
                    try await rpcClient?.sendRequest(
                        to: bunkerPubkey,
                        method: "connect",
                        params: params
                    ) { [weak self] response in
                        Task {
                            await self?.handleConnectResponse(response)
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func handleIncomingEvent(_ event: NDKEvent) async {
        do {
            guard let rpcClient = rpcClient else { return }
            let parsed = try await rpcClient.parseEvent(event)
            
            if let request = parsed as? NDKRPCRequest {
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
              let sig = json["sig"] as? String else {
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
              let sig = json["sig"] as? String else {
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
              response.error == nil else {
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
              response.error == nil else {
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
              response.error == nil else {
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
        subscription = nil  // This will automatically clean up
        rpcClient = nil
        isConnected = false
    }
    
    deinit {
        disconnect()
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NDKError.invalidEvent("Failed to parse RPC content")
        }
        
        let id = json["id"] as? String ?? ""
        
        if let method = json["method"] as? String,
           let params = json["params"] as? [String] {
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
        let request: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]
        
        let requestData = try JSONSerialization.data(withJSONObject: request)
        let requestString = String(data: requestData, encoding: .utf8) ?? ""
        
        let remoteUser = NDKUser(pubkey: pubkey)
        let encryptedContent = try await localSigner.encrypt(recipient: remoteUser, value: requestString, scheme: encryptionScheme)
        
        let localPubkey = try await localSigner.pubkey
        var event = NDKEvent(
            pubkey: localPubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 24133,
            tags: [["p", pubkey]],
            content: encryptedContent
        )
        
        try await localSigner.sign(event: &event)
        
        // Publish to specific relays if available
        if !relayUrls.isEmpty {
            try await ndk.publish(event: event, to: Set(relayUrls))
        } else {
            _ = try await ndk.publish(event)
        }
        
        // If handler provided, call it when response arrives
        if let handler = handler {
            Task {
                let response = try await waitForResponse(id: id)
                handler(response)
            }
        }
    }
    
    func sendRequest(to pubkey: String, method: String, params: [String]) async throws -> NDKRPCResponse {
        let id = UUID().uuidString.prefix(8).lowercased()
        
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            
            Task {
                do {
                    try await sendRequest(to: pubkey, method: method, params: params) { response in
                        // Response is handled in parseEvent
                    }
                    
                    // Set a timeout
                    Task {
                        try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                        if pendingRequests.removeValue(forKey: id) != nil {
                            continuation.resume(throwing: NDKError.timeout)
                        }
                    }
                } catch {
                    pendingRequests.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func waitForResponse(id: String) async throws -> NDKRPCResponse {
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            
            // Set a timeout
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                if pendingRequests.removeValue(forKey: id) != nil {
                    continuation.resume(throwing: NDKError.timeout)
                }
            }
        }
    }
}