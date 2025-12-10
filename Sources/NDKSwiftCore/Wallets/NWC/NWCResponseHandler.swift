import Foundation

/// Handler for processing NWC response events (kind 23195)
public struct NWCResponseHandler {
    private let ndk: NDK
    private let signer: NDKSigner
    private let relayURLs: [String]

    public init(ndk: NDK, signer: NDKSigner, relayURLs: [String]) {
        self.ndk = ndk
        self.signer = signer
        self.relayURLs = relayURLs
    }

    /// Execute a request and wait for response with proper sequencing
    public func executeRequestAndWaitForResponse<T: Decodable>(
        event: NDKEvent,
        responseType: T.Type,
        timeout: TimeInterval = NetworkConstants.timeoutStandardRequest
    ) async throws -> T {
        let requestId = event.id

        NDKLogger.log(.debug, category: .wallet, "[NWC Response] Setting up response listener for request \(requestId)")

        // 1. First, create filter for response events
        var filter = NDKFilter()
        filter.kinds = [.nostrWalletConnectRes]
        filter.addTagFilter("e", values: [requestId])
        NDKLogger.log(.trace, category: .wallet, "[NWC Response] Filter: kinds=\(filter.kinds ?? []), e-tag=\(requestId)")

        // Get the connected relays
        let allRelays = await ndk.relays
        let connectedRelays = allRelays.filter { relay in
            relayURLs.contains { url in
                relay.normalizedURL == URLNormalizer.tryNormalizeRelayUrl(url) ||
                relay.url == url
            }
        }
        NDKLogger.log(.debug, category: .wallet, "[NWC Response] Using \(connectedRelays.count) connected relays")

        // 2. Create subscription for the response BEFORE publishing
        let relayUrls = Set(connectedRelays.map { $0.url })

        // Use NDKSubscription for NWC response monitoring
        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Always fresh for real-time response monitoring
            cachePolicy: .networkOnly, // Skip cache for NWC responses
            relays: relayUrls
        )

        // Collect response in a task
        let responseTask = Task { () -> T in
            NDKLogger.log(.trace, category: .wallet, "[NWC Response] Waiting for response event...")

            for await responseEvent in dataSource.events {
                NDKLogger.log(.debug, category: .wallet, "[NWC Response] Got response event:")
                NDKLogger.log(.trace, category: .wallet, "[NWC Response]   ID: \(responseEvent.id)")
                NDKLogger.log(.trace, category: .wallet, "[NWC Response]   Pubkey: \(responseEvent.pubkey)")
                NDKLogger.log(.trace, category: .wallet, "[NWC Response]   Tags: \(responseEvent.tags)")

                // Decrypt the content
                let senderPubkey = responseEvent.pubkey
                let sender = NDKUser(pubkey: senderPubkey)
                NDKLogger.log(.trace, category: .wallet, "[NWC Response] Decrypting content from \(sender.pubkey)")
                let eventContent = responseEvent.content
                let decryptedContent = try await signer.decrypt(
                    sender: sender,
                    value: eventContent,
                    scheme: .nip04
                )
                NDKLogger.log(.trace, category: .wallet, "[NWC Response] Decrypted content: \(decryptedContent)")

                // Parse and return the response
                let result = try parseResponse(decryptedContent, expectedType: responseType)

                // AsyncStream will clean up automatically
                return result
            }

            // If we get here, subscription ended without response
            throw NDKError.timeout(operation: "NWC response", seconds: Int(timeout))
        }

        // 3. AsyncStream starts immediately, no need to wait for EOSE

        // 4. Now publish the request
        NDKLogger.log(.debug, category: .wallet, "[NWC Response] Publishing request event \(requestId)")
        let publishedRelays = try await ndk.publish(event)
        NDKLogger.log(.debug, category: .wallet, "[NWC Response] Published to \(publishedRelays.count) relays")

