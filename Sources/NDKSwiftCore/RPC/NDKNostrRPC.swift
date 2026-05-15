import Foundation

// MARK: - RPC Types

/// Represents a Nostr RPC request
/// Encapsulates the data needed to make RPC calls via Nostr events
public struct NDKRPCRequest {
    /// Unique identifier for this request
    let id: String
    /// Public key of the RPC service to send the request to
    let pubkey: String
    /// RPC method name to invoke
    let method: String
    /// Array of parameters for the RPC method
    let params: [String]
    /// The underlying Nostr event containing this request
    let event: NDKEvent
}

/// Represents a Nostr RPC response
/// Contains the result or error from an RPC call made via Nostr events
public struct NDKRPCResponse {
    /// Identifier matching the original request
    let id: String
    /// Result data if the RPC call succeeded
    let result: String
    /// Error message if the RPC call failed
    let error: String?
    /// The underlying Nostr event containing this response
    let event: NDKEvent
}

// MARK: - Nostr RPC Client

/// Nostr RPC client for making remote procedure calls via Nostr events
/// Implements NIP-46 for remote signing and other RPC operations
public actor NDKNostrRPC {
    private let ndk: NDK
    private let localSigner: NDKPrivateKeySigner
    private let relayURLs: [String]
    /// Default scheme used when we haven't yet learned a peer's preference.
    private let defaultEncryptionScheme: NDKEncryptionScheme = .nip44
    /// Per-peer encryption scheme learned from successful decrypts. Scoping
    /// this per-pubkey (rather than mutating a single shared field) prevents
    /// one peer's NIP-04 reply from downgrading subsequent encrypts to other
    /// peers — the actor-wide field used to do exactly that.
    private var peerEncryptionSchemes: [String: NDKEncryptionScheme] = [:]
    private var pendingRequests: [String: CheckedContinuation<NDKRPCResponse, Error>] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    private func encryptionScheme(for pubkey: String) -> NDKEncryptionScheme {
        return peerEncryptionSchemes[pubkey] ?? defaultEncryptionScheme
    }

    init(ndk: NDK, localSigner: NDKPrivateKeySigner, relayURLs: [String]) {
        self.ndk = ndk
        self.localSigner = localSigner
        self.relayURLs = relayURLs
    }

    deinit {
        // Cancel all pending timeout tasks
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()

        // Resolve any pending continuations with a cancellation error
        pendingRequests.values.forEach { $0.resume(throwing: NDKError.cancelled) }
        pendingRequests.removeAll()

        NDKLogger.log(.debug, category: .auth, "NDKNostrRPC deinitialized")
    }

    func parseEvent(_ event: NDKEvent) async throws -> Any {
        let pTags = event.tags.filter { $0.first == "p" }.map { $0.dropFirst().first ?? "?" }
        NDKLogger.log(.debug, category: .auth, "Parsing event \(event.id.prefix(8))... created_at: \(event.createdAt), p-tags: \(pTags)")

        let peerScheme = encryptionScheme(for: event.pubkey)
        var decryptedContent: String
        do {
            decryptedContent = try await localSigner.decrypt(senderPubkey: event.pubkey, value: event.content, scheme: peerScheme)
        } catch {
            // Try the other encryption scheme. Record the learned preference
            // per-peer so future encrypts to THIS pubkey use the right scheme,
            // without affecting other peers.
            let otherScheme: NDKEncryptionScheme = peerScheme == .nip44 ? .nip04 : .nip44
            decryptedContent = try await localSigner.decrypt(senderPubkey: event.pubkey, value: event.content, scheme: otherScheme)
            peerEncryptionSchemes[event.pubkey] = otherScheme
        }

        NDKLogger.log(.debug, category: .auth, "Event \(event.id.prefix(8))... decrypted: \(decryptedContent)")

        let json: [String: Any]
        do {
            json = try JSONCoding.parseDictionary(from: decryptedContent)
        } catch {
            NDKLogger.log(.error, category: .relay, "Failed to parse RPC content from event \(event.id): \(error.localizedDescription)")
            throw NDKError.invalidMessage(ErrorMessageConstants.failedTo("parse RPC content"))
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
            // Only resume immediately for SUCCESS responses
            // For error responses, log but don't resume yet - a success might follow
            if let continuation = pendingRequests[id] {
                if error == nil || !result.isEmpty {
                    // Success response - resume immediately
                    pendingRequests.removeValue(forKey: id)
                    timeoutTasks[id]?.cancel()
                    timeoutTasks.removeValue(forKey: id)
                    NDKLogger.log(.debug, category: .auth, "RPC success for \(id): \(result)")
                    continuation.resume(returning: response)
                } else {
                    // Error response - log but keep waiting for potential success
                    NDKLogger.log(.warning, category: .auth, "RPC received error for \(id): \(error ?? "unknown") - waiting for success response")
                }
            }

            return response
        }
    }

    private func sendRequestInternal(to pubkey: String, method: String, params: [String], id: String) async throws {
        NDKLogger.log(.debug, category: .auth, "Creating request - id: \(id), method: \(method), to: \(pubkey)")

        let request: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]

        let requestData = try JSONSerialization.data(withJSONObject: request)
        let requestString = String(data: requestData, encoding: .utf8) ?? ""
        NDKLogger.log(.debug, category: .auth, "Request JSON: \(requestString)")

        let outboundScheme = encryptionScheme(for: pubkey)
        let encryptedContent = try await localSigner.encrypt(recipientPubkey: pubkey, value: requestString, scheme: outboundScheme)
        NDKLogger.log(.debug, category: .auth, "Encrypted content using scheme: \(outboundScheme)")

        let localPubkey = try await localSigner.pubkey
        let event = try await NDKEventBuilder(ndk: ndk)
            .content(encryptedContent)
            .kind(EventKind.nostrConnect)
            .tags([[NostrConstants.TagName.pubkey, pubkey]])
            .build(signer: localSigner)
        NDKLogger.log(.debug, category: .auth, "Created event - id: \(event.id), from: \(localPubkey), to: \(pubkey)")

        // Prepare target relays
        let targetRelayUrls = relayURLs.setOrNil

        // Publish event
        let publishDescription = targetRelayUrls != nil ? "to specific relays: \(relayURLs)" : "to all connected relays"
        NDKLogger.log(.info, category: .auth, "Publishing \(publishDescription)")

        let publishedRelays = try await ndk.publish(event, to: targetRelayUrls)

        NDKLogger.log(.info, category: .auth, "Published to relays: \(publishedRelays.map { $0.url })")

        // If publishing to specific relays failed, try direct send as fallback
        if !relayURLs.isEmpty, publishedRelays.isEmpty {
            NDKLogger.log(.warning, category: .auth, "\(ErrorMessageConstants.failedTo("publish to any relay"))! Attempting direct send fallback...")
            await attemptDirectSend(event: event, to: relayURLs)
        }
    }

    /// Send an RPC request and deliver the response to `handler`.
    /// Routes through the throwing variant which registers the response
    /// waiter BEFORE publishing — necessary to avoid a race where a fast
    /// remote signer's response arrives before the waiter is registered.
    /// Zero in-tree callers today, but the API is part of the public surface.
    func sendRequest(to pubkey: String, method: String, params: [String], handler: @escaping (NDKRPCResponse) -> Void) async throws {
        let response = try await sendRequest(to: pubkey, method: method, params: params)
        handler(response)
    }

    func sendRequest(to pubkey: String, method: String, params: [String], timeout: TimeInterval? = nil) async throws -> NDKRPCResponse {
        let id = IDGenerator.randomId(length: 8)
        let timeoutSeconds = UInt64(timeout ?? NetworkConstants.timeoutRPCRequest)

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            Task { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NDKError.cancelled)
                    return
                }
                do {
                    // Send the request with the same ID we're waiting for
                    try await self.sendRequestInternal(to: pubkey, method: method, params: params, id: id)

                    // Set up timeout
                    await self.setupTimeout(for: id, continuation: continuation, timeoutSeconds: timeoutSeconds)
                } catch {
                    await self.cleanupRequest(id: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func waitForResponse(id: String) async throws -> NDKRPCResponse {
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            // Set up timeout
            setupTimeout(for: id, continuation: continuation)
        }
    }

    private func setupTimeout(for id: String, continuation: CheckedContinuation<NDKRPCResponse, Error>, timeoutSeconds: UInt64 = UInt64(NetworkConstants.timeoutRPCRequest)) {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutSeconds * TimeConstants.nanosecondsPerSecond)
            guard let self = self else { return }
            await self.handleTimeout(id: id, continuation: continuation)
        }
        timeoutTasks[id] = timeoutTask
    }

    private func handleTimeout(id: String, continuation: CheckedContinuation<NDKRPCResponse, Error>) async {
        timeoutTasks.removeValue(forKey: id)
        if pendingRequests.removeValue(forKey: id) != nil {
            continuation.resume(throwing: NDKError.timeout(operation: "RPC request", seconds: Int(NetworkConstants.timeoutRPCRequest)))
        }
    }

    private func cleanupRequest(id: String) async {
        pendingRequests.removeValue(forKey: id)
        timeoutTasks[id]?.cancel()
        timeoutTasks.removeValue(forKey: id)
    }

    private func attemptDirectSend(event: NDKEvent, to relayURLs: [String]) async {
        for url in relayURLs {
            if let relay = (await ndk.relays).first(where: { $0.url == url }) {
                NDKLogger.log(.debug, category: .auth, "Attempting direct send to \(url)")
                do {
                    let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
                    try await relay.send(eventMessage.serialize())
                    NDKLogger.log(.info, category: .auth, "Direct send successful to \(url)")
                } catch {
                    NDKLogger.log(.error, category: .auth, "Direct send failed to \(url): \(error)")
                }
            }
        }
    }
}
