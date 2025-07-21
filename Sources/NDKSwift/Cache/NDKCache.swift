import Foundation
import CashuSwift

// MARK: - NIP-05 Cache Types

/// Verification status for NIP-05 identifiers
public enum NIP05VerificationStatus: String, Codable, Sendable {
    /// Claimed in kind:0 but not yet verified
    case unverified
    /// Verified and matches the claiming pubkey
    case verified
    /// Verified but belongs to a different pubkey
    case invalid
    /// Was verified but needs re-verification
    case expired
    /// Verification attempt failed (network/DNS error)
    case failed
}

/// Cache entry for NIP-05 identifiers
public struct NIP05CacheEntry: Codable, Sendable, Equatable {
    /// The full NIP-05 identifier (e.g., "satoshi@bitcoin.org")
    public let identifier: String
    /// The public key associated with this identifier
    public let pubkey: String
    /// Current verification status
    public var status: NIP05VerificationStatus
    /// Optional NIP-46 relay URLs from verification
    public var nip46Relays: [String]?
    /// When this identifier was first seen
    public let claimedAt: Date
    /// When last successfully verified
    public var verifiedAt: Date?
    /// When last verification was attempted
    public var lastCheckAt: Date?
    /// Error message if verification failed
    public var errorMessage: String?
    /// HTTP status code from last verification attempt
    public var httpStatusCode: Int?
    
