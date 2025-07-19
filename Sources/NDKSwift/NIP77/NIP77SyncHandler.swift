import Foundation

/// Handles NIP-77 Negentropy sync operations
/// Note: Modified for wallet use - only downloads events, does not upload
public actor NIP77SyncHandler {
    private let ndk: NDK
    private let cache: any NDKCache
    private let storage: NDKCacheNegentropyStorage
    
    /// Current sync sessions indexed by subscription ID
    var activeSessions: [String: SyncSession] = [:]
    
    /// Completed sessions (kept briefly for result retrieval)
    var completedSessions: [String: SyncSession] = [:]
    
    public struct SyncSession {
        let filter: NDKFilter
        let relayURL: String
        let startTime: Date
        let negentropy: Negentropy
        var messageRounds: Int = 0
        var bytesTransferred: Int = 0
        var negentropyBytes: Int = 0  // Just Negentropy protocol
        var eventFetchBytes: Int = 0   // REQ/EVENT/EOSE for downloads
        var eventPublishBytes: Int = 0 // EVENT messages for uploads
        var downloadedEventIds: Set<String> = []
        var uploadedEventIds: Set<String> = []
        var actualDownloadedEvents: [NDKEvent] = []
        var actualUploadedEvents: [NDKEvent] = []
    }
    
    public init(ndk: NDK, cache: any NDKCache) {
        self.ndk = ndk
        self.cache = cache
        self.storage = NDKCacheNegentropyStorage(cache: cache)
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
            message: initialMessage.hexEncodedString()
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
            throw NIP77Error.invalidMessage
        }
        
        guard var session = activeSessions[subscriptionId] else {
            throw NIP77Error.invalidMessage
        }
        
        switch message {
        case let .negMsg(_, dataHex):
            print("[NIP77] Received NEG-MSG with data: \(dataHex)")
            
            guard let data = Data(hex: dataHex) else {
                throw NIP77Error.invalidMessage
            }
            
            // Update stats
            session.messageRounds += 1
            session.negentropyBytes += data.count
            session.bytesTransferred += data.count
            
            print("[NIP77] Processing message with negentropy...")
            
            // Process with negentropy (use session's instance)
            let (responseData, haveIds, needIds) = try await session.negentropy.reconcile(data)
            
            print("[NIP77] Negentropy response - have: \(haveIds.count), need: \(needIds.count), hasResponse: \(responseData != nil)")
            
            // Track what we need to download
            for id in needIds {
                session.downloadedEventIds.insert(id)
            }
            
            // Track what they need from us (but we won't send)
            for id in haveIds {
                session.uploadedEventIds.insert(id)
            }
            
            if !haveIds.isEmpty {
                print("[NIP77] Relay requested \(haveIds.count) events, but upload is disabled for wallet sync")
            }
            
            // Update session
            activeSessions[subscriptionId] = session
            
            if let responseData = responseData {
                // Continue reconciliation
                let relay = await ndk.pool.getRelay(for: session.relayURL)
                if let relay = relay {
                    let nostrMessage = NostrMessage.negMsg(
                        subscriptionId: subscriptionId,
                        message: responseData.hexEncodedString()
                    )
                    try? await relay.send(nostrMessage.serialize())
                }
            } else {
                // Reconciliation complete
                // Fetch missing events
                if !session.downloadedEventIds.isEmpty {
                    let (downloadedEvents, fetchBytes) = await fetchMissingEvents(
                        ids: Array(session.downloadedEventIds),
                        relayURL: session.relayURL
                    )
                    session.actualDownloadedEvents = downloadedEvents
                    session.eventFetchBytes = fetchBytes
                    session.bytesTransferred += fetchBytes
                }
                
                // Skip uploading events - wallet should only receive
                // Comment out the upload phase to make sync one-directional
                /*
                if !session.uploadedEventIds.isEmpty {
                    let (uploadedEvents, publishBytes) = await sendEvents(
                        ids: Array(session.uploadedEventIds),
                        relayURL: session.relayURL
                    )
                    session.actualUploadedEvents = uploadedEvents
                    session.eventPublishBytes = publishBytes
                    session.bytesTransferred += publishBytes
                }
                */
                
                // Close the sync through relay
                let relay = await ndk.pool.getRelay(for: session.relayURL)
                if let relay = relay {
                    let nostrMessage = NostrMessage.negClose(subscriptionId: subscriptionId)
                    let closeMessage = try nostrMessage.serialize()
                    session.negentropyBytes += closeMessage.count
                    session.bytesTransferred += closeMessage.count
                    try? await relay.send(closeMessage)
                }
                
                // Move to completed sessions
                completedSessions[subscriptionId] = session
                activeSessions.removeValue(forKey: subscriptionId)
            }
            
        case let .negErr(_, error):
            // Handle error from relay
            activeSessions.removeValue(forKey: subscriptionId)
            throw NIP77Error.relayError(error)
            
        case .negClose(_):
            // Relay closed the sync
            activeSessions.removeValue(forKey: subscriptionId)
            
        default:
            // We don't expect other message types
            throw NIP77Error.invalidMessage
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
    
    // MARK: - Helper Methods
    
    private func generateSubscriptionId() -> String {
        return IDGenerator.randomId(prefix: "sync", length: 16)
    }
    
    private func fetchMissingEvents(ids: [String], relayURL: String) async -> (events: [NDKEvent], bytesUsed: Int) {
        // Create filter for specific event IDs
        let filter = NDKFilter(ids: ids)
        
        print("[NIP77] Fetching \(ids.count) events from \(relayURL)")
        
        // Estimate bandwidth for REQ message
        let reqMessage = "[\"REQ\",\"sub\",{\"ids\":[\(ids.map { "\"\($0)\"" }.joined(separator: ","))]}]"
        var totalBytes = reqMessage.count
        
        // Fetch events using regular REQ/EVENT protocol
        do {
            let events = try await ndk.fetchEvents([filter])
            
            // Store events in cache and estimate bandwidth
            for event in events {
                try? await cache.saveEvent(event)
                // Estimate EVENT message size
                let eventJson = try? event.toJSON()
                totalBytes += (eventJson?.count ?? 500) + 20 // +20 for ["EVENT","sub", wrapper]
            }
            
            // Add EOSE message
            totalBytes += 15 // ["EOSE","sub"]
            
            print("[NIP77] Successfully fetched and cached \(events.count) events (bandwidth: \(totalBytes) bytes)")
            return (Array(events), totalBytes)
        } catch {
            print("[NIP77] Error fetching events: \(error)")
            return ([], totalBytes)
        }
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
            print("[NIP77] No events found in cache to send")
            return ([], 0)
        }
        
        print("[NIP77] Sending \(eventsToSend.count) events to \(relayURL)")
        
        // Send events to relay
        do {
            for event in eventsToSend {
                _ = try await ndk.publish(event: event, to: [relayURL])
                // Estimate EVENT message size
                let eventJson = try? event.toJSON()
                totalBytes += (eventJson?.count ?? 500) + 10 // +10 for ["EVENT", wrapper]
            }
            print("[NIP77] Successfully sent \(eventsToSend.count) events (bandwidth: \(totalBytes) bytes)")
            return (eventsToSend, totalBytes)
        } catch {
            print("[NIP77] Error sending events: \(error)")
            return ([], totalBytes)
        }
    }
}

// Removed - already defined in NDKSyncExtension.swift