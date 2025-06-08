import Foundation

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
            throw NDKError.validation("invalid_event", "Failed to parse RPC content")
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

        // Prepare target relays
        let targetRelayUrls = relayUrls.isEmpty ? nil : Set(relayUrls)
        
        // Publish event
        let publishDescription = targetRelayUrls != nil ? "to specific relays: \(relayUrls)" : "to all connected relays"
        print("[RPC] Publishing \(publishDescription)")
        
        let publishedRelays = try await (targetRelayUrls != nil 
            ? ndk.publish(event: event, to: targetRelayUrls!)
            : ndk.publish(event))
        
        print("[RPC] Published to relays: \(publishedRelays.map { $0.url })")

        // If publishing to specific relays failed, try direct send as fallback
        if !relayUrls.isEmpty && publishedRelays.isEmpty {
            print("[RPC] WARNING: Failed to publish to any relay! Attempting direct send fallback...")
            await attemptDirectSend(event: event, to: relayUrls)
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

                    // Set up timeout
                    setupTimeout(for: id, continuation: continuation)
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
            
            // Set up timeout
            setupTimeout(for: id, continuation: continuation)
        }
    }

    private func setupTimeout(for id: String, continuation: CheckedContinuation<NDKRPCResponse, Error>, timeoutSeconds: UInt64 = 30) {
        Task {
            try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            await self.handleTimeout(id: id, continuation: continuation)
        }
    }

    private func handleTimeout(id: String, continuation: CheckedContinuation<NDKRPCResponse, Error>) async {
        if pendingRequests.removeValue(forKey: id) != nil {
            continuation.resume(throwing: NDKError.network("timeout", "Operation timed out"))
        }
    }
    
    private func attemptDirectSend(event: NDKEvent, to relayUrls: [String]) async {
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
}