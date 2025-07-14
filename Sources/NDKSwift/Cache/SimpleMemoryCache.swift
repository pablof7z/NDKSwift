import Foundation

/// Simple in-memory cache implementation for testing
public actor SimpleMemoryCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var profiles: [String: NDKUserProfile] = [:]
    private var eventConfirmations: [String: EventConfirmationState] = [:]
    
    public init() {}
    
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
        print("[SimpleMemoryCache] Cleared all cache data")
    }
    
    // MARK: - Optimistic Publishing Support
    
    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        let eventId = event.id
        events[eventId] = event
        eventConfirmations[eventId] = .optimistic
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