import Foundation


/// Configuration for NDKNostrDBCache memory and disk limits
public struct NDKCacheConfig: Sendable {
    /// Maximum number of events to keep in the in-memory cache (default: 10,000)
    public var maxMemoryEvents: Int

    /// Maximum disk size in megabytes for the LMDB database (default: 500MB)
    public var maxDiskSizeMB: Int

    /// Number of days to retain events before pruning (default: 30 days)
    public var eventRetentionDays: Int

    /// Whether to automatically enforce limits in background (default: true)
    public var autoEnforceLimits: Bool

    /// Interval for background limit enforcement in seconds (default: 300 = 5 minutes)
    public var enforcementIntervalSeconds: TimeInterval

    /// Default cache configuration with sensible defaults
    public static let `default` = NDKCacheConfig()

    /// Create a cache configuration with custom values
    /// - Parameters:
    ///   - maxMemoryEvents: Maximum events in memory (default: 10,000)
    ///   - maxDiskSizeMB: Maximum disk size in MB (default: 500)
    ///   - eventRetentionDays: Days to retain events (default: 30)
    ///   - autoEnforceLimits: Auto-enforce limits in background (default: true)
    ///   - enforcementIntervalSeconds: Interval for enforcement (default: 300)
    public init(
        maxMemoryEvents: Int = 10_000,
        maxDiskSizeMB: Int = 500,
        eventRetentionDays: Int = 30,
        autoEnforceLimits: Bool = true,
        enforcementIntervalSeconds: TimeInterval = 300
    ) {
        self.maxMemoryEvents = maxMemoryEvents
        self.maxDiskSizeMB = maxDiskSizeMB
        self.eventRetentionDays = eventRetentionDays
        self.autoEnforceLimits = autoEnforceLimits
        self.enforcementIntervalSeconds = enforcementIntervalSeconds
    }
}

