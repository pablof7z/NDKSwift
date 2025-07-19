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
            // Try other encryption scheme
            let otherScheme: NDKEncryptionScheme = encryptionScheme == .nip04 ? .nip44 : .nip04
            decryptedContent = try await localSigner.decrypt(sender: remoteUser, value: event.content, scheme: otherScheme)
            encryptionScheme = otherScheme
        }

        guard let data = decryptedContent.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw NDKError.invalidMessage("Failed to parse RPC content")
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

    func sendRequest(to pubkey: String, method: String, params: [String], handler: ((NDKRPCResponse) -> Void)? = nil) async throws {
        let id = IDGenerator.randomId(length: 8)
        NDKLogger.shared.log(.debug, category: .auth, "Creating request - id: \(id), method: \(method), to: \(pubkey)")

        let request: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]

        let requestData = try JSONSerialization.data(withJSONObject: request)
        let requestString = String(data: requestData, encoding: .utf8) ?? ""
        NDKLogger.shared.log(.debug, category: .auth, "Request JSON: \(requestString)")

        let remoteUser = NDKUser(pubkey: pubkey)
        let encryptedContent = try await localSigner.encrypt(recipient: remoteUser, value: requestString, scheme: encryptionScheme)
        NDKLogger.shared.log(.debug, category: .auth, "Encrypted content using scheme: \(encryptionScheme)")

        let event = try await ndk.event()
            .content(encryptedContent)
            .kind(24133)
            .tags([["p", pubkey]])
            .build(signer: localSigner)
        NDKLogger.shared.log(.debug, category: .auth, "Created and signed event - id: \(event.id)")

        // Prepare target relays
        let targetRelayUrls = relayUrls.isEmpty ? nil : Set(relayUrls)
        
        // Publish event
        let publishDescription = targetRelayUrls != nil ? "to specific relays: \(relayUrls)" : "to all connected relays"
        NDKLogger.shared.log(.info, category: .auth, "Publishing \(publishDescription)")
        
        let publishedRelays = try await (targetRelayUrls != nil 
            ? ndk.publish(event: event, to: targetRelayUrls!)
            : ndk.publish(event))
        
        NDKLogger.shared.log(.info, category: .auth, "Published to relays: \(publishedRelays.map { $0.url })")

        // If publishing to specific relays failed, try direct send as fallback
        if !relayUrls.isEmpty && publishedRelays.isEmpty {
            NDKLogger.shared.log(.warning, category: .auth, "Failed to publish to any relay! Attempting direct send fallback...")
            await attemptDirectSend(event: event, to: relayUrls)
        }

        // If handler provided, call it when response arrives
        if let handler = handler {
            Task {
                NDKLogger.shared.log(.debug, category: .auth, "Waiting for response with id: \(id)")
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
                    try await sendRequest(to: pubkey, method: method, params: params) { _ in
                        // Response is handled in parseEvent
                    }

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

    private func setupTimeout(for id: String, continuation: CheckedContinuation<NDKRPCResponse, Error>, timeoutSeconds: UInt64 = 30) {
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: timeoutSeconds * TimeConstants.nanosecondsPerSecond)
            await self.handleTimeout(id: id, continuation: continuation)
        }
        timeoutTasks[id] = timeoutTask
    }

    private func handleTimeout(id: String, continuation: CheckedContinuation<NDKRPCResponse, Error>) async {
        timeoutTasks.removeValue(forKey: id)
        if pendingRequests.removeValue(forKey: id) != nil {
            continuation.resume(throwing: NDKError.timeout(operation: "RPC request", seconds: 30))
        }
    }
    
    private func attemptDirectSend(event: NDKEvent, to relayUrls: [String]) async {
        for url in relayUrls {
            if let relay = (await ndk.relays).first(where: { $0.url == url }) {
                NDKLogger.shared.log(.debug, category: .auth, "Attempting direct send to \(url)")
                do {
                    let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
                    try await relay.send(eventMessage.serialize())
                    NDKLogger.shared.log(.info, category: .auth, "Direct send successful to \(url)")
                } catch {
                    NDKLogger.shared.log(.error, category: .auth, "Direct send failed to \(url): \(error)")
                }
            }
        }
    }
}
