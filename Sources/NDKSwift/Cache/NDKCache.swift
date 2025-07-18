import Foundation
import CashuSwift

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
    
    // MARK: - Decrypted Content Cache
    
    /// Retrieve decrypted content for an event and viewer
    /// - Parameters:
    ///   - eventId: The event ID to look up
    ///   - viewerPubkey: The public key of the viewer who decrypted this content
    /// - Returns: The decrypted content string, or nil if not cached
    func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String?
    
    /// Store decrypted content for an event and viewer
    /// - Parameters:
    ///   - content: The decrypted content to cache
    ///   - eventId: The event ID to associate with
    ///   - viewerPubkey: The public key of the viewer who decrypted this content
    func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async
    
    /// Clear all decrypted content from cache
    func clearDecryptedContent() async
    
    /// Clear decrypted content for a specific viewer
    /// - Parameter viewerPubkey: The public key of the viewer whose content should be cleared
    func clearDecryptedContent(for viewerPubkey: String) async
    
    // MARK: - Mint Cache Operations
    
    /// Save mint info to cache
    func saveMintInfo(_ info: NDKMintInfo, url: String) async throws
    
    /// Get mint info from cache
    func getMintInfo(url: String) async -> NDKMintInfo?
    
    /// Check if mint info needs refresh
    func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool
    
    /// Invalidate mint cache (forces refresh on next load)
    func invalidateMintCache(url: String) async throws
    
    /// Save keyset to cache
    func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws
    
    /// Save multiple keysets at once
    func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws
    
    /// Get keyset by ID
    func getKeyset(id: String) async -> CashuSwift.Keyset?
    
    /// Get all keysets for a mint
    func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset]
    
    /// Get active keysets for a mint and unit
    func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset]
    
    /// Check if keysets need refresh
    func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool
    
    // MARK: - Negentropy Support
    
    /// Get events in a timestamp range for Negentropy reconciliation
    /// - Parameters:
    ///   - from: Start timestamp (inclusive)
    ///   - to: End timestamp (exclusive)
    ///   - filter: Optional filter to apply (e.g., by author or kind)
    /// - Returns: Array of events in the range
    func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent]
    
    /// Get event IDs and timestamps for efficient fingerprinting
    /// - Parameters:
    ///   - from: Start timestamp (inclusive)
    ///   - to: End timestamp (exclusive)
    ///   - filter: Optional filter to apply
    /// - Returns: Array of tuples containing event ID and timestamp
    func getEventIdsWithTimestamps(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [(id: String, timestamp: Timestamp)]
    
    /// Batch check which events exist in cache
    /// - Parameter ids: Array of event IDs to check
    /// - Returns: Dictionary mapping event ID to existence boolean
    func hasEvents(ids: [String]) async -> [String: Bool]
    
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
    
    // MARK: - Default Decrypted Content Implementation
    
    /// Default implementation that returns nil (no caching)
    func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        return nil
    }
    
    /// Default implementation that does nothing (no caching)
    func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        // Default implementation - cache implementations can override for actual caching
    }
    
    /// Default implementation that does nothing
    func clearDecryptedContent() async {
        // Default implementation - cache implementations can override
    }
    
    /// Default implementation that does nothing
    func clearDecryptedContent(for viewerPubkey: String) async {
        // Default implementation - cache implementations can override
    }
    
    // MARK: - Default Mint Cache Implementation
    
    /// Default implementation that throws not implemented
    func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        // Default implementation - cache implementations should override
    }
    
    /// Default implementation that returns nil
    func getMintInfo(url: String) async -> NDKMintInfo? {
        return nil
    }
    
    /// Default implementation that returns true (always stale)
    func isMintInfoStale(url: String, maxAge: TimeInterval) async -> Bool {
        return true
    }
    
    /// Default implementation that does nothing
    func invalidateMintCache(url: String) async throws {
        // Default implementation - cache implementations should override
    }
    
    /// Default implementation that throws not implemented
    func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        // Default implementation - cache implementations should override
    }
    
    /// Default implementation that throws not implemented
    func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        // Default implementation - cache implementations should override
    }
    
    /// Default implementation that returns nil
    func getKeyset(id: String) async -> CashuSwift.Keyset? {
        return nil
    }
    
    /// Default implementation that returns empty array
    func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        return []
    }
    
    /// Default implementation that returns empty array
    func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] {
        return []
    }
    
    /// Default implementation that returns true (always stale)
    func areKeysetsStale(mintUrl: String, maxAge: TimeInterval) async -> Bool {
        return true
    }
    
    // MARK: - Default Negentropy Implementation
    
    /// Default implementation using queryEvents
    func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        var rangeFilter = filter ?? NDKFilter()
        rangeFilter.since = from
        rangeFilter.until = to
        return try await queryEvents(rangeFilter)
    }
    
    /// Default implementation that fetches full events
    func getEventIdsWithTimestamps(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [(id: String, timestamp: Timestamp)] {
        let events = try await getEventsByTimeRange(from: from, to: to, filter: filter)
        return events.map { (id: $0.id, timestamp: $0.createdAt) }
    }
    
    /// Default implementation that checks each event individually
    func hasEvents(ids: [String]) async -> [String: Bool] {
        var result: [String: Bool] = [:]
        for id in ids {
            result[id] = await hasEvent(id: id)
        }
        return result
    }
}
