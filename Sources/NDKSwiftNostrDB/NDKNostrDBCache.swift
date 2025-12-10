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
/// - `observeEvents(matching:includeExisting:)` - Returns existing events only (subscription support planned)
/// - `observeProfile(pubkey:includeExisting:)` - Returns existing profile only (subscription support planned)
/// - `clear()` - Clears in-memory cache only (nostrdb files persist)
///
/// ## Protocol Defaults Used
/// The following methods use default implementations from NDKCache protocol extensions:
/// - Optimistic publishing: `addUnpublishedEvent`, `confirmEvent`, `getEventConfirmationState`, `getUnpublishedEvents`
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
    private var ndb: Ndb?
    private var events: [String: NDKEvent] = [:]
    private let cachePath: String?

    /// Initialize a new NostrDB cache
    /// - Parameter path: Optional path to the database directory. If nil, uses the default location.
    /// - Throws: NDKNostrDBCacheError if the database cannot be opened
    public init(path: String? = nil) async throws {
        self.cachePath = path
        self.ndb = Ndb(path: path)
        if self.ndb == nil {
            throw NDKNostrDBCacheError.failedToOpen
        }
    }

    // MARK: - Statistics & Developer Tools

    /// Get comprehensive statistics about the cache
    /// - Returns: NdbStat containing per-database and per-kind statistics
    public func getStats() -> NdbStat? {
        return ndb?.stat()
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
        guard let ndb = ndb else {
            throw NDKNostrDBCacheError.notInitialized
        }

        // Convert NDKEvent to JSON for nostrdb processing
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NDKNostrDBCacheError.encodingFailed
        }

        // Process the event through nostrdb
        _ = ndb.process_event(json)
        // Note: process_event returns false for duplicates or invalid events
        // This is not necessarily an error, so we don't throw

        // Also keep in memory for queryEvents (until we implement full nostrdb queries)
        events[event.id] = event
    }

    public func getEvent(id: String) async -> NDKEvent? {
        guard let ndb = ndb else { return nil }

        // Convert hex ID to NdbNoteId
        guard let idData = hexToData(id) else { return nil }
        let noteId = NdbNoteId(idData)

        // Lookup the note from nostrdb
        guard let txn = ndb.lookup_note(noteId) else {
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
        guard let ndb = ndb else {
            throw NDKNostrDBCacheError.notInitialized
        }

        // Convert NDKFilter to NostrFilter for nostrdb
        let nostrFilter = convertToNostrFilter(filter)

        // Try native nostrdb query first
        do {
            let ndbFilter = try NdbFilter(from: nostrFilter)
            let noteKeys = try ndb.query(filters: [ndbFilter], maxResults: filter.limit ?? 500)

            // Convert note keys to NDKEvents
            var results: [NDKEvent] = []
            results.reserveCapacity(noteKeys.count)

            for noteKey in noteKeys {
                if let txn = ndb.lookup_note_by_key(noteKey),
                   let note = txn.unsafeUnownedValue,
                   let event = convertToNDKEvent(note) {
                    results.append(event)
                }
            }

            // Sort by created_at descending (most recent first)
            results.sort { $0.createdAt > $1.createdAt }

            return results
        } catch {
            // Fall back to in-memory filtering if nostrdb query fails
            return queryEventsInMemory(filter)
        }
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

    public func deleteEvent(id: String) async throws {
        // Note: NostrDB doesn't support deletion of individual events
        // Events are immutable once stored in LMDB
        // We only remove from in-memory cache
        events.removeValue(forKey: id)
    }

    // MARK: - Cache Management

    public func clear() async throws {
        // Note: NostrDB doesn't provide a clear/reset API
        // To clear the database, you would need to delete the LMDB files
        // We can only clear the in-memory cache
        events.removeAll()
    }

    // MARK: - Reactive Observation

    public func observeEvents(
        matching filter: NDKFilter,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<[NDKEvent], Error> {
        guard let ndb = ndb else {
            return AsyncThrowingStream { $0.finish(throwing: NDKNostrDBCacheError.notInitialized) }
        }

        // Convert NDKFilter to NdbFilter for subscription
        let nostrFilter = convertToNostrFilter(filter)

        do {
            let ndbFilter = try NdbFilter(from: nostrFilter)

            // Use nostrdb's native subscription which handles:
            // 1. Subscribe first (to not miss events)
            // 2. Query existing
            // 3. Stream: existing → EOSE → new events
            let stream = try ndb.subscribe(filters: [ndbFilter], maxSimultaneousResults: filter.limit ?? 500)

            return AsyncThrowingStream { continuation in
                Task {
                    var batch: [NDKEvent] = []
                    var seenEOSE = false

                    for await item in stream {
                        switch item {
                        case .event(let noteKey):
                            // Convert NoteKey to NDKEvent
                            if let txn = ndb.lookup_note_by_key(noteKey),
                               let note = txn.unsafeUnownedValue,
                               let event = self.convertToNDKEvent(note) {

                                if !seenEOSE {
                                    // Before EOSE: batch existing events
                                    if includeExisting {
                                        batch.append(event)
                                    }
                                } else {
                                    // After EOSE: yield new events immediately
                                    continuation.yield([event])
                                }
                            }

                        case .eose:
                            seenEOSE = true
                            // Yield the batch of existing events
                            if includeExisting && !batch.isEmpty {
                                continuation.yield(batch)
                                batch = []
                            }
                        }
                    }

                    continuation.finish()
                }
            }
        } catch {
            // Fall back to one-shot query if subscription fails
            return AsyncThrowingStream { continuation in
                Task {
                    if includeExisting {
                        do {
                            let existing = try await self.queryEvents(filter)
                            if !existing.isEmpty {
                                continuation.yield(existing)
                            }
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    continuation.finish()
                }
            }
        }
    }

    public func observeProfile(
        pubkey: String,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        guard let ndb = ndb else {
            return AsyncThrowingStream { $0.finish(throwing: NDKNostrDBCacheError.notInitialized) }
        }

        // Create a filter for kind 0 (metadata) events from this pubkey
        guard let pkData = hexToData(pubkey) else {
            return AsyncThrowingStream { continuation in
                Task {
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
                    continuation.finish()
                }
            }
        }

        let nostrFilter = NostrFilter(
            kinds: [NostrKind(rawValue: 0)!],
            authors: [NdbPubkey(pkData)]
        )

        do {
            let ndbFilter = try NdbFilter(from: nostrFilter)
            let stream = try ndb.subscribe(filters: [ndbFilter], maxSimultaneousResults: 10)

            return AsyncThrowingStream { continuation in
                Task {
                    var latestMetadata: NDKUserMetadata? = nil
                    var seenEOSE = false

                    for await item in stream {
                        switch item {
                        case .event(let noteKey):
                            if let txn = ndb.lookup_note_by_key(noteKey),
                               let note = txn.unsafeUnownedValue,
                               let event = self.convertToNDKEvent(note) {

                                // Parse metadata from event content
                                if let data = event.content.data(using: .utf8) {
                                    let parsedMetadata: [String: Any]?
                                    do {
                                        parsedMetadata = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                                    } catch {
                                        NDKLogger.log(.warning, category: .cache, "Failed to parse metadata JSON for pubkey \(pubkey): \(error.localizedDescription)")
                                        parsedMetadata = nil
                                    }

                                    if let parsedMetadata = parsedMetadata {
                                        let metadata = NDKUserMetadata(
                                            pubkey: pubkey,
                                            parsedMetadata: parsedMetadata,
                                            updatedAt: event.createdAt,
                                            eventId: event.id
                                        )

                                        if !seenEOSE {
                                            // Before EOSE: track latest (by timestamp)
                                            if latestMetadata == nil || event.createdAt > (latestMetadata?.updatedAt ?? 0) {
                                                latestMetadata = metadata
                                            }
                                        } else {
                                            // After EOSE: yield new profiles immediately
                                            continuation.yield(metadata)
                                        }
                                    }
                                }
                            }

                        case .eose:
                            seenEOSE = true
                            if includeExisting, let metadata = latestMetadata {
                                continuation.yield(metadata)
                            }
                        }
                    }

                    continuation.finish()
                }
            }
        } catch {
            // Fall back to one-shot lookup
            return AsyncThrowingStream { continuation in
                Task {
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
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Profile Metadata Operations

    public func getProfileMetadata(pubkey: String) async -> (metadata: [String: Any], updatedAt: Timestamp, eventId: String)? {
        guard let ndb = ndb else { return nil }

        // Convert hex pubkey to NdbPubkey
        guard let pkData = hexToData(pubkey) else { return nil }
        let ndbPubkey = NdbPubkey(pkData)

        // Lookup profile from NostrDB
        guard let txn = ndb.lookup_profile(ndbPubkey) else {
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
    /// - Parameters:
    ///   - query: Search query string
    ///   - limit: Maximum number of results (default: 50)
    /// - Returns: Array of matching NDKEvents
    public func textSearch(_ query: String, limit: Int = 50) async -> [NDKEvent] {
        guard let ndb = ndb else { return [] }

        // Use nostrdb's text_search to get matching note keys
        let noteKeys = ndb.text_search(query: query, limit: limit, order: .newest_first)

        // Convert note keys to NDKEvents
        var results: [NDKEvent] = []
        for noteKey in noteKeys {
            if let txn = ndb.lookup_note_by_key(noteKey),
               let note = txn.unsafeUnownedValue,
               let event = convertToNDKEvent(note) {
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
    public func processEvent(_ event: NDKEvent, from relay: String, subscriptionId: String) async throws {
        guard let ndb = ndb else {
            throw NDKNostrDBCacheError.notInitialized
        }

        // Convert NDKEvent to JSON for nostrdb processing
        let json = try event.toJSON()

        // Process with relay URL for source tracking
        _ = ndb.process_event(json, originRelayURL: relay)

        // Also save to in-memory cache
        events[event.id] = event

        // Note: NostrDB automatically tracks which relays have sent each event
        // This can be queried later with ndb.was(noteKey:seenOn:)
    }

    /// Get relay sources for an event
    /// - Parameter eventId: The event ID to check
    /// - Returns: Set of relay URLs that have provided this event
    public func getRelaySources(eventId: String) async -> Set<String> {
        guard let ndb = ndb else { return [] }

        // Convert hex ID to NdbNoteId
        guard let idData = hexToData(eventId) else { return [] }
        let noteId = NdbNoteId(idData)

        // Check if the note exists in nostrdb
        guard ndb.lookup_note_key(noteId) != nil else { return [] }

        // Note: NostrDB stores relay sources, but we'd need to enumerate all relays
        // to check which ones have seen this event. For now, return empty set.
        // This could be improved by tracking relay URLs separately or using
        // ndb.was(noteKey:seenOn:) with a list of known relays.
        return []
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
            let byteString = String(hex[index..<nextIndex])
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
        return data.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Error Types

/// Errors that can occur when using NDKNostrDBCache
public enum NDKNostrDBCacheError: Error {
    case failedToOpen
    case notInitialized
    case encodingFailed
}
