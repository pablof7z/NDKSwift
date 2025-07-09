import Foundation

/// Simple in-memory cache implementation for testing
public actor SimpleMemoryCache: NDKCache {
    private var events: [String: NDKEvent] = [:]
    private var profiles: [String: NDKUserProfile] = [:]
    
    public init() {}
    
    // MARK: - Event Operations
    
    public func saveEvent(_ event: NDKEvent) async throws {
        guard let eventId = event.id else {
            throw NDKError.invalidEventID("Event has no ID")
        }
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
            if filter.matches(event: event) {
                results.append(event)
            }
        }
        
        // Apply limit if specified
        if let limit = filter.limit, limit > 0 {
            results = Array(results.prefix(limit))
        }
        
        // Sort by created_at descending
        results.sort { $0.createdAt > $1.createdAt }
        
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
        print("[SimpleMemoryCache] Cleared all cache data")
    }
    
    // MARK: - Debug Helpers
    
    public func eventCount() async -> Int {
        return events.count
    }
    
    public func profileCount() async -> Int {
        return profiles.count
    }
}