import Foundation
import CashuSwift

/// Comprehensive in-memory cache implementation for testing and temporary use
public actor MemoryCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var profiles: [String: NDKUserProfile] = [:]
    private var eventConfirmations: [String: EventConfirmationState] = [:]
    private var unpublishedEventRelays: [String: Set<String>] = [:]
    private var eventCreationTimes: [String: Date] = [:]
    private var decryptedContent: LRUCache<String, String>
    private var mintInfos: [String: (info: NDKMintInfo, timestamp: Date)] = [:]
    private var keysets: [String: CashuSwift.Keyset] = [:]
    private var mintKeysets: [String: [(keyset: CashuSwift.Keyset, timestamp: Date)]] = [:]
    
    // Tombstone cache for deletion events that arrive before the original event
    private var deletionTombstones: [String: Date] = [:]
    private let tombstoneTTL: TimeInterval = NetworkConstants.tombstoneTTL
    
    // Observer tracking
    private var observers: [FilterSignature: Set<WeakObserver>] = [:]
    
    public init() {
        // Initialize LRU cache with configured item limit for decrypted content
        self.decryptedContent = LRUCache(capacity: NetworkConstants.defaultCacheCapacity)
    }
    
    // MARK: - Event Operations
    
    public func saveEvent(_ event: NDKEvent) async throws {
        // Skip ephemeral events (20000-29999)
        if EventKind.isEphemeral(event.kind) {
            NDKLogger.log(.trace, category: .cache, "MemoryCache: Skipping ephemeral event (kind: \(event.kind)): \(event.id)")
            return
        }
        
        let eventId = event.id
        let isNew = events[eventId] == nil
        events[eventId] = event
        
        // Notify observers if this is a new event
        if isNew {
            await notifyObservers(of: event)
        }
    }
    
    public func getEvent(id: String) async -> NDKEvent? {
        let event = events[id]
        NDKLogger.log(.trace, category: .cache, "Retrieved event \(id): \(event != nil ? "found" : "not found")")
        return event
    }
    
    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        var results: [NDKEvent] = []
        
        for event in events.values {
            if filter.matches(event: event) {
                results.append(event)
            }
        }
        
        // Apply limit if specified
        if let limit = filter.limit, limit > 0 {
            results = Array(results.prefix(limit))
        }
        
        // Sort by created_at descending
        // Extract created_at values for sorting
        let sortedResults = await withTaskGroup(of: (NDKEvent, Timestamp).self) { group in
            for event in results {
                group.addTask {
                    let timestamp = event.createdAt
                    return (event, timestamp)
                }
            }
            
            var eventWithTimestamps: [(NDKEvent, Timestamp)] = []
            for await result in group {
                eventWithTimestamps.append(result)
            }
            
            // Sort by timestamp descending
            eventWithTimestamps.sort { $0.1 > $1.1 }
            
            return eventWithTimestamps.map { $0.0 }
        }
        
        results = sortedResults
        
        return results
    }
    
    public func deleteEvent(id: String) async throws {
        events.removeValue(forKey: id)
        NDKLogger.log(.debug, category: .cache, "Deleted event \(id)")
    }
    
    // MARK: - Profile Operations
    
    public func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        profiles[pubkey] = profile
        NDKLogger.log(.trace, category: .cache, "Saved profile for \(pubkey)")
    }
    
    public func getProfile(pubkey: String) async -> NDKUserProfile? {
        let profile = profiles[pubkey]
        NDKLogger.log(.trace, category: .cache, "Retrieved profile for \(pubkey): \(profile != nil ? "found" : "not found")")
        return profile
    }
    
    // MARK: - Cache Management
    
    public func clear() async throws {
        events.removeAll()
        profiles.removeAll()
        eventConfirmations.removeAll()
        mintInfos.removeAll()
        keysets.removeAll()
        mintKeysets.removeAll()
        await decryptedContent.clear()
        NDKLogger.log(.info, category: .cache, "Cleared all cache data")
    }
    
    // MARK: - Optimistic Publishing Support
    
    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        let eventId = event.id
        events[eventId] = event
        eventConfirmations[eventId] = .optimistic
        unpublishedEventRelays[eventId] = relays
        eventCreationTimes[eventId] = Date()
        NDKLogger.log(.debug, category: .cache, "Added unpublished event \(eventId) for relays: \(relays.joined(separator: ", "))")
    }
    
    public func confirmEvent(eventId: String, onRelay relay: String) async throws {
        if let existingState = eventConfirmations[eventId] {
            switch existingState {
            case .optimistic:
                eventConfirmations[eventId] = .confirmed(fromRelay: relay)
                NDKLogger.log(.debug, category: .cache, "Confirmed event \(eventId) on relay \(relay)")
            case .confirmed:
                NDKLogger.log(.trace, category: .cache, "Event \(eventId) already confirmed")
            }
        } else {
            // Event not found, might have been confirmed directly
            eventConfirmations[eventId] = .confirmed(fromRelay: relay)
            NDKLogger.log(.debug, category: .cache, "Marked event \(eventId) as confirmed on relay \(relay)")
        }
    }
    
    public func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return eventConfirmations[eventId]
    }
    
    public func getUnpublishedEvents(maxAge: TimeInterval = TimeConstants.hour, limit: Int? = nil) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        let cutoffTime = Date().addingTimeInterval(-maxAge)
        var results: [(event: NDKEvent, targetRelays: Set<String>)] = []
        
        for (eventId, confirmationState) in eventConfirmations {
            // Only include optimistic events
            guard case .optimistic = confirmationState else { continue }
            
            // Check age constraint
            if let creationTime = eventCreationTimes[eventId], creationTime < cutoffTime {
                continue
            }
            
            // Get the event and relays
            guard let event = events[eventId],
                  let targetRelays = unpublishedEventRelays[eventId] else { continue }
            
            results.append((event: event, targetRelays: targetRelays))
        }
        
        // Sort by creation time (newest first)
        results.sort { lhs, rhs in
            let lhsTime = eventCreationTimes[lhs.event.id] ?? Date.distantPast
            let rhsTime = eventCreationTimes[rhs.event.id] ?? Date.distantPast
            return lhsTime > rhsTime
        }
        
        // Apply limit if specified
        if let limit = limit, limit > 0 {
            results = Array(results.prefix(limit))
        }
        
        NDKLogger.log(.trace, category: .cache, "Found \(results.count) unpublished events (maxAge: \(maxAge)s)")
        return results
    }
    
    // MARK: - Decrypted Content Cache
    
    public func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        let key = "\(eventId):\(viewerPubkey)"
        return await decryptedContent.get(key)
    }
    
    public func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        let key = "\(eventId):\(viewerPubkey)"
        await decryptedContent.set(key, value: content)
        NDKLogger.log(.trace, category: .cache, "Cached decrypted content for event \(eventId) viewer \(viewerPubkey)")
    }
    
    public func clearDecryptedContent() async {
        await decryptedContent.clear()
        NDKLogger.log(.debug, category: .cache, "Cleared all decrypted content")
    }
    
    public func clearDecryptedContent(for viewerPubkey: String) async {
        // Get all keys that end with the viewer pubkey
        let allItems = await decryptedContent.allItems()
        for (key, _) in allItems where key.hasSuffix(":\(viewerPubkey)") {
            await decryptedContent.delete(key)
        }
        NDKLogger.log(.debug, category: .cache, "Cleared decrypted content for viewer \(viewerPubkey)")
    }
    
    // MARK: - Debug Helpers
    
    public func eventCount() async -> Int {
        return events.count
    }
    
    public func profileCount() async -> Int {
        return profiles.count
    }
    
    public func unconfirmedEventCount() async -> Int {
        return eventConfirmations.values.filter { !$0.isConfirmed }.count
    }
    
    // MARK: - Mint Cache Operations
    
    public func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        mintInfos[url] = (info, Date())
        NDKLogger.log(.trace, category: .cache, "Saved mint info for \(url)")
    }
    
    public func getMintInfo(url: String) async -> NDKMintInfo? {
        let info = mintInfos[url]?.info
        NDKLogger.log(.trace, category: .cache, "Retrieved mint info for \(url): \(info != nil ? "found" : "not found")")
        return info
    }
    
    public func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        guard let entry = mintInfos[url] else { return true }
        let isStale = Date().timeIntervalSince(entry.timestamp) > maxAge
        NDKLogger.log(.trace, category: .cache, "Mint info for \(url) is \(isStale ? "stale" : "fresh")")
        return isStale
    }
    
    public func invalidateMintCache(url: String) async throws {
        mintInfos.removeValue(forKey: url)
        mintKeysets.removeValue(forKey: url)
        NDKLogger.log(.debug, category: .cache, "Invalidated mint cache for \(url)")
    }
    
    public func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        keysets[keyset.keysetID] = keyset
        
        var mintList = mintKeysets[mintUrl] ?? []
        mintList.append((keyset, Date()))
        mintKeysets[mintUrl] = mintList
        
        NDKLogger.log(.trace, category: .cache, "Saved keyset \(keyset.keysetID) for mint \(mintUrl)")
    }
    
    public func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        let timestamp = Date()
        var mintList = mintKeysets[mintUrl] ?? []
        
        for keyset in keysets {
            self.keysets[keyset.keysetID] = keyset
            mintList.append((keyset, timestamp))
        }
        
        mintKeysets[mintUrl] = mintList
        NDKLogger.log(.debug, category: .cache, "Saved \(keysets.count) keysets for mint \(mintUrl)")
    }
    
    public func getKeyset(id: String) async -> CashuSwift.Keyset? {
        let keyset = keysets[id]
        NDKLogger.log(.trace, category: .cache, "Retrieved keyset \(id): \(keyset != nil ? "found" : "not found")")
        return keyset
    }
    
    public func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        let keysets = mintKeysets[mintUrl]?.map { $0.keyset } ?? []
        NDKLogger.log(.trace, category: .cache, "Retrieved \(keysets.count) keysets for mint \(mintUrl)")
        return keysets
    }
    
    public func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] {
        let activeKeysets = mintKeysets[mintUrl]?
            .map { $0.keyset }
            .filter { $0.unit == unit && $0.active } ?? []
        NDKLogger.log(.trace, category: .cache, "Retrieved \(activeKeysets.count) active keysets for mint \(mintUrl) unit \(unit)")
        return activeKeysets
    }
    
    public func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool {
        guard let entries = mintKeysets[mintUrl], !entries.isEmpty else { 
            NDKLogger.log(.debug, category: .cache, "No keysets found for mint \(mintUrl), considering stale")
            return true 
        }
        
        let oldestTimestamp = entries.map { $0.timestamp }.min() ?? Date()
        let isStale = Date().timeIntervalSince(oldestTimestamp) > maxAge
        NDKLogger.log(.trace, category: .cache, "Keysets for mint \(mintUrl) are \(isStale ? "stale" : "fresh")")
        return isStale
    }
    
    // MARK: - Negentropy Support
    
    public func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        var results: [NDKEvent] = []
        
        for event in events.values {
            // Check time range
            if event.createdAt < from || event.createdAt >= to {
                continue
            }
            
            // Apply filter if provided
            if let filter = filter {
                if !filter.matches(event: event) {
                    continue
                }
            }
            
            results.append(event)
        }
        
        // Sort by timestamp for consistent ordering
        let sorted = results.sorted { $0.createdAt < $1.createdAt }
        NDKLogger.log(.trace, category: .cache, "Found \(sorted.count) events in range [\(from), \(to))")
        return sorted
    }
    
    public func getEventIdsWithTimestamps(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [(id: String, timestamp: Timestamp)] {
        var results: [(id: String, timestamp: Timestamp)] = []
        
        for event in events.values {
            // Check time range
            if event.createdAt < from || event.createdAt >= to {
                continue
            }
            
            // Apply filter if provided
            if let filter = filter {
                if !filter.matches(event: event) {
                    continue
                }
            }
            
            results.append((id: event.id, timestamp: event.createdAt))
        }
        
        // Sort by timestamp for consistent ordering
        let sorted = results.sorted { $0.timestamp < $1.timestamp }
        NDKLogger.log(.trace, category: .cache, "Found \(sorted.count) event IDs in range [\(from), \(to))")
        return sorted
    }
    
    public func hasEvents(ids: [String]) async -> [String: Bool] {
        var result: [String: Bool] = [:]
        
        for id in ids {
            result[id] = events[id] != nil
        }
        
        let foundCount = result.values.filter { $0 }.count
        NDKLogger.log(.trace, category: .cache, "Checked \(ids.count) event IDs, found \(foundCount)")
        return result
    }
    
    // MARK: - Event Processing with Deletion Support
    
    public func processEvent(
        _ event: NDKEvent,
        from relay: String,
        subscriptionId: String
    ) async throws {
        // Skip ephemeral events (20000-29999)
        if EventKind.isEphemeral(event.kind) {
            NDKLogger.log(.trace, category: .cache, "MemoryCache: Skipping ephemeral event in processEvent (kind: \(event.kind)): \(event.id)")
            return
        }
        
        // Check if event was tombstoned by a deletion event
        if deletionTombstones[event.id] != nil {
            // Event was deleted before it arrived, don't save it
            NDKLogger.log(.debug, category: .cache, "Event \(event.id) was tombstoned, not saving")
            return
        }
        
        // Process deletion events (NIP-09) before saving
        if event.kind == EventKind.deletion {
            await processDeletionEvent(event)
        }
        
        // Save the event
        try await saveEvent(event)
        
        // No need to notify here since saveEvent already does it
    }
    
    /// Process a kind:5 deletion event according to NIP-09
    private func processDeletionEvent(_ deletionEvent: NDKEvent) async {
        // Extract event IDs to delete from "e" tags
        let eventIdsToDelete = deletionEvent.tags.eventIds
        
        guard !eventIdsToDelete.isEmpty else { return }
        
        let now = Date()
        
        // Process each event to be deleted
        for eventId in eventIdsToDelete {
            // Check if the event exists in cache
            if let existingEvent = events[eventId] {
                // Verify the deletion event author matches the original event author
                if existingEvent.pubkey == deletionEvent.pubkey {
                    // Delete the event from cache
                    do {
                        try await deleteEvent(id: eventId)
                        NDKLogger.log(.debug, category: .cache, "Deleted event \(eventId)")
                    } catch {
                        NDKLogger.log(.error, category: .cache, "Failed to delete event \(eventId): \(error)")
                    }
                }
            } else {
                // Event not in cache yet - add to tombstone cache
                // This prevents the event from being added if it arrives later
                deletionTombstones[eventId] = now
            }
        }
    }
    
    // MARK: - Reactive Observation
    
    public func observeEvents(
        matching filter: NDKFilter,
        observer: CacheObserver
    ) async -> ObservationHandle {
        let signature = FilterSignature(from: filter)
        let weakObserver = WeakObserver(observer: observer)
        
        // Add observer to the set for this filter signature
        if observers[signature] == nil {
            observers[signature] = []
        }
        observers[signature]?.insert(weakObserver)
        
        // Deliver existing cached events that match the filter
        let existingEvents = try? await queryEvents(filter)
        if let events = existingEvents, !events.isEmpty {
            for event in events {
                await observer.handleEvent(event)
            }
        }
        
        // Return handle that removes observer when cancelled
        return ObservationHandle { [weak self] in
            await self?.removeObserver(weakObserver, for: signature)
        }
    }
    
    private func removeObserver(_ observer: WeakObserver, for signature: FilterSignature) async {
        observers[signature]?.remove(observer)
        if observers[signature]?.isEmpty == true {
            observers.removeValue(forKey: signature)
        }
    }
    
    private func notifyObservers(of event: NDKEvent) async {
        // Clean up any nil weak references
        for (signature, observerSet) in observers {
            observers[signature] = observerSet.filter { $0.observer != nil }
        }
        
        // Find all observers whose filters match this event
        for (signature, observerSet) in observers {
            // Create filter from signature to check if event matches
            let filter = NDKFilter(
                ids: signature.ids,
                authors: signature.authors,
                kinds: signature.kinds,
                tags: signature.tags?.mapValues { Set($0) }
            )
            
            // Check if event matches this filter
            let matches = filter.matches(event: event)
            
            if matches {
                // Notify all observers for this filter
                for weakObserver in observerSet {
                    if let observer = weakObserver.observer {
                        await observer.handleEvent(event)
                    }
                }
            }
        }
    }
}