/// NostrDB-based cache implementation for NDKSwift
///
/// This actor provides persistent event storage using nostrdb as the backend,
/// with high-performance event storage and native nostrdb querying capabilities.
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
/// ## Event Operations
/// - `saveEvent(_:)` - Stores events in nostrdb with LMDB persistence
/// - `getEvent(id:)` - Retrieves events from nostrdb by ID
/// - `queryEvents(_:)` - Queries using nostrdb native filters with in-memory fallback
/// - `deleteEvent(id:)` - Marks as deleted in-memory (nostrdb events are immutable)
/// - `getProfileMetadata(pubkey:)` - Uses nostrdb's native profile lookup
/// - `textSearch(_:limit:)` - Leverages nostrdb's full-text search index
/// - `processEvent(_:from:subscriptionId:)` - Tracks relay sources via nostrdb
/// - `getRelaySources(eventId:)` - Returns relays that provided an event (in-memory + nostrdb)
/// - `observeEvents(matching:includeExisting:)` - Real-time event observation using nostrdb subscriptions
/// - `observeProfile(pubkey:includeExisting:)` - Real-time profile observation using nostrdb subscriptions
/// - `clear()` - Clears in-memory cache and unpublished events
/// - `clearPersisted()` - Clears persisted database and unpublished events
///
/// ## Optimistic Publishing
/// - `addUnpublishedEvent(_:publishedRelays:pendingRelays:)` - Tracks unpublished events with per-relay state in JSONL file
/// - `confirmEvent(eventId:onRelay:)` - Marks events as confirmed on specific relays
/// - `getEventConfirmationState(eventId:)` - Returns detailed state (which relays pending/confirmed)
/// - `getUnpublishedEvents(maxAge:limit:)` - Returns pending events (persists across app restarts)
/// - `recordPublishFailure(eventId:relay:reason:)` - Records failure reason for specific relay
/// - `removeUnpublishedEvent(eventId:)` - Removes event from tracking when threshold is met
///
/// ## Usage
/// ```swift
/// let cache = try await NDKNostrDBCache(path: "path/to/db")
/// try await cache.saveEvent(event)
/// let event = await cache.getEvent(id: eventId)
/// let results = await cache.textSearch("bitcoin")
/// ```
public actor NDKNostrDBCache {
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

    /// Cache configuration for memory and disk limits
    private let config: NDKCacheConfig

    /// LRU tracking for in-memory events (stores event ID -> last access time)
    private var eventAccessOrder: [String] = []

    /// Background task for enforcing cache limits
    private var enforcementTask: Task<Void, Never>?

    /// Persistent SQLite-backed store for non-event auxiliary state (NIP-05
    /// cache, KV, decrypted content cache, deletion markers, fetch times).
    /// Nil if we couldn't open the auxiliary database; the cache still works
    /// in memory-only mode in that case (losing the persistence guarantees).
    private let sqliteStore: NDKCacheSQLiteStore?

    /// Initialize a new NostrDB cache
    /// - Parameters:
    ///   - path: Optional path to the database directory. If nil, uses the default location.
    ///   - config: Cache configuration with memory/disk limits. Uses defaults if not specified.
    /// - Throws: NDKNostrDBCacheError if the database cannot be opened
    public init(path: String? = nil, config: NDKCacheConfig = .default) async throws {
        cachePath = path
        self.config = config
        relayCache = LRUCache<String, Bool>(capacity: Self.maxRelayCount, defaultTTL: TimeInterval.infinity)
        nostrDB = Ndb(path: path)
        publishingManager = OptimisticPublishingManager(cachePath: path)

        if nostrDB == nil {
            throw NDKNostrDBCacheError.failedToOpen
        }

        // Open the SQLite auxiliary store. Best-effort: failures here are
        // logged and we fall back to memory-only behavior so a corrupt
        // sidecar can't take the whole cache down. Pre-e9925313 stores
        // (deletedEventIds, decrypted content cache, kvStore, NIP-05 cache,
        // fetchTimes) all hydrate from this on init and write through to
        // it on every set.
        let sqlitePath = Self.auxStorePath(for: path)
        do {
            sqliteStore = try NDKCacheSQLiteStore(path: sqlitePath)
        } catch {
            NDKLogger.log(.warning, category: .cache,
                          "Failed to open auxiliary SQLite store at \(sqlitePath): \(error) — falling back to memory-only")
            sqliteStore = nil
        }

        // Hydrate in-memory caches from SQLite. Each hydration is best-effort.
        await hydrateFromSQLite()

        // Start background limit enforcement if enabled
        if config.autoEnforceLimits {
            startBackgroundEnforcement()
        }
    }

    /// Compute the path to the auxiliary SQLite store file. Lives alongside
    /// the NostrDB LMDB files so a single cache directory holds both.
    private static func auxStorePath(for cachePath: String?) -> String {
        let base = cachePath ?? Ndb.db_path() ?? NSTemporaryDirectory()
        if base.hasSuffix("/") {
            return base + "ndkswift-aux.sqlite"
        }
        return base + "/ndkswift-aux.sqlite"
    }

    /// Load persisted state from SQLite into the in-memory caches.
    private func hydrateFromSQLite() async {
        guard let store = sqliteStore else { return }

        // Deletion markers (NIP-09 tombstones).
        if let loaded = try? await store.loadDeletedEvents() {
            deletedEventIds = loaded
            NDKLogger.log(.debug, category: .cache,
                          "Hydrated \(loaded.count) deletion markers from SQLite")
        }

        // Decrypted content cache (most-recent first up to capacity).
        if let rows = try? await store.loadRecentDecrypted(limit: 1000) {
            for row in rows {
                await decryptedContentCache.set(row.key, value: row.content)
            }
            if !rows.isEmpty {
                NDKLogger.log(.debug, category: .cache,
                              "Hydrated \(rows.count) decrypted-content entries from SQLite")
            }
        }

        // Generic key/value store. Loads the whole table — keep small.
        if let rows = try? await store.loadAllKV() {
            for row in rows {
                if kvStore[row.namespace] == nil { kvStore[row.namespace] = [:] }
                kvStore[row.namespace]?[row.key] = row.value
            }
            if !rows.isEmpty {
                NDKLogger.log(.debug, category: .cache,
                              "Hydrated \(rows.count) KV entries from SQLite")
            }
        }

        // NIP-05 verification cache.
        if let rows = try? await store.loadAllNIP05() {
            let decoder = JSONDecoder()
            for row in rows {
                if let entry = try? decoder.decode(NIP05CacheEntry.self, from: row.entryJSON) {
                    nip05Cache[row.identifier] = entry
                    if entry.status == .verified {
                        nip05ByPubkey[entry.pubkey] = entry.identifier
                    }
                }
            }
            if !rows.isEmpty {
                NDKLogger.log(.debug, category: .cache,
                              "Hydrated \(rows.count) NIP-05 entries from SQLite")
            }
        }

        // Per-filter fetch timestamps.
        if let rows = try? await store.loadAllFetchTimes() {
            for row in rows {
                fetchTimes[row.fingerprint] = row.date
            }
            if !rows.isEmpty {
                NDKLogger.log(.debug, category: .cache,
                              "Hydrated \(rows.count) fetch-time entries from SQLite")
            }
        }
    }

    /// Fire-and-forget write-through helper for SQLite persistence.
    /// We don't want every public method to gain `try` / `throws`, so we
    /// log errors and let the in-memory copy win for this run.
    private nonisolated func sqliteWriteThrough(_ work: @Sendable @escaping (NDKCacheSQLiteStore) async throws -> Void) {
        Task { [weak self] in
            guard let self else { return }
            guard let store = self.sqliteStore else { return }
            do {
                try await work(store)
            } catch {
                NDKLogger.log(.warning, category: .cache,
                              "SQLite write-through failed: \(error.localizedDescription)")
            }
        }
    }

    /// Start background task for periodic limit enforcement
    private func startBackgroundEnforcement() {
        enforcementTask?.cancel()
        enforcementTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(self?.config.enforcementIntervalSeconds ?? 300) * 1_000_000_000)
                } catch {
                    break
                }

                guard let self = self else { break }
                await self.enforceMemoryLimit()
                do {
                    try await self.enforceDiskLimit()
                } catch {
                    NDKLogger.log(.warning, category: .cache, "Background disk limit enforcement failed: \(error)")
                }
            }
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

    /// Get the current cache configuration
    public var cacheConfig: NDKCacheConfig {
        return config
    }

    // MARK: - Cache Limit Enforcement

    /// Enforce the memory event limit using LRU eviction
    /// Removes least recently accessed events when over the limit
    public func enforceMemoryLimit() async {
        let eventsToRemove = events.count - config.maxMemoryEvents
        guard eventsToRemove > 0 else { return }

        NDKLogger.log(.info, category: .cache, "Enforcing memory limit: removing \(eventsToRemove) events (current: \(events.count), max: \(config.maxMemoryEvents))")

        // Remove oldest events based on access order (LRU eviction)
        var removed = 0
        while removed < eventsToRemove && !eventAccessOrder.isEmpty {
            let eventId = eventAccessOrder.removeFirst()
            if events.removeValue(forKey: eventId) != nil {
                eventRelaySources.removeValue(forKey: eventId)
                removed += 1
            }
        }

        // If access order is out of sync with events dict, clean up remaining
        if removed < eventsToRemove {
            // Sort events by createdAt and remove oldest
            let sortedEvents = events.sorted { $0.value.createdAt < $1.value.createdAt }
            let toRemove = sortedEvents.prefix(eventsToRemove - removed)
            for (id, _) in toRemove {
                events.removeValue(forKey: id)
                eventAccessOrder.removeAll { $0 == id }
                eventRelaySources.removeValue(forKey: id)
            }
        }

        NDKLogger.log(.info, category: .cache, "Memory limit enforced: now have \(events.count) events in memory")
    }

    /// Enforce the disk size limit
    /// Prunes oldest events from nostrdb when disk usage exceeds the limit
    public func enforceDiskLimit() async throws {
        let currentSizeMB = getDatabaseSize() / (1024 * 1024)
        let maxSizeMB = Int64(config.maxDiskSizeMB)

        guard currentSizeMB > maxSizeMB else { return }

        NDKLogger.log(.info, category: .cache, "Disk limit exceeded: \(currentSizeMB)MB > \(maxSizeMB)MB, pruning old events")

        // Prune events older than retention period
        let retentionSeconds = TimeInterval(config.eventRetentionDays * 24 * 60 * 60)
        try await pruneOldEvents(olderThan: retentionSeconds)

        let newSizeMB = getDatabaseSize() / (1024 * 1024)
        NDKLogger.log(.info, category: .cache, "After pruning: \(newSizeMB)MB")
    }

    /// Prune events older than the specified time interval
    /// - Parameter olderThan: Events older than this interval from now will be removed
    /// - Note: This marks events as deleted in-memory. NostrDB's LMDB storage is immutable,
    ///         but events will be filtered from future queries.
    public func pruneOldEvents(olderThan interval: TimeInterval) async throws {
        let cutoffTimestamp = Timestamp(Date().timeIntervalSince1970 - interval)
        var prunedCount = 0

        // Prune from in-memory cache
        let eventsToPrune = events.filter { $0.value.createdAt < cutoffTimestamp }
        for (id, _) in eventsToPrune {
            events.removeValue(forKey: id)
            eventAccessOrder.removeAll { $0 == id }
            eventRelaySources.removeValue(forKey: id)
            deletedEventIds.insert(id)
            prunedCount += 1
        }

        NDKLogger.log(.info, category: .cache, "Pruned \(prunedCount) events older than \(Int(interval / 86400)) days")
    }

    /// Get cache usage statistics
    /// - Returns: Tuple with memory event count, disk size in MB, and configured limits
    public func getCacheUsage() -> (memoryEvents: Int, diskSizeMB: Int64, maxMemoryEvents: Int, maxDiskSizeMB: Int) {
        let diskSizeMB = getDatabaseSize() / (1024 * 1024)
        return (events.count, diskSizeMB, config.maxMemoryEvents, config.maxDiskSizeMB)
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

        // Track in memory with LRU ordering
        if events[event.id] == nil {
            // New event - add to access order
            eventAccessOrder.append(event.id)
        } else {
            // Existing event - move to end of access order (most recently used)
            eventAccessOrder.removeAll { $0 == event.id }
            eventAccessOrder.append(event.id)
        }
        events[event.id] = event

        // Apply NIP-09 deletion semantics for kind-5 events at ingestion time.
        applyDeletionIfApplicable(event)

        // Enforce memory limit if needed (immediate enforcement on save)
        if events.count > config.maxMemoryEvents {
            await enforceMemoryLimit()
        }
    }

    /// If `event` is a NIP-09 deletion (kind 5), mark each e-tagged event ID as
    /// deleted — but only when the deletion's author matches the original
    /// event's author (per NIP-09 only the author can delete their own events).
    /// Events that are not yet in the in-memory map are still recorded as
    /// deleted so they will be filtered out when they arrive later.
    private func applyDeletionIfApplicable(_ event: NDKEvent) {
        guard event.kind == EventKind.deletion else { return }

        var newlyDeleted: [String] = []
        for tag in event.tags where tag.count >= 2 && tag[0] == "e" {
            let targetId = tag[1]
            // If we have the target locally, verify authorship before honoring.
            if let target = events[targetId] {
                guard target.pubkey == event.pubkey else { continue }
            }
            if deletedEventIds.insert(targetId).inserted {
                newlyDeleted.append(targetId)
            }
            events.removeValue(forKey: targetId)
            eventAccessOrder.removeAll { $0 == targetId }
        }
        if !newlyDeleted.isEmpty {
            let idsToPersist = newlyDeleted
            sqliteWriteThrough { store in
                for id in idsToPersist {
                    try? await store.addDeletedEvent(id)
                }
                _ = store
            }
        }
    }

    /// NIP-40: an event with an `expiration` tag (Unix timestamp seconds)
    /// is considered expired once that time has passed and SHOULD NOT be
    /// returned from queries or `getEvent`.
    private func isExpired(_ event: NDKEvent) -> Bool {
        for tag in event.tags where tag.count >= 2 && tag[0] == "expiration" {
            if let ts = Int64(tag[1]), ts > 0, ts <= Int64(Date().timeIntervalSince1970) {
                return true
            }
        }
        return false
    }

    public func getEvent(id: String) async -> NDKEvent? {
        // Filter out deleted events
        if deletedEventIds.contains(id) {
            return nil
        }

        // Update LRU access order if event is in memory
        if events[id] != nil {
            eventAccessOrder.removeAll { $0 == id }
            eventAccessOrder.append(id)
        }

        let resolved: NDKEvent? = {
            guard let nostrDB = nostrDB else { return events[id] }
            guard let idData = hexToData(id) else { return nil }
            let noteId = NdbNoteId(idData)
            guard let txn = nostrDB.lookup_note(noteId),
                  let note = txn.unsafeUnownedValue
            else {
                return events[id]
            }
            return convertToNDKEvent(note)
        }()

        // NIP-40: don't surface expired events.
        if let event = resolved, isExpired(event) {
            return nil
        }
        return resolved
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
            let noteKeys = try nostrDB.query(filters: [ndbFilter], maxResults: filter.limit ?? 10000)

            // Convert note keys to NDKEvents, filtering out deleted/expired events
            for noteKey in noteKeys {
                if let txn = nostrDB.lookup_note_by_key(noteKey),
                   let note = txn.unsafeUnownedValue,
                   let event = convertToNDKEvent(note) {
                    if !seenIds.contains(event.id),
                       !deletedEventIds.contains(event.id),
                       !isExpired(event) {
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
            if !seenIds.contains(event.id),
               !deletedEventIds.contains(event.id),
               !isExpired(event) {
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
        eventAccessOrder.removeAll { $0 == id }
        // Drop relay-source bookkeeping too — used to grow forever.
        eventRelaySources.removeValue(forKey: id)
        // Track as deleted to filter from all queries (persisted via SQLite).
        if deletedEventIds.insert(id).inserted {
            sqliteWriteThrough { store in
                try await store.addDeletedEvent(id)
            }
        }
    }

    // MARK: - Cache Management

    /// Clears only the in-memory cache, leaving the persisted LMDB database files intact.
    /// After calling this method, the database will still contain all events on disk.
    /// - Note: To fully clear the database including persisted data, use `clearPersisted()` instead.
    public func clear() async throws {
        events.removeAll()
        eventAccessOrder.removeAll()
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
        // Cancel background enforcement
        enforcementTask?.cancel()
        enforcementTask = nil

        // Clear in-memory state first
        events.removeAll()
        eventAccessOrder.removeAll()
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

        // Restart background enforcement if enabled
        if config.autoEnforceLimits {
            startBackgroundEnforcement()
        }
    }

    /// Stop background limit enforcement (useful when shutting down)
    public func stopBackgroundEnforcement() {
        enforcementTask?.cancel()
        enforcementTask = nil
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
                    // Use filter's limit if set, otherwise use 100000 to load all existing events
                    let maxResults = filter.limit ?? 100000
                    let subscriptionStream = try nostrDB.subscribe(filters: [ndbFilter], maxSimultaneousResults: maxResults)

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
                               let event = self.convertToNDKEvent(note) {
                                continuation.yield([event])
                            }
                        case .events(let noteKeys):
                            // Convert batch of NoteKeys to NDKEvents (initial query results)
                            var events: [NDKEvent] = []
                            events.reserveCapacity(noteKeys.count)
                            for noteKey in noteKeys {
                                if let txn = nostrDB.lookup_note_by_key(noteKey),
                                   let note = txn.unsafeUnownedValue,
                                   let event = self.convertToNDKEvent(note) {
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
                               let note = txn.unsafeUnownedValue {
                                // Parse profile metadata from the event content
                                if let data = note.content.data(using: .utf8),
                                   let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                    let userMetadata = NDKUserMetadata(
                                        pubkey: pubkey,
                                        parsedMetadata: metadata,
                                        updatedAt: Timestamp(note.created_at),
                                        eventId: self.dataToHex(note.id.id)
                                    )
                                    continuation.yield(userMetadata)
                                }
                            }
                        case .events(let noteKeys):
                            // Batch events - find the most recent kind 0 event
                            var latestMetadata: NDKUserMetadata?
                            var latestTimestamp: Timestamp = 0
                            for noteKey in noteKeys {
                                if let txn = nostrDB.lookup_note_by_key(noteKey),
                                   let note = txn.unsafeUnownedValue {
                                    // Only process kind 0 events
                                    guard note.kind == 0 else { continue }
                                    let timestamp = Timestamp(note.created_at)
                                    if timestamp > latestTimestamp {
                                        if let data = note.content.data(using: .utf8),
                                           let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                            latestTimestamp = timestamp
                                            latestMetadata = NDKUserMetadata(
                                                pubkey: pubkey,
                                                parsedMetadata: metadata,
                                                updatedAt: timestamp,
                                                eventId: self.dataToHex(note.id.id)
                                            )
                                        }
                                    }
                                }
                            }
                            if let metadata = latestMetadata {
                                continuation.yield(metadata)
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
               let event = convertToNDKEvent(note) {
                results.append(event)
            }
        }

        return results
    }

    // MARK: - Profile Search

    /// Search profiles by name/displayName using nostrdb's profile search index
    ///
    /// This method uses nostrdb's native profile search capability which indexes
    /// profile names and display names for fast prefix matching.
    ///
    /// - Parameters:
    ///   - query: Search query string (matches name or displayName prefix)
    ///   - limit: Maximum number of results (default: 20)
    /// - Returns: Array of pubkeys matching the query
    public func searchProfiles(_ query: String, limit: Int = 20) async -> [String] {
        guard let nostrDB = nostrDB else { return [] }
        guard !query.isEmpty else { return [] }

        // Use nostrdb's native profile search
        guard let txn = NdbTxn(ndb: nostrDB) else { return [] }

        let pubkeys = nostrDB.search_profile(query, limit: limit, txn: txn)
        return pubkeys.map { dataToHex($0.data) }
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

        // Apply NIP-09 deletion semantics so kind-5 events ingested from a relay
        // immediately remove their targets from query results.
        applyDeletionIfApplicable(event)
    }

    /// Get relay sources for an event
    ///
    /// Returns relay URLs that have provided this event. First checks the in-memory cache
    /// for immediate availability, then falls back to querying nostrdb's persisted relay
    /// index. This means relay sources survive app restarts — nostrdb stores relay provenance
    /// in LMDB via `ndb_note_relay_iterate_*`.
    ///
    /// - Parameter eventId: The event ID to check
    /// - Returns: Set of relay URLs that have provided this event
    public func getRelaySources(eventId: String) async -> Set<String> {
        // Check in-memory cache first (immediately available, includes recently-seen relays)
        if let sources = eventRelaySources[eventId], !sources.isEmpty {
            return sources
        }

        // Fall back to nostrdb's persisted relay index
        guard let nostrDB = nostrDB,
              let idData = hexToData(eventId) else {
            return []
        }

        let noteId = NdbNoteId(idData)
        guard let noteKey = nostrDB.lookup_note_key(noteId) else {
            return []
        }

        let persistedRelays = nostrDB.getRelays(noteKey: noteKey)

        // Backfill in-memory cache for future fast lookups
        if !persistedRelays.isEmpty {
            eventRelaySources[eventId] = persistedRelays
        }

        return persistedRelays
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

    // MARK: - Decrypted Content Cache (In-Memory LRU)

    /// LRU cache for decrypted content
    private var decryptedContentCache: LRUCache<String, String> = LRUCache(capacity: 1000)

    /// Retrieve decrypted content for an event and viewer
    public func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        let key = "\(eventId):\(viewerPubkey)"
        return await decryptedContentCache.get(key)
    }

    /// Store decrypted content for an event and viewer
    public func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        let key = "\(eventId):\(viewerPubkey)"
        await decryptedContentCache.set(key, value: content)
        sqliteWriteThrough { store in
            try await store.setDecrypted(key: key, content: content)
        }
    }

    /// Clear all decrypted content from cache
    public func clearDecryptedContent() async {
        await decryptedContentCache.clear()
        sqliteWriteThrough { store in
            try await store.clearAll() // limited blast — but we don't have a per-table truncate yet
            _ = store
        }
    }

    /// Clear decrypted content for a specific viewer
    public func clearDecryptedContent(for viewerPubkey: String) async {
        let allItems = await decryptedContentCache.allItems()
        var deletedKeys: [String] = []
        for (key, _) in allItems where key.hasSuffix(":\(viewerPubkey)") {
            await decryptedContentCache.delete(key)
            deletedKeys.append(key)
        }
        let toDelete = deletedKeys
        sqliteWriteThrough { store in
            for key in toDelete {
                try? await store.deleteDecrypted(key: key)
            }
            _ = store
        }
    }

    // MARK: - Generic Key-Value Store (In-Memory)

    /// In-memory key-value store: namespace -> key -> value
    private var kvStore: [String: [String: Data]] = [:]

    /// Store a value in the generic key-value store
    public func setValue(_ value: Data, forKey key: String, namespace: String) async throws {
        if kvStore[namespace] == nil {
            kvStore[namespace] = [:]
        }
        kvStore[namespace]?[key] = value
        sqliteWriteThrough { store in
            try await store.setKV(namespace: namespace, key: key, value: value)
        }
    }

    /// Retrieve a value from the generic key-value store
    public func getValue(forKey key: String, namespace: String) async -> Data? {
        return kvStore[namespace]?[key]
    }

    /// Delete a value from the generic key-value store
    public func deleteValue(forKey key: String, namespace: String) async throws {
        kvStore[namespace]?.removeValue(forKey: key)
        sqliteWriteThrough { store in
            try await store.deleteKV(namespace: namespace, key: key)
        }
    }

    /// Get all values in a namespace, optionally filtered by key prefix
    public func getValues(namespace: String, keyPrefix: String?) async -> [String: Data] {
        guard let namespaceStore = kvStore[namespace] else {
            return [:]
        }
        if let prefix = keyPrefix {
            return namespaceStore.filter { $0.key.hasPrefix(prefix) }
        }
        return namespaceStore
    }

    // MARK: - NIP-05 Caching (In-Memory)

    /// In-memory NIP-05 cache
    private var nip05Cache: [String: NIP05CacheEntry] = [:]
    private var nip05ByPubkey: [String: String] = [:]

    /// Domain rate limiting tracker
    private var domainVerificationAttempts: [String: Date] = [:]

    /// Save an unverified NIP-05 claim
    public func saveNIP05Claim(_ identifier: String, pubkey: String, retrievedAt: Date = Date()) async throws {
        let entry = NIP05CacheEntry(
            identifier: identifier,
            pubkey: pubkey,
            status: .unverified,
            claimedAt: retrievedAt
        )
        nip05Cache[identifier] = entry
        if let json = try? JSONEncoder().encode(entry) {
            sqliteWriteThrough { store in
                try await store.saveNIP05(identifier: identifier, entryJSON: json)
            }
        }
    }

    /// Get a NIP-05 cache entry by identifier
    public func getNIP05Entry(_ identifier: String) async -> NIP05CacheEntry? {
        return nip05Cache[identifier]
    }

    /// Get all NIP-05 entries for a given pubkey
    public func getNIP05Entries(pubkey: String) async -> [NIP05CacheEntry] {
        return nip05Cache.values.filter { $0.pubkey == pubkey }
    }

    /// Search for NIP-05 identifiers matching a prefix
    public func searchNIP05(_ prefix: String, limit: Int) async -> [NIP05CacheEntry] {
        let results = nip05Cache.values.filter { $0.identifier.hasPrefix(prefix) }
        return Array(results.prefix(limit))
    }

    /// Save a NIP-05 entry (convenience alias for saveNIP05Resolution)
    public func saveNIP05Entry(_ entry: NIP05CacheEntry) async throws {
        nip05Cache[entry.identifier] = entry
        // Also update reverse lookup by pubkey
        if entry.status == .verified {
            nip05ByPubkey[entry.pubkey] = entry.identifier
        }
        let identifier = entry.identifier
        if let json = try? JSONEncoder().encode(entry) {
            sqliteWriteThrough { store in
                try await store.saveNIP05(identifier: identifier, entryJSON: json)
            }
        }
    }

    /// Save a verified NIP-05 resolution result
    public func saveNIP05Resolution(_ entry: NIP05CacheEntry) async throws {
        try await saveNIP05Entry(entry)
    }

    /// Get NIP-05 identifier for a given pubkey
    public func getNIP05ForPubkey(_ pubkey: String) async -> String? {
        return nip05ByPubkey[pubkey]
    }

    /// Check if we can check a NIP-05 domain (rate limiting) - convenience alias
    public func canCheckNIP05Domain(_ domain: String) async -> Bool {
        return await canVerifyDomain(domain)
    }

    /// Record a NIP-05 domain check - convenience alias
    public func recordNIP05DomainCheck(_ domain: String) async throws {
        await recordDomainVerificationAttempt(domain)
    }

    /// Mark a NIP-05 entry as invalid
    public func invalidateNIP05(_ identifier: String, actualPubkey: String?) async throws {
        if var entry = nip05Cache[identifier] {
            // Remove old pubkey mapping
            nip05ByPubkey.removeValue(forKey: entry.pubkey)
            entry.status = .invalid
            nip05Cache[identifier] = entry
        }

        // If we know the actual pubkey, save a new verified entry
        if let actualPubkey = actualPubkey {
            let newEntry = NIP05CacheEntry(
                identifier: identifier,
                pubkey: actualPubkey,
                status: .verified,
                nip46Relays: nil,
                claimedAt: Date(),
                verifiedAt: Date(),
                lastCheckAt: Date()
            )
            try await saveNIP05Entry(newEntry)
        }
    }

    /// Check if a NIP-05 entry needs verification
    public func needsNIP05Verification(_ identifier: String, maxAge: TimeInterval) async -> Bool {
        guard let entry = nip05Cache[identifier] else { return true }
        if entry.status == .unverified || entry.status == .expired { return true }
        guard let lastCheck = entry.lastCheckAt ?? entry.verifiedAt else { return true }
        return Date().timeIntervalSince(lastCheck) > maxAge
    }

    /// Get unverified NIP-05 entries for background verification
    public func getUnverifiedNIP05s(limit: Int) async -> [NIP05CacheEntry] {
        let results = nip05Cache.values.filter { $0.status == .unverified }
        return Array(results.prefix(limit))
    }

    /// Check if we can verify a domain (rate limiting)
    public func canVerifyDomain(_ domain: String) async -> Bool {
        guard let lastAttempt = domainVerificationAttempts[domain] else { return true }
        return Date().timeIntervalSince(lastAttempt) > 360 // 6 minutes between checks per domain
    }

    /// Record a domain verification attempt
    public func recordDomainVerificationAttempt(_ domain: String) async {
        domainVerificationAttempts[domain] = Date()
    }

    // MARK: - Cache Freshness Tracking (In-Memory)

    /// In-memory tracking of last fetch times per filter fingerprint
    private var fetchTimes: [String: Date] = [:]

    /// Get the timestamp when events matching a filter were last fetched
    public func getLastFetchTime(for filter: NDKFilter) async -> Date? {
        return fetchTimes[filter.fingerprint]
    }

    /// Record that a filter was just queried
    public func recordFetchTime(for filter: NDKFilter, timestamp: Date = Date()) async {
        fetchTimes[filter.fingerprint] = timestamp
        let fingerprint = filter.fingerprint
        sqliteWriteThrough { store in
            try await store.setFetchTime(fingerprint: fingerprint, at: timestamp)
        }
    }

    // MARK: - Batch Profile Metadata Lookup

    /// Save parsed profile metadata to cache
    public func saveProfileMetadata(pubkey: String, metadata: [String: Any], updatedAt _: Timestamp, eventId _: String) async throws {
        // Profile metadata is stored in nostrdb via event processing
        // This method is a no-op for nostrdb since profiles are derived from kind:0 events
        // The metadata will be available through getProfileMetadata when the kind:0 event is ingested
        NDKLogger.log(.trace, category: .cache, "saveProfileMetadata called for \(pubkey) - profiles are auto-indexed by nostrdb")
    }

    /// Get multiple profile metadata entries at once using nostrdb's native lookup
    public func getMultipleProfileMetadata(pubkeys: [String]) async -> [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] {
        var result: [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] = [:]
        for pubkey in pubkeys {
            if let profile = await getProfileMetadata(pubkey: pubkey) {
                result[pubkey] = profile
            }
        }
        return result
    }

    // MARK: - Negentropy Optimized Queries

    /// Get events in a timestamp range for Negentropy reconciliation
    /// Uses nostrdb's native query when possible for better performance
    public func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        var rangeFilter = filter ?? NDKFilter()
        rangeFilter.since = from
        rangeFilter.until = to
        return try await queryEvents(rangeFilter)
    }

    /// Get event IDs and timestamps for efficient fingerprinting
    public func getEventIdsWithTimestamps(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [(id: String, timestamp: Timestamp)] {
        let events = try await getEventsByTimeRange(from: from, to: to, filter: filter)
        return events.map { (id: $0.id, timestamp: $0.createdAt) }
    }

    /// Batch check which events exist in cache
    public func hasEvents(ids: [String]) async -> [String: Bool] {
        var result: [String: Bool] = [:]
        for id in ids {
            result[id] = await getEvent(id: id) != nil
        }
        return result
    }

    // MARK: - Convenience Methods

    /// Check if an event exists in cache
    public func hasEvent(id: String) async -> Bool {
        return await getEvent(id: id) != nil
    }

    /// Batch save events
    public func saveEvents(_ events: [NDKEvent]) async throws {
        for event in events {
            try await saveEvent(event)
        }
    }

    /// Query events by author
    public func queryEvents(author: String, kinds: [Int]? = nil, limit: Int? = nil) async throws -> [NDKEvent] {
        var filter = NDKFilter(authors: [author])
        filter.kinds = kinds
        filter.limit = limit
        return try await queryEvents(filter)
    }

    /// Query events by kind
    public func queryEvents(kind: Int, limit: Int? = nil) async throws -> [NDKEvent] {
        let filter = NDKFilter(kinds: [kind], limit: limit)
        return try await queryEvents(filter)
    }
}

// MARK: - Error Types

/// Errors that can occur when using NDKNostrDBCache
public enum NDKNostrDBCacheError: Error {
    case failedToOpen
    case notInitialized
    case encodingFailed
}
