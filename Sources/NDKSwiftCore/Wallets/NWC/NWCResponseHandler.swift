import Foundation

/// Handler for processing NWC response events (kind 23195)
public struct NWCResponseHandler {
    private let ndk: NDK
    private let signer: NDKSigner
    private let relayURLs: [String]
    /// The wallet service's pubkey, taken from the trusted NWCConnectionURI.
    /// Used to validate response/notification events instead of trusting an
    /// arbitrary `p` tag on the wire (which any client can forge).
    private let walletPubkey: String

    public init(ndk: NDK, signer: NDKSigner, relayURLs: [String], walletPubkey: String) {
        self.ndk = ndk
        self.signer = signer
        self.relayURLs = relayURLs
        self.walletPubkey = walletPubkey
    }

    /// Execute a request and wait for response with proper sequencing
    public func executeRequestAndWaitForResponse<T: Decodable>(
        event: NDKEvent,
        responseType: T.Type,
        timeout: TimeInterval = NetworkConstants.timeoutStandardRequest
    ) async throws -> T {
        let requestId = event.id

        NDKLogger.log(.debug, category: .wallet, "[NWC Response] Setting up response listener for request \(requestId)")

        // 1. First, create filter for response events. Restrict authors to the
        // trusted wallet pubkey so attackers can't publish 23195 events that
        // we'll try to decrypt.
        var filter = NDKFilter()
        filter.kinds = [.nostrWalletConnectRes]
        filter.authors = [walletPubkey]
        filter.addTagFilter("e", values: [requestId])
        NDKLogger.log(.trace, category: .wallet, "[NWC Response] Filter: kinds=\(filter.kinds ?? []), e-tag=\(requestId), author=\(walletPubkey)")

        // Get the connected relays
        let allRelays = await ndk.relays
        let connectedRelays = allRelays.filter { relay in
            relayURLs.contains { url in
                relay.normalizedURL == URLNormalizer.tryNormalizeRelayUrl(url) ||
                    relay.url == url
            }
        }
        NDKLogger.log(.debug, category: .wallet, "[NWC Response] Using \(connectedRelays.count) connected relays out of \(allRelays.count) total")

        // 2. Create subscription for the response BEFORE publishing
        let relayUrls = Set(connectedRelays.map { $0.url })

        guard !relayUrls.isEmpty else {
            NDKLogger.log(.error, category: .wallet, "[NWC Response] No matching NWC relays found! Expected: \(relayURLs)")
            throw NDKError.notConfigured("No NWC relays connected. Expected: \(relayURLs)")
        }

        // Use NDKSubscription for NWC response monitoring
        // IMPORTANT: groupable: false ensures the subscription REQ is sent immediately
        // before we publish the request event (prevents race condition)
        let options = NDKSubscriptionOptions(
            maxAge: 0, // Always fresh for real-time response monitoring
            cachePolicy: .networkOnly, // Skip cache for NWC responses
            relays: relayUrls,
            groupable: false // Execute immediately, don't wait for grouping
        )
        let dataSource = NDKSubscription<NDKEvent>(ndk: ndk, filter: filter, options: options)

        // Collect response in a task
        let responseTask = Task { () -> T in
            NDKLogger.log(.trace, category: .wallet, "[NWC Response] Waiting for response event...")

            for await batch in dataSource.events {
                for responseEvent in batch {
                    NDKLogger.log(.debug, category: .wallet, "[NWC Response] Got response event:")
                    NDKLogger.log(.trace, category: .wallet, "[NWC Response]   ID: \(responseEvent.id)")
                    NDKLogger.log(.trace, category: .wallet, "[NWC Response]   Pubkey: \(responseEvent.pubkey)")
                    NDKLogger.log(.trace, category: .wallet, "[NWC Response]   Tags: \(responseEvent.tags)")

                    // Defence-in-depth: the filter is authored-locked but a
                    // misconfigured relay could still return foreign events.
                    guard responseEvent.pubkey == walletPubkey else {
                        NDKLogger.log(.warning, category: .wallet,
                                      "[NWC Response] Ignoring event from non-wallet author \(responseEvent.pubkey)")
                        continue
                    }

                    // Decrypt the content (sender is the trusted wallet).
                    NDKLogger.log(.trace, category: .wallet, "[NWC Response] Decrypting content from \(walletPubkey)")
                    let eventContent = responseEvent.content
                    let decryptedContent = try await signer.decrypt(
                        senderPubkey: walletPubkey,
                        value: eventContent,
                        scheme: .nip04
                    )
                    NDKLogger.log(.trace, category: .wallet, "[NWC Response] Decrypted content: \(decryptedContent)")

                    // Parse and return the response
                    let result = try parseResponse(decryptedContent, expectedType: responseType)

                    // AsyncStream will clean up automatically
                    return result
                }
            }

            // If we get here, subscription ended without response
            throw NDKError.timeout(operation: "NWC response", seconds: Int(timeout))
        }

        // 3. Now publish the request to NWC relays specifically
        NDKLogger.log(.debug, category: .wallet, "[NWC Response] Publishing request event \(requestId) to NWC relays: \(relayUrls)")
        let publishedRelays = try await ndk.publish(event, to: relayUrls)
        NDKLogger.log(.debug, category: .wallet, "[NWC Response] Published to \(publishedRelays.count) relays")

        // 5. Race between response and timeout
        let result: T = try await withThrowingTaskGroup(of: T.self) { group in
            // Response task
            group.addTask {
                try await responseTask.value
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
                throw NDKError.timeout(operation: "NWC response", seconds: Int(timeout))
            }

            // Wait for first result (either response or timeout)
            guard let firstResult = try await group.next() else {
                throw NDKError.timeout(operation: "NWC response", seconds: Int(timeout))
            }

            // Cancel the remaining task
            group.cancelAll()

            return firstResult
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
        // Create filter for responses with this request ID, authored by the
        // trusted wallet pubkey only.
        var filter = NDKFilter()
        filter.kinds = [.nostrWalletConnectRes]
        filter.authors = [walletPubkey]
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
            for await batch in dataSource.events {
                for event in batch {
                    // Get the d-tag for this response
                    let eventTags = event.tags
                    guard let dTag = eventTags.first(where: { $0.count >= 2 && $0[0] == "d" }),
                          dTag.count > 1
                    else {
                        continue
                    }

                    let dTagValue = dTag[1]

                    // Decrypt and parse the response. Defence-in-depth check
                    // that the event came from the wallet we trust — the filter
                    // already enforces this but a misbehaving relay could lie.
                    guard event.pubkey == walletPubkey else {
                        continue
                    }

                    do {
                        let eventContent = event.content
                        let decrypted = try await signer.decrypt(
                            senderPubkey: walletPubkey,
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
                // Create filter for notification events (no e-tag). Restrict
                // authors to the trusted wallet pubkey.
                var filter = NDKFilter(kinds: [.nostrWalletConnectRes])
                filter.authors = [walletPubkey]

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
                    for await batch in dataSource.events {
                        for event in batch {
                            // Check if this is an NWC notification (no e-tag)
                            let eventTags = event.tags
                            guard !eventTags.contains(where: { $0.count >= 1 && $0[0] == "e" }) else {
                                continue
                            }

                            // Defence-in-depth: only accept notifications from
                            // the trusted wallet (filter already enforces this).
                            guard event.pubkey == walletPubkey else {
                                continue
                            }

                            // Decrypt the notification
                            do {
                                let eventContent = event.content
                                let decrypted = try await signer.decrypt(
                                    senderPubkey: walletPubkey,
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
                                      let notificationData = json["notification"] as? [String: Any]
                                else {
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

    private func parseResponse<T: Decodable>(_ content: String, expectedType _: T.Type) throws -> T {
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
