import Foundation

/// The primary cache protocol for NDKSwift
/// 
/// This protocol defines the caching interface that implementations must conform to.
/// The SQLite cache implementation provides the default, high-performance solution.
public protocol NDKCache: Actor {
    // MARK: - Event Operations
    
    /// Save an event to cache
    func saveEvent(_ event: NDKEvent) async throws
    
    /// Retrieve an event by ID
    func getEvent(id: String) async -> NDKEvent?
    
    /// Query events matching a filter
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent]
    
    /// Delete an event from cache
    func deleteEvent(id: String) async throws
    
    // MARK: - Profile Operations
    
    /// Save a user profile
    func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws
    
    /// Retrieve a user profile
    func getProfile(pubkey: String) async -> NDKUserProfile?
    
    // MARK: - Cache Management
    
    /// Clear all cached data
    func clear() async throws
}

// MARK: - Optional Protocol Extensions

public extension NDKCache {
    /// Check if an event exists in cache
    func hasEvent(id: String) async -> Bool {
        return await getEvent(id: id) != nil
    }
    
    /// Batch save events
    func saveEvents(_ events: [NDKEvent]) async throws {
        for event in events {
            try await saveEvent(event)
        }
    }
    
    /// Query events by author
    func queryEvents(author: String, kinds: [Int]? = nil, limit: Int? = nil) async throws -> [NDKEvent] {
        var filter = NDKFilter(authors: [author])
        filter.kinds = kinds
        filter.limit = limit
        return try await queryEvents(filter)
    }
    
    /// Query events by kind
    func queryEvents(kind: Int, limit: Int? = nil) async throws -> [NDKEvent] {
        let filter = NDKFilter(kinds: [kind], limit: limit)
        return try await queryEvents(filter)
    }
}