        // 5. Set up timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
            // AsyncStream will clean up automatically when task is cancelled
            throw NDKError.timeout(operation: "NWC response", seconds: Int(timeout))
        }

        // 6. Race between response and timeout
        let result: T = try await withThrowingTaskGroup(of: Result<T, Error>.self) { group in
            group.addTask {
                do {
                    return .success(try await responseTask.value)
                } catch {
                    return .failure(error)
                }
            }

            group.addTask {
                do {
                    try await timeoutTask.value
                    return .failure(NDKError.timeout(operation: "NWC response", seconds: Int(timeout)))
                } catch {
                    return .failure(error)
                }
            }

            // Wait for first result
            guard let firstResult = try await group.next() else {
                throw NDKError.timeout(operation: "NWC response", seconds: Int(timeout))
            }

            // Cancel the other task
            group.cancelAll()

            switch firstResult {
            case .success(let value):
                return value
            case .failure(let error):
                throw error
            }
        }

        return result
    }


    /// Wait for multiple responses
    public func waitForMultipleResponses<T: Decodable>(
        requestId: String,
        responseType: T.Type,
        expectedCount: Int,
        timeout: TimeInterval = NetworkConstants.timeoutStandardRequest
    ) async throws -> [String: Result<T, NDKError>] {
        // Create filter for responses with this request ID
        var filter = NDKFilter()
        filter.kinds = [.nostrWalletConnectRes]
        filter.addTagFilter("e", values: [requestId])

        // Get connected relays that match our wallet relays
        let allConnected = await ndk.pool.connectedRelays()
        let connectedRelays = allConnected.filter { relay in
            relayURLs.contains(relay.url)
        }

        guard !connectedRelays.isEmpty else {
            throw NDKError.notConfigured("No relays connected for NWC wallet")
        }

        // Create subscription
        let relayUrls = Set(connectedRelays.map { $0.url })

        // Use NDKSubscription for batch NWC response monitoring
        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Always fresh for real-time response monitoring
            cachePolicy: .networkOnly, // Skip cache for NWC responses
            relays: relayUrls
        )

        var responses: [String: Result<T, NDKError>] = [:]

        let responseTask = Task<[String: Result<T, NDKError>], Error> {
            for await event in dataSource.events {
                // Get the d-tag for this response
                let eventTags = event.tags
                guard let dTag = eventTags.first(where: { $0.count >= 2 && $0[0] == "d" }),
                      dTag.count > 1 else {
                    continue
                }

                let dTagValue = dTag[1]

                // Decrypt and parse the response
                do {
                    // Get wallet service pubkey from p-tag
                    let eventTags = event.tags
                    guard let pTag = eventTags.first(where: { $0.count >= 2 && $0[0] == "p" }) else {
                        continue
                    }
                    let walletPubkey = pTag[1]
                    let walletUser = NDKUser(pubkey: walletPubkey)

                    let eventContent = event.content
                    let decrypted = try await signer.decrypt(
                        sender: walletUser,
                        value: eventContent,
                        scheme: .nip04
                    )

                    let parsed = try parseResponse(decrypted, expectedType: responseType)
                    responses[dTagValue] = .success(parsed)
                } catch {
                    responses[dTagValue] = .failure(error as? NDKError ?? NDKError.invalidResponse(from: "Parse error: \(error)"))
                }

                // Check if we have enough responses
                if responses.count >= expectedCount {
                    return responses
                }
            }

            // If we exit the loop without enough responses
            throw NDKError.timeout(operation: "NWC multi-response", seconds: Int(timeout))
        }

        let timeoutTask = Task<[String: Result<T, NDKError>], Error> {
            try await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
            throw NDKError.timeout(operation: "NWC multi-response", seconds: Int(timeout))
        }

        let result = try await withThrowingTaskGroup(of: [String: Result<T, NDKError>].self) { group in
            group.addTask { try await responseTask.value }
            group.addTask { try await timeoutTask.value }

            guard let firstResult = try await group.next() else {
                throw NDKError.timeout(operation: "NWC multi-response", seconds: Int(timeout))
            }

            group.cancelAll()
            return firstResult
        }

        return result
    }

    /// Subscribe to payment notifications
    public func subscribeToNotifications() -> AsyncStream<NWCNotification<PaymentNotification>> {
        AsyncStream { continuation in
            Task {
                // Create filter for notification events (no e-tag)
                let filter = NDKFilter(kinds: [.nostrWalletConnectRes])

                // Get connected relays that match our wallet relays
                var connectedRelays: [NDKRelay] = []
                for relay in await ndk.relays {
                    let state = await relay.connectionState
                    if state == .connected && relayURLs.contains(relay.url) {
                        connectedRelays.append(relay)
                    }
                }

                guard !connectedRelays.isEmpty else {
                    continuation.finish()
                    return
                }

                // Create subscription
                let relayUrls = Set(connectedRelays.map { $0.url })

                // Use NDKSubscription for NWC notification monitoring
                let dataSource = NDKSubscription(
                    ndk: ndk,
                    filter: filter,
                    maxAge: 0, // Always fresh for real-time notification monitoring
                    cachePolicy: .networkOnly, // Skip cache for NWC notifications
                    relays: relayUrls
                )

                let task = Task {
                for await event in dataSource.events {
                    // Check if this is an NWC notification (no e-tag)
                    let eventTags = event.tags
                    guard !eventTags.contains(where: { $0.count >= 1 && $0[0] == "e" }) else {
                        continue
                    }

                    // Get wallet service pubkey from p-tag
                    guard let pTag = eventTags.first(where: { $0.count >= 2 && $0[0] == "p" }) else {
                        continue
                    }
                    let walletPubkey = pTag[1]
                    let walletUser = NDKUser(pubkey: walletPubkey)

                    // Decrypt the notification
                    do {
                        let eventContent = event.content
                        let decrypted = try await signer.decrypt(
                            sender: walletUser,
                            value: eventContent,
                            scheme: .nip04
                        )

                        // Parse as notification
                        let json: [String: Any]
                        do {
                            json = try JSONCoding.parseDictionary(from: decrypted)
                        } catch {
                            NDKLogger.log(.warning, category: .wallet, "Failed to parse NWC notification JSON from event \(event.id): \(error.localizedDescription)")
                            continue
                        }

                        guard let notificationType = json["notification_type"] as? String,
                              let notificationData = json["notification"] as? [String: Any] else {
                            NDKLogger.log(.warning, category: .wallet, "NWC notification missing required fields")
                            continue
                        }

                        // Convert notification data back to JSON for parsing
                        let paymentNotification = try JSONCoding.decodeFromDictionary(PaymentNotification.self, from: notificationData)

                        let notification = NWCNotification(
                            notificationType: notificationType,
                            notification: paymentNotification
                        )

                        continuation.yield(notification)
                    } catch {
                        // Silently ignore parse errors for notifications
                        continue
                    }
                }

                continuation.finish()
            }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func parseResponse<T: Decodable>(_ content: String, expectedType: T.Type) throws -> T {
        guard let data = content.data(using: .utf8) else {
            throw NDKError.invalidResponse(from: "Invalid response content")
        }

        let response = try JSONCoding.decode(NWCResponse<T>.self, from: data)

        if let error = response.error {
            throw NDKError.walletError(message: error.message)
        }

        guard let result = response.result else {
            throw NDKError.invalidResponse(from: "No result in response")
        }

        return result
    }
}