    public init(
        identifier: String,
        pubkey: String,
        status: NIP05VerificationStatus,
        nip46Relays: [String]? = nil,
        claimedAt: Date = Date(),
        verifiedAt: Date? = nil,
        lastCheckAt: Date? = nil,
        errorMessage: String? = nil,
        httpStatusCode: Int? = nil
    ) {
        self.identifier = identifier
        self.pubkey = pubkey
        self.status = status
        self.nip46Relays = nip46Relays
        self.claimedAt = claimedAt
        self.verifiedAt = verifiedAt
        self.lastCheckAt = lastCheckAt
        self.errorMessage = errorMessage
        self.httpStatusCode = httpStatusCode
    }
}

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
    
    // MARK: - Reactive Observation
    
    /// Observe events matching a filter
    /// - Parameters:
    ///   - filter: The filter to match events against
    ///   - observer: The observer to notify of matching events
    /// - Returns: An observation handle to manage the observation lifecycle
    func observeEvents(
        matching filter: NDKFilter,
        observer: CacheObserver
    ) async -> ObservationHandle
    
    /// Process incoming event from relay
    /// - Parameters:
    ///   - event: The event to process
    ///   - relay: The relay this event came from
    ///   - subscriptionId: The subscription that received this event
    func processEvent(
        _ event: NDKEvent,
        from relay: String,
        subscriptionId: String
    ) async throws
    
    /// Get relay sources for an event
    /// - Parameter eventId: The event ID to check
    /// - Returns: Set of relay URLs that have provided this event
    func getRelaySources(eventId: String) async -> Set<String>
    
    // MARK: - Cache Freshness Tracking
    
    /// Get the timestamp when events matching a filter were last fetched
    /// - Parameter filter: The filter to check
    /// - Returns: The date when this filter was last queried, or nil if never
    func getLastFetchTime(for filter: NDKFilter) async -> Date?
    
    /// Record that a filter was just queried
    /// - Parameters:
    ///   - filter: The filter that was queried
    ///   - timestamp: When the query occurred (defaults to now)
    func recordFetchTime(for filter: NDKFilter, timestamp: Date) async
    
    // MARK: - NIP-05 Caching Operations
    
    /// Save an unverified NIP-05 claim found in a kind:0 event
    /// - Parameters:
    ///   - identifier: The NIP-05 identifier (e.g., "satoshi@bitcoin.org")
    ///   - pubkey: The public key claiming this identifier
    ///   - retrievedAt: When this claim was observed
    func saveNIP05Claim(_ identifier: String, pubkey: String, retrievedAt: Date) async throws
    
    /// Get a NIP-05 cache entry by identifier
    /// - Parameter identifier: The NIP-05 identifier to lookup
    /// - Returns: The cache entry if found, nil otherwise
    func getNIP05Entry(_ identifier: String) async -> NIP05CacheEntry?
    
    /// Get all NIP-05 entries for a given pubkey
    /// - Parameter pubkey: The public key to search for
    /// - Returns: Array of NIP-05 entries claimed by this pubkey
    func getNIP05Entries(pubkey: String) async -> [NIP05CacheEntry]
    
    /// Search for NIP-05 identifiers matching a prefix (for autocomplete)
    /// - Parameters:
    ///   - prefix: The search prefix
    ///   - limit: Maximum number of results
    /// - Returns: Array of matching NIP-05 entries
    func searchNIP05(_ prefix: String, limit: Int) async -> [NIP05CacheEntry]
    
    /// Save a verified NIP-05 resolution result
    /// - Parameter entry: The complete NIP-05 cache entry with verification status
    func saveNIP05Resolution(_ entry: NIP05CacheEntry) async throws
    
    /// Mark a NIP-05 entry as invalid
    /// - Parameters:
    ///   - identifier: The NIP-05 identifier
    ///   - actualPubkey: The actual pubkey that owns this identifier (if known)
    func invalidateNIP05(_ identifier: String, actualPubkey: String?) async throws
    
    /// Check if a NIP-05 entry needs verification
    /// - Parameters:
    ///   - identifier: The NIP-05 identifier
    ///   - maxAge: Maximum age before re-verification is needed
    /// - Returns: True if verification is needed
    func needsNIP05Verification(_ identifier: String, maxAge: TimeInterval) async -> Bool
    
    /// Get unverified NIP-05 entries for background verification
    /// - Parameter limit: Maximum number of entries to return
    /// - Returns: Array of unverified NIP-05 entries
    func getUnverifiedNIP05s(limit: Int) async -> [NIP05CacheEntry]
    
    /// Check if we can verify a domain (rate limiting)
    /// - Parameter domain: The domain to check
    /// - Returns: True if verification is allowed
    func canVerifyDomain(_ domain: String) async -> Bool
    
    /// Record a domain verification attempt (for rate limiting)
    /// - Parameter domain: The domain that was attempted
    func recordDomainVerificationAttempt(_ domain: String) async
    
    // MARK: - Relay Preferences Cache
    
    /// Save relay preferences with EOSE tracking
    /// - Parameters:
    ///   - pubkey: The public key
    ///   - writeRelays: Write relay URLs (nil if no relay list)
    ///   - readRelays: Read relay URLs (nil if no relay list)
    ///   - fetchedAt: When this was fetched
    ///   - expiresAt: When this cache entry expires
    ///   - checkedRelays: Which relays sent EOSE (for negative entries)
    func saveRelayPreferences(
        pubkey: String,
        writeRelays: [String]?,
        readRelays: [String]?,
        fetchedAt: Date,
        expiresAt: Date,
        checkedRelays: Set<String>?
    ) async throws
    
    /// Get cached relay preferences
    /// - Parameter pubkey: The public key to look up
    /// - Returns: Tuple with relay preferences and metadata, or nil if not found/expired
    func getRelayPreferences(
        pubkey: String
    ) async -> (writeRelays: [String]?, readRelays: [String]?, fetchedAt: Date, expiresAt: Date, checkedRelays: Set<String>?)?
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
    
    // MARK: - Default Reactive Observation Implementation
    
    /// Default implementation that returns a no-op handle
    func observeEvents(
        matching filter: NDKFilter,
        observer: CacheObserver
    ) async -> ObservationHandle {
        // Default implementation - cache implementations should override
        return ObservationHandle { /* no-op */ }
    }
    
    /// Default implementation that just saves the event
    func processEvent(
        _ event: NDKEvent,
        from relay: String,
        subscriptionId: String
    ) async throws {
        // Default implementation - just save the event
        try await saveEvent(event)
    }
    
    /// Default implementation that returns empty set
    func getRelaySources(eventId: String) async -> Set<String> {
        // Default implementation - cache implementations should override
        return []
    }
    
    // MARK: - Default Cache Freshness Implementation
    
    /// Default implementation that returns nil (no tracking)
    func getLastFetchTime(for filter: NDKFilter) async -> Date? {
        // Default implementation - cache implementations should override
        return nil
    }
    
    /// Default implementation that does nothing
    func recordFetchTime(for filter: NDKFilter, timestamp: Date = Date()) async {
        // Default implementation - cache implementations should override
    }
    
    // MARK: - Default NIP-05 Implementation
    
    /// Default implementation that does nothing
    func saveNIP05Claim(_ identifier: String, pubkey: String, retrievedAt: Date = Date()) async throws {
        // Default implementation - cache implementations should override
    }
    
    /// Default implementation that returns nil
    func getNIP05Entry(_ identifier: String) async -> NIP05CacheEntry? {
        // Default implementation - cache implementations should override
        return nil
    }
    
    /// Default implementation that returns empty array
    func getNIP05Entries(pubkey: String) async -> [NIP05CacheEntry] {
        // Default implementation - cache implementations should override
        return []
    }
    
    /// Default implementation that returns empty array
    func searchNIP05(_ prefix: String, limit: Int) async -> [NIP05CacheEntry] {
        // Default implementation - cache implementations should override
        return []
    }
    
    /// Default implementation that does nothing
    func saveNIP05Resolution(_ entry: NIP05CacheEntry) async throws {
        // Default implementation - cache implementations should override
    }
    
    /// Default implementation that does nothing
    func invalidateNIP05(_ identifier: String, actualPubkey: String?) async throws {
        // Default implementation - cache implementations should override
    }
    
    /// Default implementation that always returns true (needs verification)
    func needsNIP05Verification(_ identifier: String, maxAge: TimeInterval) async -> Bool {
        // Default implementation - cache implementations should override
        return true
    }
    
    /// Default implementation that returns empty array
    func getUnverifiedNIP05s(limit: Int) async -> [NIP05CacheEntry] {
        // Default implementation - cache implementations should override
        return []
    }
    
    /// Default implementation that always returns true (allow verification)
    func canVerifyDomain(_ domain: String) async -> Bool {
        // Default implementation - cache implementations should override
        return true
    }
    
    /// Default implementation that does nothing
    func recordDomainVerificationAttempt(_ domain: String) async {
        // Default implementation - cache implementations should override
    }
    
    // MARK: - Default Relay Preferences Implementation
    
    /// Default implementation that does nothing
    func saveRelayPreferences(
        pubkey: String,
        writeRelays: [String]?,
        readRelays: [String]?,
        fetchedAt: Date,
        expiresAt: Date,
        checkedRelays: Set<String>?
    ) async throws {
        // Default implementation - cache implementations should override
    }
    
    /// Default implementation that returns nil
    func getRelayPreferences(
        pubkey: String
    ) async -> (writeRelays: [String]?, readRelays: [String]?, fetchedAt: Date, expiresAt: Date, checkedRelays: Set<String>?)? {
        // Default implementation - cache implementations should override
        return nil
    }
}
