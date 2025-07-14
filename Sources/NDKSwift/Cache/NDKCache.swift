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
    
    // MARK: - Optimistic Publishing Support
    
    /// Add an unpublished event to cache for optimistic publishing
    /// - Parameters:
    ///   - event: The event to cache
    ///   - relays: Target relays for this event
    func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws
    
    /// Confirm an event was published to a relay
    /// - Parameters:
    ///   - eventId: The event ID to confirm
    ///   - relay: The relay that confirmed the event
    func confirmEvent(eventId: String, onRelay relay: String) async throws
    
    /// Get the confirmation state of an event
    /// - Parameter eventId: The event ID to check
    /// - Returns: The confirmation state, or nil if not found
    func getEventConfirmationState(eventId: String) async -> EventConfirmationState?
    
    /// Query for unpublished events (optimistic events not yet confirmed)
    /// - Parameters:
    ///   - maxAge: Maximum age of events to include (default: 1 hour)
    ///   - limit: Maximum number of events to return
    /// - Returns: Array of unpublished events with their target relays
    func getUnpublishedEvents(maxAge: TimeInterval, limit: Int?) async -> [(event: NDKEvent, targetRelays: Set<String>)]
    
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
    
    // MARK: - Default Optimistic Publishing Implementation
    
    /// Default implementation that simply stores the event normally
    func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        try await saveEvent(event)
    }
    
    /// Default implementation that does nothing
    func confirmEvent(eventId: String, onRelay relay: String) async throws {
        // Default implementation - cache implementations can override for richer behavior
    }
    
    /// Default implementation that returns nil
    func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return nil
    }
    
    /// Default implementation that returns empty array
    func getUnpublishedEvents(maxAge: TimeInterval = 3600, limit: Int? = nil) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        return []
    }
}
