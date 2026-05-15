import Foundation

/// Direction of sync operations
public enum SyncDirection {
    case send // Only upload events to relay
    case receive // Only download events from relay
    case both // Bidirectional sync (default)
}

/// Handles NIP-77 Negentropy sync operations
public actor NIP77SyncHandler {
    /// Log prefix constant for NIP77 sync handler related logging
    private let logPrefix = "[NIP77]"

    private let ndk: NDK
    private let cache: NDKNostrDBCache
    private let storage: NDKCacheNegentropyStorage

    /// Direction of sync operations
    /// Default is .both for bidirectional sync
    public var syncDirection: SyncDirection = .both

    /// Current sync sessions indexed by subscription ID
    var activeSessions: [String: SyncSession] = [:]

    /// Completed sessions (kept briefly for result retrieval)
    var completedSessions: [String: SyncSession] = [:]

    /// Continuations awaiting the completion of a sync session (per id).
    /// Replaces a previous 100ms `Task.sleep` polling loop in NDKSyncExtension
    /// that hammered actor isolation ~10× per second per active sync.
    private var completionWaiters: [String: [CheckedContinuation<SyncSession, Error>]] = [:]

    private func resolveWaiters(subscriptionId: String, with result: Result<SyncSession, Error>) {
        guard let waiters = completionWaiters.removeValue(forKey: subscriptionId) else { return }
        for waiter in waiters {
            switch result {
            case let .success(session):
                waiter.resume(returning: session)
            case let .failure(error):
                waiter.resume(throwing: error)
            }
        }
    }

    public struct SyncSession {
        let filter: NDKFilter
        let relayURL: String
        let startTime: Date
        let negentropy: Negentropy
        var messageRounds: Int = 0
        var bytesTransferred: Int = 0
        var negentropyBytes: Int = 0 // Just Negentropy protocol
        var eventFetchBytes: Int = 0 // REQ/EVENT/EOSE for downloads
        var eventPublishBytes: Int = 0 // EVENT messages for uploads
        var downloadedEventIds: Set<String> = []
        var uploadedEventIds: Set<String> = []
        var actualDownloadedEvents: [NDKEvent] = []
        var actualUploadedEvents: [NDKEvent] = []
    }

    public init(ndk: NDK, cache: NDKNostrDBCache) {
        self.ndk = ndk
        self.cache = cache
        storage = NDKCacheNegentropyStorage(cache: cache)
    }

    /// Set the sync direction
    public func setSyncDirection(_ direction: SyncDirection) {
        syncDirection = direction
    }

    /// Start a sync operation with a relay
    public func startSync(filter: NDKFilter, relayURL: String) async throws -> String {
        let subscriptionId = generateSubscriptionId()

        // Initialize negentropy with filter
        await storage.setFilter(filter)
        let negentropy = Negentropy(storage: storage)
        let initialMessage = try await negentropy.initiate()

        // Create session
        var session = SyncSession(
            filter: filter,
            relayURL: relayURL,
            startTime: Date(),
            negentropy: negentropy
        )
        activeSessions[subscriptionId] = session

        // Send NEG-OPEN message through relay
        let relay = await ndk.pool.getRelay(for: relayURL)
        guard let relay = relay else {
            throw NIP77Error.relayError("Relay not found: \(relayURL)")
        }

        // Create and send NEG-OPEN message
        let nostrMessage = NostrMessage.negOpen(
            subscriptionId: subscriptionId,
            filter: filter,
            message: initialMessage.hexString
        )

        let negOpenMessage = try nostrMessage.serialize()
        try await relay.send(negOpenMessage)

        // Track the initial message bandwidth
        session.negentropyBytes = initialMessage.count + negOpenMessage.count
        session.bytesTransferred = session.negentropyBytes
        activeSessions[subscriptionId] = session

        return subscriptionId
    }

    /// Handle incoming NIP-77 message
    public func handleMessage(_ message: NostrMessage) async throws {
        let subscriptionId: String

        switch message {
        case let .negMsg(subId, _):
            subscriptionId = subId
        case let .negErr(subId, _):
            subscriptionId = subId
        case let .negClose(subId):
            subscriptionId = subId
        default:
            throw NIP77Error.invalidMessageFormat("Unknown message type")
        }

        guard var session = activeSessions[subscriptionId] else {
            throw NIP77Error.invalidMessageFormat("Unknown message type")
        }

        switch message {
        case let .negMsg(_, dataHex):
            NDKLogger.log(.debug, category: .network, "\(logPrefix) Received NEG-MSG with data: \(dataHex)")

            guard let data = Data(hexString: dataHex) else {
                throw NIP77Error.invalidMessageFormat("Unknown message type")
            }

            // Update stats
            session.messageRounds += 1
            session.negentropyBytes += data.count
            session.bytesTransferred += data.count

            NDKLogger.log(.debug, category: .network, "\(logPrefix) Processing message with negentropy...")

            // Process with negentropy (use session's instance)
            let (responseData, haveIds, needIds) = try await session.negentropy.reconcile(data)

            NDKLogger.log(.debug, category: .network, "\(logPrefix) Negentropy response - have: \(haveIds.count), need: \(needIds.count), hasResponse: \(responseData != nil)")

            // Track what we need to download
            for id in needIds {
                session.downloadedEventIds.insert(id)
            }

            // Track what they need from us
            for id in haveIds {
                session.uploadedEventIds.insert(id)
            }

            // Update session
            activeSessions[subscriptionId] = session

            if let responseData = responseData {
                // Continue reconciliation
                let relay = await ndk.pool.getRelay(for: session.relayURL)
                if let relay = relay {
                    let nostrMessage = NostrMessage.negMsg(
                        subscriptionId: subscriptionId,
                        message: responseData.hexString
                    )
                    do {
                        try await relay.send(nostrMessage.serialize())
                    } catch {
                        NDKLogger.log(.warning, category: .relay, "Failed to send NEG-MSG during NIP77 sync to \(session.relayURL): \(error.localizedDescription)")
                    }
                }
            } else {
                // Reconciliation complete
                // Handle downloads based on sync direction
                if !session.downloadedEventIds.isEmpty, syncDirection != .send {
                    let (downloadedEvents, fetchBytes) = await fetchMissingEvents(
                        ids: Array(session.downloadedEventIds),
                        relayURL: session.relayURL
                    )
                    session.actualDownloadedEvents = downloadedEvents
                    session.eventFetchBytes = fetchBytes
                    session.bytesTransferred += fetchBytes
                } else if !session.downloadedEventIds.isEmpty, syncDirection == .send {
                    NDKLogger.log(.info, category: .network, "\(logPrefix) Relay has \(session.downloadedEventIds.count) events we don't have, but sync direction is send-only")
                }

                // Handle uploads based on sync direction
                if !session.uploadedEventIds.isEmpty, syncDirection != .receive {
                    let (uploadedEvents, publishBytes) = await sendEvents(
                        ids: Array(session.uploadedEventIds),
                        relayURL: session.relayURL
                    )
                    session.actualUploadedEvents = uploadedEvents
                    session.eventPublishBytes = publishBytes
                    session.bytesTransferred += publishBytes
                } else if !session.uploadedEventIds.isEmpty, syncDirection == .receive {
                    NDKLogger.log(.info, category: .network, "\(logPrefix) Relay requested \(session.uploadedEventIds.count) events, but sync direction is receive-only")
                }

                // Close the sync through relay
                let relay = await ndk.pool.getRelay(for: session.relayURL)
                if let relay = relay {
                    let nostrMessage = NostrMessage.negClose(subscriptionId: subscriptionId)
                    let closeMessage = try nostrMessage.serialize()
                    session.negentropyBytes += closeMessage.count
                    session.bytesTransferred += closeMessage.count
                    do {
                        try await relay.send(closeMessage)
                    } catch {
                        NDKLogger.log(.warning, category: .relay, "Failed to send NEG-CLOSE during NIP77 sync to \(session.relayURL): \(error.localizedDescription)")
                    }
                }

                // Move to completed sessions
                completedSessions[subscriptionId] = session
                activeSessions.removeValue(forKey: subscriptionId)

                // Remove self from NDKPool's static map to prevent memory leak
                await ndk.pool.removeSyncHandler(for: session.relayURL)
                resolveWaiters(subscriptionId: subscriptionId, with: .success(session))
            }

        case let .negErr(_, error):
            // Handle error from relay
            if let session = activeSessions.removeValue(forKey: subscriptionId) {
                // Remove self from NDKPool's static map to prevent memory leak
                await ndk.pool.removeSyncHandler(for: session.relayURL)
            }
            resolveWaiters(subscriptionId: subscriptionId, with: .failure(NIP77Error.relayError(error)))
            throw NIP77Error.relayError(error)

        case .negClose:
            // Relay closed the sync
            if let session = activeSessions.removeValue(forKey: subscriptionId) {
                // Remove self from NDKPool's static map to prevent memory leak
                await ndk.pool.removeSyncHandler(for: session.relayURL)
                // Treat a relay-side close as completion with whatever we have.
                completedSessions[subscriptionId] = session
                resolveWaiters(subscriptionId: subscriptionId, with: .success(session))
            } else {
                resolveWaiters(subscriptionId: subscriptionId,
                               with: .failure(NIP77Error.relayError("Relay closed sync session before it started")))
            }

        default:
            // We don't expect other message types
            throw NIP77Error.invalidMessageFormat("Unknown message type")
        }
    }

    /// Check if a sync session is still active
    public func isSyncActive(subscriptionId: String) async -> Bool {
        return activeSessions[subscriptionId] != nil
    }

    /// Get completed session
    public func getCompletedSession(subscriptionId: String) async -> SyncSession? {
        return completedSessions[subscriptionId]
    }

    /// Suspend until the given sync session completes (or `timeout` elapses).
    /// Replaces a 100ms polling loop with a direct completion signal.
    public func waitForCompletion(subscriptionId: String, timeout: TimeInterval) async throws -> SyncSession {
        // Fast paths: already completed or never started.
        if let session = completedSessions[subscriptionId] {
            return session
        }
        guard activeSessions[subscriptionId] != nil else {
            throw NIP77Error.relayError("No active sync session for id \(subscriptionId)")
        }

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
            await self?.timeOutWaiters(subscriptionId: subscriptionId, timeout: timeout)
        }

        do {
            let session = try await withCheckedThrowingContinuation { continuation in
                completionWaiters[subscriptionId, default: []].append(continuation)
            }
            timeoutTask.cancel()
            return session
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }

    /// Internal helper used by the timeout Task to fail pending waiters.
    private func timeOutWaiters(subscriptionId: String, timeout: TimeInterval) {
        resolveWaiters(
            subscriptionId: subscriptionId,
            with: .failure(NIP77Error.timeout("Sync timeout after \(timeout) seconds"))
        )
    }

    // MARK: - Helper Methods

    private func generateSubscriptionId() -> String {
        return IDGenerator.randomId(prefix: "sy", length: 8)
    }

    private func fetchMissingEvents(ids: [String], relayURL: String) async -> (events: [NDKEvent], bytesUsed: Int) {
        // Create filter for specific event IDs
        let filter = NDKFilter(ids: ids)

        NDKLogger.log(.info, category: .network, "\(logPrefix) Fetching \(ids.count) events from \(relayURL)")

        // Estimate bandwidth for REQ message
        let reqMessage = "[\"REQ\",\"sub\",{\"ids\":[\(ids.map { "\"\($0)\"" }.joined(separator: ","))]}]"
        var totalBytes = reqMessage.count

        // Fetch events until EOSE (sync operations need all events)
        let events = await ndk.fetchEvents(
            filter: filter,
            cachePolicy: .networkOnly, // Skip cache for sync operations
            timeout: NetworkConstants.timeoutDataCollectionSync
        )

        // Store events in cache and estimate bandwidth
        for event in events {
            // Use processEvent to ensure observers are notified
            do {
                try await cache.processEvent(event, from: relayURL, subscriptionId: "nip77-sync-\(relayURL)")
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to process event \(event.id) during NIP77 sync: \(error.localizedDescription)")
            }
            // Estimate EVENT message size
            let eventJson: String?
            do {
                eventJson = try event.toJSON()
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to serialize event \(event.id) to JSON during NIP77 sync: \(error.localizedDescription)")
                eventJson = nil
            }
            totalBytes += (eventJson?.count ?? 500) + 20 // +20 for ["EVENT","sub", wrapper]
        }

        // Add EOSE message
        totalBytes += 15 // ["EOSE","sub"]

        NDKLogger.log(.info, category: .network, "\(logPrefix) Successfully fetched and cached \(events.count) events (bandwidth: \(totalBytes) bytes)")
        return (Array(events), totalBytes)
    }

    private func sendEvents(ids: [String], relayURL: String) async -> (events: [NDKEvent], bytesUsed: Int) {
        // Get events from cache
        var eventsToSend: [NDKEvent] = []
        var totalBytes = 0

        for id in ids {
            if let event = await cache.getEvent(id: id) {
                eventsToSend.append(event)
            }
        }

        if eventsToSend.isEmpty {
            NDKLogger.log(.warning, category: .network, "\(logPrefix) No events found in cache to send")
            return ([], 0)
        }

        NDKLogger.log(.info, category: .network, "\(logPrefix) Sending \(eventsToSend.count) events to \(relayURL)")

        // Send events to relay
        do {
            for event in eventsToSend {
                _ = try await ndk.publish(event, to: [relayURL])
                // Estimate EVENT message size
                let eventJson: String?
                do {
                    eventJson = try event.toJSON()
                } catch {
                    NDKLogger.log(.warning, category: .cache, "Failed to serialize event \(event.id) to JSON during NIP77 send: \(error.localizedDescription)")
                    eventJson = nil
                }
                totalBytes += (eventJson?.count ?? 500) + 10 // +10 for ["EVENT", wrapper]
            }
            NDKLogger.log(.info, category: .network, "\(logPrefix) Successfully sent \(eventsToSend.count) events (bandwidth: \(totalBytes) bytes)")
            return (eventsToSend, totalBytes)
        } catch {
            NDKLogger.log(.error, category: .network, "\(logPrefix) Error sending events: \(error)")
            return ([], totalBytes)
        }
    }
}

// Removed - already defined in NDKSyncExtension.swift
