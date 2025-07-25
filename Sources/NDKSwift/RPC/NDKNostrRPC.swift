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
    private let relayUrls: [String]
    private var encryptionScheme: NDKEncryptionScheme = .nip44
    private var pendingRequests: [String: CheckedContinuation<NDKRPCResponse, Error>] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]

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
            // Try other encryption scheme (fallback to NIP04 if NIP44 fails)
            let otherScheme: NDKEncryptionScheme = encryptionScheme == .nip44 ? .nip04 : .nip44
            decryptedContent = try await localSigner.decrypt(sender: remoteUser, value: event.content, scheme: otherScheme)
            encryptionScheme = otherScheme
        }

        guard let data = decryptedContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
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
            if let continuation = pendingRequests.removeValue(forKey: id) {
                // Cancel associated timeout task
                timeoutTasks[id]?.cancel()
                timeoutTasks.removeValue(forKey: id)
                continuation.resume(returning: response)
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

        let remoteUser = NDKUser(pubkey: pubkey)
        let encryptedContent = try await localSigner.encrypt(recipient: remoteUser, value: requestString, scheme: encryptionScheme)
        NDKLogger.log(.debug, category: .auth, "Encrypted content using scheme: \(encryptionScheme)")

        let event = try await NDKEventBuilder(ndk: ndk)
            .content(encryptedContent)
            .kind(24133)
            .tags([["p", pubkey]])
            .build(signer: localSigner)
        NDKLogger.log(.debug, category: .auth, "Created and signed event - id: \(event.id)")

        // Prepare target relays
        let targetRelayUrls = relayUrls.isEmpty ? nil : Set(relayUrls)

        // Publish event
        let publishDescription = targetRelayUrls != nil ? "to specific relays: \(relayUrls)" : "to all connected relays"
        NDKLogger.log(.info, category: .auth, "Publishing \(publishDescription)")

        let publishedRelays = try await ndk.publish(event, to: targetRelayUrls)

        NDKLogger.log(.info, category: .auth, "Published to relays: \(publishedRelays.map { $0.url })")

        // If publishing to specific relays failed, try direct send as fallback
        if !relayUrls.isEmpty && publishedRelays.isEmpty {
            NDKLogger.log(.warning, category: .auth, "Failed to publish to any relay! Attempting direct send fallback...")
            await attemptDirectSend(event: event, to: relayUrls)
        }
    }

    func sendRequest(to pubkey: String, method: String, params: [String], handler: ((NDKRPCResponse) -> Void)? = nil) async throws {
        let id = IDGenerator.randomId(length: 8)

        try await sendRequestInternal(to: pubkey, method: method, params: params, id: id)

        // If handler provided, call it when response arrives
        if let handler = handler {
            Task {
                NDKLogger.log(.debug, category: .auth, "Waiting for response with id: \(id)")
                let response = try await waitForResponse(id: id)
                handler(response)
            }
        }
    }

    func sendRequest(to pubkey: String, method: String, params: [String]) async throws -> NDKRPCResponse {
        let id = IDGenerator.randomId(length: 8)

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            Task {
                do {
                    // Send the request with the same ID we're waiting for
                    try await sendRequestInternal(to: pubkey, method: method, params: params, id: id)

                    // Set up timeout
                    setupTimeout(for: id, continuation: continuation)
                } catch {
                    self.pendingRequests.removeValue(forKey: id)
                    self.timeoutTasks[id]?.cancel()
                    self.timeoutTasks.removeValue(forKey: id)
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
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: timeoutSeconds * TimeConstants.nanosecondsPerSecond)
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

    private func attemptDirectSend(event: NDKEvent, to relayUrls: [String]) async {
        for url in relayUrls {
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
