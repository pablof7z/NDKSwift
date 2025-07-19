import Foundation

// Sync result structure
public struct NegentropySyncResult {
    public let localEventCount: Int
    public let downloadedEvents: [NDKEvent]
    public let uploadedEvents: [NDKEvent]
    public let messageRounds: Int
    public let bytesTransferred: Int
    public let duration: TimeInterval
    public let relay: String
    
    public var efficiencyRatio: Int {
        // Naive sync would:
        // 1. Send REQ with filter (estimated ~100 bytes)
        // 2. Receive all events from relay (including ones we already have)
        // 3. Send all our events to relay (including ones they already have)
        
        // For events, estimate average size including JSON wrapper
        let avgEventSize = 520 // Average EVENT message size
        let reqSize = 100 // REQ message with filter
        let eoseSize = 20 // EOSE message
        
        // Naive approach would transfer ALL events in both directions
        let naiveDownload = reqSize + (localEventCount + downloadedEvents.count) * avgEventSize + eoseSize
        let naiveUpload = (localEventCount + uploadedEvents.count) * avgEventSize
        let naiveBytes = naiveDownload + naiveUpload
        
        guard naiveBytes > 0 else { return 0 }
        let savedBytes = naiveBytes - bytesTransferred
        return max(0, (savedBytes * 100) / naiveBytes)
    }
}

// Extension to NDK for NIP-77 sync support
extension NDK {
    /// Sync events with a specific relay using NIP-77 Negentropy protocol
    /// - Parameters:
    ///   - filter: Filter to apply for sync
    ///   - relay: Relay URL to sync with
    /// - Returns: Sync result with statistics
    /// - Throws: NIP77Error if sync fails
    public func syncEvents(filter: NDKFilter, relay relayURL: String) async throws -> NegentropySyncResult {
        let startTime = Date()
        
        // Get or create relay connection
        var relay = await pool.getRelay(for: relayURL)
        if relay == nil {
            relay = await pool.addRelay(relayURL)
            try await relay?.connect()
        }
        
        guard relay != nil else {
            throw NIP77Error.relayError("Failed to connect to relay")
        }
        
        // Create sync handler
        let syncHandler = NIP77SyncHandler(ndk: self, cache: cache)
        
        // Store handler for message routing
        await pool.setSyncHandler(syncHandler, for: relayURL)
        
        // Start sync - this will send NEG-OPEN
        let subscriptionId = try await syncHandler.startSync(filter: filter, relayURL: relayURL)
        
        // Wait for sync to complete (with timeout)
        let timeout: TimeInterval = 30.0
        let startWait = Date()
        
        while await syncHandler.isSyncActive(subscriptionId: subscriptionId) {
            if Date().timeIntervalSince(startWait) > timeout {
                throw NIP77Error.timeout("Sync timeout after \(timeout) seconds")
            }
            try await Task.sleep(nanoseconds: 100 * TimeConstants.nanosecondsPerMillisecond) // 100ms
        }
        
        // Get completed session data
        guard let session = await syncHandler.getCompletedSession(subscriptionId: subscriptionId) else {
            throw NIP77Error.relayError("Sync session not found")
        }
        
        // Use the actual events from the session
        let downloadedEvents = session.actualDownloadedEvents
        let uploadedEvents = session.actualUploadedEvents
        
        let localEventCount = try await countLocalEvents(filter: filter)
        
        // Calculate efficiency
        let naiveBytes = (localEventCount + downloadedEvents.count) * 500 // ~500 bytes per event
        _ = max(0, 100 - ((session.bytesTransferred * 100) / max(1, naiveBytes)))
        
        return NegentropySyncResult(
            localEventCount: localEventCount,
            downloadedEvents: downloadedEvents,
            uploadedEvents: uploadedEvents,
            messageRounds: session.messageRounds,
            bytesTransferred: session.bytesTransferred,
            duration: Date().timeIntervalSince(startTime),
            relay: relayURL
        )
    }
    
    /// Sync with all connected relays
    /// - Parameter filter: Filter to apply for sync
    /// - Returns: Dictionary of relay URLs to sync results
    public func syncWithAllRelays(filter: NDKFilter) async throws -> [String: NegentropySyncResult] {
        let relays = await pool.connectedRelays()
        
        return await withTaskGroup(of: (String, NegentropySyncResult?).self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        let result = try await self.syncEvents(filter: filter, relay: relay.url)
                        return (relay.url, result)
                    } catch {
                        // Log error but don't fail entire sync
                        NDKLogger.shared.log(.warning, category: .relay, "Sync failed for \(relay.url): \(error)")
                        return (relay.url, nil)
                    }
                }
            }
            
            var results: [String: NegentropySyncResult] = [:]
            for await (relay, result) in group {
                if let result = result {
                    results[relay] = result
                }
            }
            return results
        }
    }
    
    /// Check if a relay supports NIP-77
    /// - Parameter relayURL: Relay URL to check
    /// - Returns: True if relay supports NIP-77
    public func relaySupportsNegentropy(_ relayURL: String) async -> Bool {
        // First check if we have a connected relay
        guard let relay = await pool.getRelay(for: relayURL) else {
            return false
        }
        
        // Check the relay's NIP-11 information first
        if let info = await relay.info,
           let supportedNips = info.supportedNips {
            // If NIP-11 says it supports NIP-77, trust it
            if supportedNips.contains(77) {
                return true
            }
        }
        
        // If no explicit support in NIP-11, we'll try anyway
        // Some relays might support it without advertising
        return false  // Changed to false but we'll still try in the demo
    }
    
    // MARK: - Helper Methods
    
    private func fetchEvents(ids: [String]) async -> [NDKEvent] {
        var events: [NDKEvent] = []
        for id in ids {
            if let event = await cache.getEvent(id: id) {
                events.append(event)
            }
        }
        return events
    }
    
    private func countLocalEvents(filter: NDKFilter) async throws -> Int {
        let events = try await cache.queryEvents(filter)
        return events.count
    }
}

// Extension for relay pool to manage sync handlers
extension NDKPool {
    private static var syncHandlers = [String: NIP77SyncHandler]()
    
    func setSyncHandler(_ handler: NIP77SyncHandler, for relayURL: String) {
        let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(relayURL) ?? relayURL
        Self.syncHandlers[normalizedURL] = handler
    }
    
    func getSyncHandler(for relayURL: String) -> NIP77SyncHandler? {
        let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(relayURL) ?? relayURL
        return Self.syncHandlers[normalizedURL]
    }
    
    func removeSyncHandler(for relayURL: String) {
        let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(relayURL) ?? relayURL
        Self.syncHandlers.removeValue(forKey: normalizedURL)
    }
}

// Extension for NIP77SyncHandler to support completion tracking
extension NIP77SyncHandler {
    struct CompletedSession {
        let downloadedEventIds: [String]
        let uploadedEventIds: [String]
        let messageRounds: Int
        let bytesTransferred: Int
    }
    
    private static var completedSessions = [String: CompletedSession]()
    
    
    func getActiveSession(subscriptionId: String) async -> SyncSession? {
        return activeSessions[subscriptionId]
    }
    
    
    func completeSession(_ session: SyncSession, subscriptionId: String) {
        Self.completedSessions[subscriptionId] = CompletedSession(
            downloadedEventIds: Array(session.downloadedEventIds),
            uploadedEventIds: Array(session.uploadedEventIds),
            messageRounds: session.messageRounds,
            bytesTransferred: session.bytesTransferred
        )
    }
}