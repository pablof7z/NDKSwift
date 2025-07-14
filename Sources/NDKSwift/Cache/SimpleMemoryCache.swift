import Foundation

/// Simple in-memory cache implementation for testing
public actor SimpleMemoryCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var profiles: [String: NDKUserProfile] = [:]
    private var eventConfirmations: [String: EventConfirmationState] = [:]
    private var unpublishedEventRelays: [String: Set<String>] = [:]
    private var eventCreationTimes: [String: Date] = [:]
    private var decryptedContent: LRUCache<String, String>
    
    public init() {
        // Initialize LRU cache with 1000 item limit
        self.decryptedContent = LRUCache(capacity: 1000)
    }
    
    // MARK: - Event Operations
    
    public func saveEvent(_ event: NDKEvent) async throws {
        let eventId = event.id
        events[eventId] = event
        print("[SimpleMemoryCache] Saved event \(eventId)")
    }
    
    public func getEvent(id: String) async -> NDKEvent? {
        let event = events[id]
        print("[SimpleMemoryCache] Retrieved event \(id): \(event != nil ? "found" : "not found")")
        return event
    }
    
    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        var results: [NDKEvent] = []
        
        for event in events.values {
            if await filter.matches(event: event) {
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
        
        print("[SimpleMemoryCache] Query returned \(results.count) events")
        return results
    }
    
    public func deleteEvent(id: String) async throws {
        events.removeValue(forKey: id)
        print("[SimpleMemoryCache] Deleted event \(id)")
    }
    
    // MARK: - Profile Operations
    
    public func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        profiles[pubkey] = profile
        print("[SimpleMemoryCache] Saved profile for \(pubkey)")
    }
    
    public func getProfile(pubkey: String) async -> NDKUserProfile? {
        let profile = profiles[pubkey]
        print("[SimpleMemoryCache] Retrieved profile for \(pubkey): \(profile != nil ? "found" : "not found")")
        return profile
    }
    
    // MARK: - Cache Management
    
    public func clear() async throws {
        events.removeAll()
        profiles.removeAll()
        eventConfirmations.removeAll()
        await decryptedContent.clear()
        print("[SimpleMemoryCache] Cleared all cache data")
    }
    
    // MARK: - Optimistic Publishing Support
    
    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        let eventId = event.id
        events[eventId] = event
        eventConfirmations[eventId] = .optimistic
        unpublishedEventRelays[eventId] = relays
        eventCreationTimes[eventId] = Date()
        print("[SimpleMemoryCache] Added unpublished event \(eventId) for relays: \(relays.joined(separator: ", "))")
    }
    
    public func confirmEvent(eventId: String, onRelay relay: String) async throws {
        if let existingState = eventConfirmations[eventId] {
            switch existingState {
            case .optimistic:
                eventConfirmations[eventId] = .confirmed(fromRelay: relay)
                print("[SimpleMemoryCache] Confirmed event \(eventId) on relay \(relay)")
            case .confirmed:
                print("[SimpleMemoryCache] Event \(eventId) already confirmed")
            }
        } else {
            // Event not found, might have been confirmed directly
            eventConfirmations[eventId] = .confirmed(fromRelay: relay)
            print("[SimpleMemoryCache] Marked event \(eventId) as confirmed on relay \(relay)")
        }
    }
    
    public func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return eventConfirmations[eventId]
    }
    
    public func getUnpublishedEvents(maxAge: TimeInterval = 3600, limit: Int? = nil) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
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
        
        print("[SimpleMemoryCache] Found \(results.count) unpublished events (maxAge: \(maxAge)s)")
        return results
    }
    
    // MARK: - Decrypted Content Cache
    
    public func getDecryptedContent(for eventId: String) async -> String? {
        return await decryptedContent.get(eventId)
    }
    
    public func storeDecryptedContent(_ content: String, for eventId: String) async {
        await decryptedContent.set(eventId, value: content)
        print("[SimpleMemoryCache] Cached decrypted content for event \(eventId)")
    }
    
    public func clearDecryptedContent() async {
        await decryptedContent.clear()
        print("[SimpleMemoryCache] Cleared all decrypted content")
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
}