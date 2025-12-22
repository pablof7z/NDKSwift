import Foundation
import NDKSwiftCore

/// NostrDB-based cache implementation for NDKSwift
///
/// This actor provides persistent event storage using nostrdb as the backend.
/// It implements the NDKCache protocol and provides high-performance event
/// storage with native nostrdb querying capabilities.
///
/// ## Features
/// - Fast event storage and retrieval using nostrdb's C-based engine
/// - Persistent storage with LMDB backend
/// - High-performance event indexing
/// - Memory-efficient event management
/// - Native profile metadata lookup via nostrdb
/// - Full-text search across event content
/// - Relay source tracking for events
///
/// ## Implemented NDKCache Methods
/// - `saveEvent(_:)` - Stores events in nostrdb with LMDB persistence
/// - `getEvent(id:)` - Retrieves events from nostrdb by ID
/// - `queryEvents(_:)` - Basic filtering (currently in-memory, will use nostrdb native queries in future)
/// - `deleteEvent(id:)` - Removes from in-memory cache only (nostrdb events are immutable)
/// - `getProfileMetadata(pubkey:)` - Uses nostrdb's native profile lookup
/// - `textSearch(_:limit:)` - Leverages nostrdb's full-text search index
/// - `processEvent(_:from:subscriptionId:)` - Tracks relay sources via nostrdb
/// - `getRelaySources(eventId:)` - Returns relays that provided an event
/// - `observeEvents(matching:includeExisting:)` - Real-time event observation using nostrdb subscriptions
/// - `observeProfile(pubkey:includeExisting:)` - Real-time profile observation using nostrdb subscriptions
/// - `clear()` - Clears in-memory cache and unpublished events
/// - `clearPersisted()` - Clears persisted database and unpublished events
///
/// ## Implemented Optimistic Publishing
/// - `addUnpublishedEvent(_:publishedRelays:pendingRelays:)` - Tracks unpublished events with per-relay state in JSONL file
/// - `confirmEvent(eventId:onRelay:)` - Marks events as confirmed on specific relays
/// - `getEventConfirmationState(eventId:)` - Returns detailed state (which relays pending/confirmed)
/// - `getUnpublishedEvents(maxAge:limit:)` - Returns pending events (persists across app restarts)
/// - `recordPublishFailure(eventId:relay:reason:)` - Records failure reason for specific relay
/// - `removeUnpublishedEvent(eventId:)` - Removes event from tracking when threshold is met
///
/// ## Protocol Defaults Used
/// The following methods use default implementations from NDKCache protocol extensions:
/// - Decrypted content: `getDecryptedContent`, `storeDecryptedContent`, `clearDecryptedContent`
/// - Mint/wallet cache: All mint and keyset methods
/// - Negentropy: `getEventsByTimeRange`, `getEventIdsWithTimestamps`, `hasEvents`
/// - Cache freshness: `getLastFetchTime`, `recordFetchTime`
/// - NIP-05: All NIP-05 verification methods
/// - Relay preferences: `saveRelayPreferences`, `getRelayPreferences`
/// - Profile batch: `getMultipleProfileMetadata`, `saveProfileMetadata`
///
/// ## Usage
/// ```swift
/// let cache = try await NDKNostrDBCache(path: "path/to/db")
/// try await cache.saveEvent(event)
/// let event = await cache.getEvent(id: eventId)
/// let results = await cache.textSearch("bitcoin")
/// ```
public actor NDKNostrDBCache: NDKCache {
    private var nostrDB: Ndb?
    private var events: [String: NDKEvent] = [:]
    private let cachePath: String?
    private var relayCache: LRUCache<String, Bool>
    private var eventRelaySources: [String: Set<String>] = [:]

    /// Tracks event IDs that have been logically deleted.
    /// These events still exist in LMDB but should be filtered from queries.
    private var deletedEventIds: Set<String> = []

    /// Manages optimistic publishing state for unpublished events
    private var publishingManager: OptimisticPublishingManager

    /// Maximum number of relay URLs to track in the LRU cache
    private static let maxRelayCount = 100

    /// Initialize a new NostrDB cache
    /// - Parameter path: Optional path to the database directory. If nil, uses the default location.
    /// - Throws: NDKNostrDBCacheError if the database cannot be opened
    public init(path: String? = nil) async throws {
        cachePath = path
        relayCache = LRUCache<String, Bool>(capacity: Self.maxRelayCount, defaultTTL: TimeInterval.infinity)
        nostrDB = Ndb(path: path)
        publishingManager = OptimisticPublishingManager(cachePath: path)

        if nostrDB == nil {
            throw NDKNostrDBCacheError.failedToOpen
        }
    }

    // MARK: - Statistics & Developer Tools

    /// Get comprehensive statistics about the cache
    /// - Returns: NdbStat containing per-database and per-kind statistics
    public func getStats() -> NdbStat? {
        return nostrDB?.stat()
    }

    /// Get the path where the cache database is stored
    /// - Returns: The cache directory path, or nil if using default location
    public func getCachePath() -> String? {
        return cachePath ?? Ndb.db_path()
    }

    /// Get the total size of the database files on disk
    /// - Returns: Total size in bytes
    public func getDatabaseSize() -> Int64 {
        guard let path = getCachePath() else { return 0 }

        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        for file in ["data.mdb", "lock.mdb"] {
            let filePath = "\(path)/\(file)"
            let attrs: [FileAttributeKey: Any]?
            do {
                attrs = try fileManager.attributesOfItem(atPath: filePath)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to get file attributes for \(filePath): \(error.localizedDescription)")
                attrs = nil
            }
            if let attrs = attrs, let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }

        return totalSize
    }

    /// Get the count of events currently in the in-memory cache
    public var inMemoryEventCount: Int {
        return events.count
    }

    // MARK: - Event Operations

    public func saveEvent(_ event: NDKEvent) async throws {
        guard shouldCache(event: event) else { return }

        guard let nostrDB = nostrDB else {
            throw NDKNostrDBCacheError.notInitialized
        }

        // Convert NDKEvent to JSON for nostrdb processing
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NDKNostrDBCacheError.encodingFailed
        }

        // Process the event through nostrdb
        _ = nostrDB.process_event(json)
        // Note: process_event returns false for duplicates or invalid events
        // This is not necessarily an error, so we don't throw

        // Also keep in memory for queryEvents (until we implement full nostrdb queries)
        events[event.id] = event
    }

    public func getEvent(id: String) async -> NDKEvent? {
        // Filter out deleted events
        if deletedEventIds.contains(id) {
            return nil
        }

        guard let nostrDB = nostrDB else { return nil }

        // Convert hex ID to NdbNoteId
        guard let idData = hexToData(id) else { return nil }
        let noteId = NdbNoteId(idData)

        // Lookup the note from nostrdb
        guard let txn = nostrDB.lookup_note(noteId) else {
            // Fall back to in-memory cache if not in nostrdb yet
            return events[id]
        }

        let note = txn.unsafeUnownedValue
        guard let note = note else {
            return events[id]
        }

        // Convert NdbNote to NDKEvent
        return convertToNDKEvent(note)
    }

    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        guard let nostrDB = nostrDB else {
            throw NDKNostrDBCacheError.notInitialized
        }

        // Convert NDKFilter to NostrFilter for nostrdb
        let nostrFilter = convertToNostrFilter(filter)

        // Query both nostrdb and in-memory cache, then merge results
        // This ensures we get events that may not yet be indexed by nostrdb's async ingester
        var seenIds = Set<String>()
        var results: [NDKEvent] = []

        // Try native nostrdb query first
        do {
            let ndbFilter = try NdbFilter(from: nostrFilter)
            let noteKeys = try nostrDB.query(filters: [ndbFilter], maxResults: filter.limit ?? Int.max)

            // Convert note keys to NDKEvents, filtering out deleted events
            for noteKey in noteKeys {
                if let txn = nostrDB.lookup_note_by_key(noteKey),
                   let note = txn.unsafeUnownedValue,
                   let event = convertToNDKEvent(note)
                {
                    if !seenIds.contains(event.id) && !deletedEventIds.contains(event.id) {
                        seenIds.insert(event.id)
                        results.append(event)
                    }
                }
            }
        } catch {
            // Nostrdb query failed, will rely on in-memory only
            NDKLogger.log(.error, category: .cache, "NostrDB native query failed: \(error). Falling back to in-memory query.")
        }

        // Also query in-memory cache for events not yet indexed
        let inMemoryResults = queryEventsInMemory(filter)
        for event in inMemoryResults {
            if !seenIds.contains(event.id) && !deletedEventIds.contains(event.id) {
                seenIds.insert(event.id)
                results.append(event)
            }
        }

        // Sort by created_at descending (most recent first)
        results.sort { $0.createdAt > $1.createdAt }

        // Apply limit
        if let limit = filter.limit {
            return Array(results.prefix(limit))
        }

        return results
    }

    /// Fallback in-memory query when nostrdb query is unavailable
    private func queryEventsInMemory(_ filter: NDKFilter) -> [NDKEvent] {
        var results = Array(events.values)

        // Filter by IDs
        if let ids = filter.ids {
            results = results.filter { ids.contains($0.id) }
        }

        // Filter by authors
        if let authors = filter.authors {
            results = results.filter { authors.contains($0.pubkey) }
        }

        // Filter by kinds
        if let kinds = filter.kinds {
            results = results.filter { kinds.contains($0.kind) }
        }

        // Filter by timestamp
        if let since = filter.since {
            results = results.filter { $0.createdAt >= since }
        }

        if let until = filter.until {
            results = results.filter { $0.createdAt <= until }
        }

        // Sort by created_at descending (most recent first)
        results.sort { $0.createdAt > $1.createdAt }

        // Apply limit
        if let limit = filter.limit {
            results = Array(results.prefix(limit))
        }

        return results
    }

    /// Convert NDKFilter to NostrFilter for nostrdb compatibility
    private func convertToNostrFilter(_ filter: NDKFilter) -> NostrFilter {
        // Convert IDs
        let ids: [NdbNoteId]? = filter.ids?.compactMap { hexToData($0).map { NdbNoteId($0) } }

        // Convert authors
        let authors: [NdbPubkey]? = filter.authors?.compactMap { hexToData($0).map { NdbPubkey($0) } }

        // Convert kinds
        let kinds: [NostrKind]? = filter.kinds?.compactMap { NostrKind(rawValue: UInt32($0)) }

        // Convert referenced event IDs (#e tags)
        let referencedIds: [NdbNoteId]? = filter.events?.compactMap { hexToData($0).map { NdbNoteId($0) } }

        // Convert referenced pubkeys (#p tags)
        let pubkeys: [NdbPubkey]? = filter.pubkeys?.compactMap { hexToData($0).map { NdbPubkey($0) } }

        // Convert hashtags (#t tags)
        let hashtags: [String]? = filter.tagFilter("t")

        // Convert d-tag parameters (#d tags)
        let parameters: [String]? = filter.tagFilter("d")

        // Convert quotes (#q tags)
        let quotes: [NdbNoteId]? = filter.tagFilter("q")?.compactMap { hexToData($0).map { NdbNoteId($0) } }

        return NostrFilter(
            ids: ids,
            kinds: kinds,
            referenced_ids: referencedIds,
            pubkeys: pubkeys,
            since: filter.since.map { UInt64($0) },
            until: filter.until.map { UInt64($0) },
            limit: filter.limit,
            authors: authors,
            hashtag: hashtags,
            parameter: parameters,
            quotes: quotes
        )
    }

    /// Delete an event from the cache.
    /// - Parameter id: The event ID to delete
    /// - Note: NostrDB doesn't support physical deletion of events from LMDB.
    ///         Events are marked as deleted and filtered from all query results,
    ///         but they still exist in the underlying LMDB database.
    public func deleteEvent(id: String) async throws {
        // Remove from in-memory cache
        events.removeValue(forKey: id)
        // Track as deleted to filter from all queries
        deletedEventIds.insert(id)
    }

    // MARK: - Cache Management

    /// Clears only the in-memory cache, leaving the persisted LMDB database files intact.
    /// After calling this method, the database will still contain all events on disk.
    /// - Note: To fully clear the database including persisted data, use `clearPersisted()` instead.
    public func clear() async throws {
        events.removeAll()
        eventRelaySources.removeAll()
        await relayCache.clear()
        deletedEventIds.removeAll()
        try await publishingManager.clear()
    }

    /// Completely clears the database by deleting the LMDB files and reinitializing.
    /// This removes all persisted events from disk and resets the in-memory cache.
    /// After calling this method, the cache will be completely empty and ready for new data.
    /// - Throws: NDKNostrDBCacheError if the database cannot be reinitialized
    public func clearPersisted() async throws {
        // Clear in-memory state first
        events.removeAll()
        eventRelaySources.removeAll()
        await relayCache.clear()
        deletedEventIds.removeAll()
        try await publishingManager.clear()

        // Close the nostrdb connection
        nostrDB?.close()
        nostrDB = nil

        // Get the database path
        guard let dbPath = cachePath ?? Ndb.db_path() else {
            throw NDKNostrDBCacheError.failedToOpen
        }

        // Delete the LMDB files
        let fileManager = FileManager.default
        for dbFile in ["data.mdb", "lock.mdb"] {
            let filePath = "\(dbPath)/\(dbFile)"
            if fileManager.fileExists(atPath: filePath) {
                do {
                    try fileManager.removeItem(atPath: filePath)
                } catch {
                    NDKLogger.log(.warning, category: .cache, "Failed to delete \(dbFile): \(error.localizedDescription)")
                }
            }
        }

        // Reinitialize nostrdb with a fresh database
        nostrDB = Ndb(path: cachePath)
        if nostrDB == nil {
            throw NDKNostrDBCacheError.failedToOpen
        }
    }


    // MARK: - Reactive Observation

    public func observeEvents(
        matching filter: NDKFilter,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<[NDKEvent], Error> {
        guard let nostrDB = nostrDB else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NDKNostrDBCacheError.notInitialized)
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                // Note: includeExisting is handled by nostrDB.subscribe which yields
                // initial events as a batch (.events case) before live events (.event case)
                // This avoids duplicate queries and ensures proper batching.
                _ = includeExisting // Suppress unused parameter warning (always includes existing)

                // Convert NDKFilter to NostrFilter and then NdbFilter for subscription
                let nostrFilter = self.convertToNostrFilter(filter)
                do {
                    let ndbFilter = try NdbFilter(from: nostrFilter)

                    // Subscribe to new events matching the filter
                    let subscriptionStream = try nostrDB.subscribe(filters: [ndbFilter])

                    // Process incoming events from the subscription
                    for try await item in subscriptionStream {
                        switch item {
                        case .eose:
                            // EOSE just indicates initial query is done, continue listening
                            continue
                        case .event(let noteKey):
                            // Convert NoteKey to NDKEvent (single event from live subscription)
                            if let txn = nostrDB.lookup_note_by_key(noteKey),
                               let note = txn.unsafeUnownedValue,
                               let event = self.convertToNDKEvent(note)
                            {
                                continuation.yield([event])
                            }
                        case .events(let noteKeys):
                            // Convert batch of NoteKeys to NDKEvents (initial query results)
                            var events: [NDKEvent] = []
                            events.reserveCapacity(noteKeys.count)
                            for noteKey in noteKeys {
                                if let txn = nostrDB.lookup_note_by_key(noteKey),
                                   let note = txn.unsafeUnownedValue,
                                   let event = self.convertToNDKEvent(note)
                                {
                                    events.append(event)
                                }
                            }
                            if !events.isEmpty {
                                continuation.yield(events)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func observeProfile(
        pubkey: String,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        guard let nostrDB = nostrDB else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NDKNostrDBCacheError.notInitialized)
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                // Yield existing profile first if requested
                if includeExisting {
                    if let profile = await self.getProfileMetadata(pubkey: pubkey) {
                        let metadata = NDKUserMetadata(
                            pubkey: pubkey,
                            parsedMetadata: profile.metadata,
                            updatedAt: profile.updatedAt,
                            eventId: profile.eventId
                        )
                        continuation.yield(metadata)
                    }
                }

                // Subscribe to profile updates (kind 0 events for this pubkey)
                guard let pkData = self.hexToData(pubkey),
                      let kind0 = NostrKind(rawValue: 0)
                else {
                    continuation.finish()
                    return
                }

                let nostrFilter = NostrFilter(
                    ids: nil,
                    kinds: [kind0],
                    referenced_ids: nil,
                    pubkeys: nil,
                    since: nil,
                    until: nil,
                    limit: nil,
                    authors: [NdbPubkey(pkData)],
                    hashtag: nil,
                    parameter: nil,
                    quotes: nil
                )

                do {
                    let ndbFilter = try NdbFilter(from: nostrFilter)

                    // Subscribe to new profile events
                    let subscriptionStream = try nostrDB.subscribe(filters: [ndbFilter])

                    // Process incoming profile events from the subscription
                    for try await item in subscriptionStream {
                        switch item {
                        case .eose:
                            // EOSE just indicates initial query is done, continue listening
                            continue
                        case .event(let noteKey):
                            // Convert NoteKey to profile metadata
                            if let txn = nostrDB.lookup_note_by_key(noteKey),
                               let note = txn.unsafeUnownedValue
                            {
                                // Parse profile metadata from the event content
                                if let data = note.content.data(using: .utf8),
                                   let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                                {
                                    let userMetadata = NDKUserMetadata(
                                        pubkey: pubkey,
                                        parsedMetadata: metadata,
                                        updatedAt: Timestamp(note.created_at),
                                        eventId: self.dataToHex(note.id.id)
                                    )
                                    continuation.yield(userMetadata)
                                }
                            }
                        case .events:
                            // Batch events - not used in this context
                            continue
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Profile Metadata Operations

    public func getProfileMetadata(pubkey: String) async -> (metadata: [String: Any], updatedAt: Timestamp, eventId: String)? {
        guard let nostrDB = nostrDB else { return nil }

        // Convert hex pubkey to NdbPubkey
        guard let pkData = hexToData(pubkey) else { return nil }
        let ndbPubkey = NdbPubkey(pkData)

        // Lookup profile from NostrDB
        guard let txn = nostrDB.lookup_profile(ndbPubkey) else {
            // Fall back to in-memory cache
            return getProfileMetadataFromMemory(pubkey: pubkey)
        }

        guard let cachedProfile = txn.unsafeUnownedValue else {
            return getProfileMetadataFromMemory(pubkey: pubkey)
        }

        // Convert NdbProfile to metadata dictionary
        var metadata: [String: Any] = [:]
        if let name = cachedProfile.profile.name { metadata["name"] = name }
        if let displayName = cachedProfile.profile.displayName { metadata["display_name"] = displayName }
        if let about = cachedProfile.profile.about { metadata["about"] = about }
        if let picture = cachedProfile.profile.picture { metadata["picture"] = picture }
        if let banner = cachedProfile.profile.banner { metadata["banner"] = banner }
        if let website = cachedProfile.profile.website { metadata["website"] = website }
        if let nip05 = cachedProfile.profile.nip05 { metadata["nip05"] = nip05 }
        if let lud16 = cachedProfile.profile.lud16 { metadata["lud16"] = lud16 }
        if let lud06 = cachedProfile.profile.lud06 { metadata["lud06"] = lud06 }

        // Use receivedAt as the timestamp and derive event ID from note key
        let updatedAt = Timestamp(cachedProfile.receivedAt.timeIntervalSince1970)

        // We need to look up the actual note to get the event ID
        // For now, use a placeholder - this could be improved by storing note ID with profile
        let eventId = "unknown"

        return (metadata: metadata, updatedAt: updatedAt, eventId: eventId)
    }

    /// Fallback to in-memory profile lookup
    private func getProfileMetadataFromMemory(pubkey: String) -> (metadata: [String: Any], updatedAt: Timestamp, eventId: String)? {
        let kind0Events = events.values.filter { $0.kind == EventKind.metadata && $0.pubkey == pubkey }

        guard let latestEvent = kind0Events.max(by: { $0.createdAt < $1.createdAt }) else {
            return nil
        }

        // Parse metadata from JSON content
        guard let data = latestEvent.content.data(using: .utf8) else {
            return nil
        }

        let metadata: [String: Any]?
        do {
            metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            NDKLogger.log(.warning, category: .cache, "Failed to parse metadata JSON for pubkey \(pubkey): \(error.localizedDescription)")
            return nil
        }

        guard let metadata = metadata else {
            return nil
        }

        return (metadata: metadata, updatedAt: latestEvent.createdAt, eventId: latestEvent.id)
    }

    // MARK: - Text Search

    /// Perform full-text search on event content using nostrdb's native search
    /// Falls back to in-memory search for events not yet indexed by nostrdb's async ingester
    /// - Parameters:
    ///   - query: Search query string
    ///   - limit: Maximum number of results (default: 50)
    /// - Returns: Array of matching NDKEvents
    public func textSearch(_ query: String, limit: Int = 50) async -> [NDKEvent] {
        guard let nostrDB = nostrDB else { return [] }

        var results: [NDKEvent] = []

        // Use nostrdb's native text_search (fast, indexed)
        let noteKeys = nostrDB.text_search(query: query, limit: limit, order: .newest_first)
        for noteKey in noteKeys {
            if let txn = nostrDB.lookup_note_by_key(noteKey),
               let note = txn.unsafeUnownedValue,
               let event = convertToNDKEvent(note)
            {
                results.append(event)
            }
        }

        return results
    }

    // MARK: - Relay Source Tracking

    /// Process event with relay source tracking
    /// - Parameters:
    ///   - event: The event to process
    ///   - relay: The relay this event came from
    ///   - subscriptionId: The subscription that received this event
    public func processEvent(_ event: NDKEvent, from relay: String, subscriptionId _: String) async throws {
        guard shouldCache(event: event) else { return }

        guard let nostrDB = nostrDB else {
            throw NDKNostrDBCacheError.notInitialized
        }

        // Track this relay URL in LRU cache (automatically evicts least recently used)
        await relayCache.set(relay, value: true)

        // Track event-to-relay mapping in-memory (for immediate availability)
        var sources = eventRelaySources[event.id] ?? []
        sources.insert(relay)
        eventRelaySources[event.id] = sources

        // Convert NDKEvent to JSON for nostrdb processing
        let json = try event.toJSON()

        // Process with relay URL for source tracking (nostrdb also tracks this, but async)
        _ = nostrDB.process_event(json, originRelayURL: relay)

        // Also save to in-memory cache
        events[event.id] = event
    }

    /// Get relay sources for an event
    /// - Parameter eventId: The event ID to check
    /// - Returns: Set of relay URLs that have provided this event
    public func getRelaySources(eventId: String) async -> Set<String> {
        // Use in-memory tracking which is immediately available
        // NostrDB also tracks this, but it's async and may not be indexed yet
        return eventRelaySources[eventId] ?? []
    }

    // MARK: - Optimistic Publishing

    /// Add an unpublished event with target relays (protocol conformance)
    /// - Parameters:
    ///   - event: The event to track
    ///   - relays: Target relays for publishing
    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        // Save event to nostrdb first
        try await saveEvent(event)

        // Store in unpublished file with all relays as pending
        let pendingRelays = Dictionary(uniqueKeysWithValues: relays.map { ($0, "pending") })
        try await publishingManager.addUnpublishedEvent(event, publishedRelays: [], pendingRelays: pendingRelays)
    }

    /// Add an unpublished event with detailed relay state
    /// - Parameters:
    ///   - event: The event to track
    ///   - publishedRelays: Relays that have successfully published
    ///   - pendingRelays: Relays pending publication with failure reasons
    public func addUnpublishedEventWithState(_ event: NDKEvent, publishedRelays: [String], pendingRelays: [String: String]) async throws {
        // Save event to nostrdb first
        try await saveEvent(event)

        // Store in unpublished file (NDK-core already decided this needs tracking)
        try await publishingManager.addUnpublishedEvent(event, publishedRelays: publishedRelays, pendingRelays: pendingRelays)
    }

    /// Mark event as confirmed on a specific relay
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relay: The relay URL that confirmed
    public func confirmEvent(eventId: String, onRelay relay: String) async throws {
        try await publishingManager.confirmEvent(eventId: eventId, onRelay: relay)
    }

    /// Record a publish failure for a relay
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relay: The relay URL that failed
    ///   - reason: The failure reason
    public func recordPublishFailure(eventId: String, relay: String, reason: String) async throws {
        try await publishingManager.recordPublishFailure(eventId: eventId, relay: relay, reason: reason)
    }

    /// Remove an event from unpublished tracking (called by NDK-core when threshold is met)
    /// - Parameter eventId: The event ID to remove
    public func removeUnpublishedEvent(eventId: String) async throws {
        try await publishingManager.removeUnpublishedEvent(eventId: eventId)
    }

    /// Get event confirmation state
    /// - Parameter eventId: The event ID
    /// - Returns: Confirmation state with published and pending relays
    public func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return await publishingManager.getEventConfirmationState(eventId: eventId)
    }

    /// Get unpublished events that need retry
    /// - Parameters:
    ///   - maxAge: Maximum age of events to return
    ///   - limit: Optional limit on number of events
    /// - Returns: Array of events with their target relays
    public func getUnpublishedEvents(
        maxAge: TimeInterval = TimeConstants.unpublishedEventRetryWindow,
        limit: Int? = nil
    ) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        return await publishingManager.getUnpublishedEvents(maxAge: maxAge, limit: limit)
    }

    /// Get the stream of unpublished store changes for reactive updates
    /// Returns nil if unpublished store is not available
    public var unpublishedChanges: AsyncStream<UnpublishedChange>? {
        get async {
            await publishingManager.unpublishedChanges
        }
    }

    /// Get all unpublished event records with full per-relay status
    /// Returns a dictionary of eventId -> record containing publishedRelays and pendingRelays
    public func getAllUnpublishedRecords() async -> [String: UnpublishedStore.UnpublishedEventRecord] {
        return await publishingManager.getAllUnpublishedRecords()
    }

    // MARK: - Helper Methods

    /// Convert NdbNote to NDKEvent
    private func convertToNDKEvent(_ note: NdbNote) -> NDKEvent? {
        // Convert tags using built-in helper
        let tags = note.tags.strings()

        // Convert ID, pubkey, and sig to hex strings
        let id = dataToHex(note.id.id)
        let pubkey = dataToHex(note.pubkey.data)
        let sig = dataToHex(note.sig.data)

        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: Timestamp(note.created_at),
            kind: Kind(note.kind),
            tags: tags,
            content: note.content,
            sig: sig
        )
    }

    /// Convert hex string to Data
    private func hexToData(_ hex: String) -> Data? {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteString = String(hex[index ..< nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        return data.count == hex.count / 2 ? data : nil
    }

    /// Convert Data to hex string
    private func dataToHex(_ data: Data) -> String {
        // Use reduce(into:) to build the string efficiently without intermediate allocations
        data.reduce(into: "") { result, byte in
            let high = byte >> 4
            let low = byte & 0x0F
            result.append(high < 10 ? Character(UnicodeScalar(0x30 + high)) : Character(UnicodeScalar(0x61 + high - 10)))
            result.append(low < 10 ? Character(UnicodeScalar(0x30 + low)) : Character(UnicodeScalar(0x61 + low - 10)))
        }
    }

    /// Check if an event should be cached
    /// - Parameter event: The event to check
    /// - Returns: true if the event should be cached, false otherwise
    private func shouldCache(event: NDKEvent) -> Bool {
        // Skip ephemeral events (20000-29999) - they should never be persisted
        if EventKind.isEphemeral(event.kind) {
            NDKLogger.log(.trace, category: .cache, "NDKNostrDBCache: Skipping ephemeral event (kind: \(event.kind)): \(event.id)")
            return false
        }
        return true
    }

    /// Lookup and convert a note by its key
    /// - Parameter noteKey: The note key to lookup
    /// - Returns: The converted NDKEvent, or nil if not found
    private func lookupAndConvert(noteKey: NoteKey) -> NDKEvent? {
        guard let nostrDB = nostrDB,
              let txn = nostrDB.lookup_note_by_key(noteKey),
              let note = txn.unsafeUnownedValue else {
            return nil
        }
        return convertToNDKEvent(note)
    }
}

// MARK: - Error Types

/// Errors that can occur when using NDKNostrDBCache
public enum NDKNostrDBCacheError: Error {
    case failedToOpen
    case notInitialized
    case encodingFailed
}
