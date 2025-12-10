import Foundation
import NDKSwiftCore
import GRDB
import Combine

// MARK: - SQLite Constants

private enum SQLiteConstants {
    /// SQLite cache size in KB (negative means KB, positive means pages)
    static let cacheSize = -64000 // 64MB

    /// Batch size for bulk database operations to avoid SQLite limits
    static let queryBatchSize = 100
}


/// SQLite-backed cache implementation for NDKSwift
/// Provides efficient storage and querying of Nostr events with proper migration support
public actor NDKSQLiteCache: NDKCache {
    private let dbQueue: DatabaseQueue
    private let dbPath: String
    private let debugMode: Bool
    
    // Active observations
    private var activeObservations: [UUID: DatabaseCancellable] = [:]

    // Relay source tracking
    private var relaySourceTracking: [String: Set<String>] = [:] // eventId -> relay URLs

    // Tombstone cache for deletion events that arrive before the original event
    private var deletionTombstones: [String: Timestamp] = [:] // eventId -> deletion timestamp
    private let tombstoneTTL: TimeInterval = NetworkConstants.tombstoneTTL

    // Periodic cleanup task
    private var cleanupTask: Task<Void, Never>?

    /// Initialize SQLite cache with optional custom path
    public init(path: String? = nil, debugMode: Bool = false) async throws {
        self.debugMode = debugMode

        if let customPath = path {
            self.dbPath = customPath
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.dbPath = documentsPath.appendingPathComponent("ndk_cache.db").path
        }

        var config = Configuration()
        config.readonly = false
        self.dbQueue = try DatabaseQueue(path: dbPath, configuration: config)

        try await self.setupPragmas()
        try await self.migrateDatabase()

        // Start periodic cleanup task
        self.cleanupTask = Task {
            await self.startPeriodicCleanup()
        }
    }

    // MARK: - Database Setup & Configuration

    private func setupPragmas() async throws {
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA cache_size = \(SQLiteConstants.cacheSize)") // \(abs(SQLiteConstants.cacheSize) / 1024)MB cache
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
    }

    private func migrateDatabase() async throws {
        var migrator = DatabaseMigrator()

        // Register all migrations
        Self.registerV1InitialMigration(&migrator)
        Self.registerV2MintCachingMigration(&migrator)
        Self.registerV3StructuredMintDataMigration(&migrator)
        Self.registerV4OptimisticPublishingMigration(&migrator)
        Self.registerV5DecryptedContentMigration(&migrator)
        Self.registerV6RelaySourcesMigration(&migrator)
        Self.registerV7FetchTimestampsMigration(&migrator)
        Self.registerV8AddSubscriptionIdMigration(&migrator)
        Self.registerV9NIP05CacheMigration(&migrator)
        Self.registerV10RelayPreferencesMigration(&migrator)
        Self.registerV11ProfileAdditionalFieldsMigration(&migrator)
        Self.registerV12AddEventIdToProfilesMigration(&migrator)
        Self.registerV13KeyValueStoreMigration(&migrator)

        try migrator.migrate(dbQueue)
    }

    // MARK: - Event Storage Operations

    public func saveEvent(_ event: NDKEvent) async throws {
        // Skip ephemeral events (20000-29999)
        if EventKind.isEphemeral(event.kind) {
            NDKLogger.log(.trace, category: .cache, "Skipping ephemeral event (kind: \(event.kind)): \(event.id)")
            return
        }

        let eventId = event.id
        let pubkey = event.pubkey
        let createdAt = event.createdAt
        let kind = event.kind
        let content = event.content
        let sig = event.sig
        let tags = event.tags

        let jsonString = try JSONCoding.encodeToString(event)

        do {
            try await dbQueue.write { db in
                // Insert or replace event
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO events (id, pubkey, created_at, kind, content, sig, json)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [eventId, pubkey, createdAt, kind, content, sig, jsonString]
                )
                
                if self.debugMode {
                    NDKLogger.log(.info, category: .cache, "💾 Saved event to database - id: \(eventId), kind: \(kind), pubkey: \(pubkey.prefix(8))...")
                }

                // Save tags
                try db.execute(sql: "DELETE FROM tags WHERE event_id = ?", arguments: [eventId])

                for (index, tag) in tags.enumerated() {
                    guard tag.count >= 2 else { continue }

                    try db.execute(
                        sql: "INSERT INTO tags (event_id, tag_name, tag_value, tag_index) VALUES (?, ?, ?, ?)",
                        arguments: [eventId, tag[0], tag[1], index]
                    )
                }
            }
        } catch {
            logError(operation: "save event", parameter: eventId, error: error)
            throw error
        }
    }

    public func getEvent(id: String) async -> NDKEvent? {
        do {
            return try await dbQueue.read { [self] db in
                if let row = try Row.fetchOne(db, sql: "SELECT json FROM events WHERE id = ?", arguments: [id]) {
                    return try self.decodeEventFromRowThrowing(row)
                }
                return nil
            }
        } catch {
            logError(operation: "get event", parameter: id, error: error)
            return nil
        }
    }

    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        return try await dbQueue.read { [self] db in
            var arguments = StatementArguments()
            var whereClauses: [String] = []
            var joins: [String] = []
            var tagIndex = 0

            // Build filter clauses using helper
            SQLiteQueryBuilder.buildFilterClauses(
                from: filter,
                arguments: &arguments,
                whereClauses: &whereClauses,
                joins: &joins,
                tagIndex: &tagIndex
            )

            // Build final query using helper
            let sql = SQLiteQueryBuilder.buildSelectQuery(
                joins: joins,
                whereClauses: whereClauses,
                limit: filter.limit,
                orderBy: "e.created_at DESC"
            )

            // Execute query
            NDKLogger.log(.trace, category: .cache, "Executing SQL: \(sql)")

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)

            let events: [NDKEvent] = rows.compactMap { row in
                return self.decodeEventFromRow(row)
            }

            NDKLogger.log(.trace, category: .cache, "Exiting dbQueue.read block")
            return events
        }
    }

    public func deleteEvent(id: String) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM events WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Profile Metadata Operations

    /// Reconstruct profile metadata from database row
    private nonisolated func reconstructProfileMetadata(from row: Row) -> [String: Any] {
        var metadata: [String: Any] = [:]
        let pubkey = row["pubkey"] as? String ?? "unknown"

        // Check if we have semantic fields populated
        let hasSemanticFields = row["name"] as? String != nil ||
                              row["display_name"] as? String != nil ||
                              row["about"] as? String != nil

        if hasSemanticFields {
            // Add standard fields if present
            if let name = row["name"] as? String { metadata["name"] = name }
            if let displayName = row["display_name"] as? String { metadata["display_name"] = displayName }
            if let about = row["about"] as? String { metadata["about"] = about }
            if let picture = row["picture"] as? String { metadata["picture"] = picture }
            if let banner = row["banner"] as? String { metadata["banner"] = banner }
            if let website = row["website"] as? String { metadata["website"] = website }
            if let nip05 = row["nip05"] as? String { metadata["nip05"] = nip05 }
            if let lud06 = row["lud06"] as? String { metadata["lud06"] = lud06 }
            if let lud16 = row["lud16"] as? String { metadata["lud16"] = lud16 }

            // Add additional fields if present
            if let additionalFieldsData = row["additional_fields"] as? Data {
                let additionalFields: [String: String]?
                do {
                    additionalFields = try PropertyListSerialization.propertyList(from: additionalFieldsData, format: nil) as? [String: String]
                } catch {
                    NDKLogger.log(.warning, category: .cache, "Failed to deserialize additional fields for profile \(pubkey): \(error.localizedDescription)")
                    additionalFields = nil
                }
                if let additionalFields = additionalFields {
                    for (key, value) in additionalFields {
                        metadata[key] = value
                    }
                }
            }
        } else {
            // Fallback to JSON parsing for backward compatibility
            if let jsonString = row["json"] as? String,
               let jsonData = jsonString.data(using: .utf8) {
                let jsonDict: [String: Any]?
                do {
                    jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                } catch {
                    NDKLogger.log(.warning, category: .cache, "Failed to parse JSON for profile \(pubkey): \(error.localizedDescription)")
                    jsonDict = nil
                }
                if let jsonDict = jsonDict {
                    metadata = jsonDict
                }
            }
        }

        return metadata
    }

    public func saveProfileMetadata(pubkey: String, metadata: [String: Any], updatedAt: Timestamp, eventId: String) async throws {
        // Extract standard fields
        let name = metadata["name"] as? String
        let displayName = metadata["display_name"] as? String
        let about = metadata["about"] as? String
        let picture = metadata["picture"] as? String
        let banner = metadata["banner"] as? String
        let website = metadata["website"] as? String
        let nip05 = metadata["nip05"] as? String
        let lud06 = metadata["lud06"] as? String
        let lud16 = metadata["lud16"] as? String
        
        // Extract additional fields
        let knownKeys = ["name", "display_name", "about", "picture", "banner", "nip05", "lud16", "lud06", "website"]
        var additionalFields: [String: String] = [:]
        
        for (key, value) in metadata {
            if !knownKeys.contains(key), let stringValue = value as? String {
                additionalFields[key] = stringValue
            }
        }
        
        // Encode additional fields as property list data
        let additionalFieldsData: Data?
        if !additionalFields.isEmpty {
            do {
                additionalFieldsData = try PropertyListSerialization.data(fromPropertyList: additionalFields, format: .binary, options: 0)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to encode additional fields for profile \(pubkey): \(error.localizedDescription)")
                additionalFieldsData = nil
            }
        } else {
            additionalFieldsData = nil
        }
        
        // Reconstruct JSON for backward compatibility
        let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: [])
        let json = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO profiles 
                (pubkey, name, display_name, about, picture, nip05, lud06, lud16, banner, website, 
                 additional_fields, updated_at, event_id, json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    pubkey, name, displayName, about, picture, nip05, lud06, lud16, banner, website,
                    additionalFieldsData, updatedAt, eventId, json
                ]
            )
        }
        
        if debugMode {
            NDKLogger.log(.debug, category: .cache, "Saved profile metadata for \(pubkey.prefix(8))...")
        }
    }
    
    public func getProfileMetadata(pubkey: String) async -> (metadata: [String: Any], updatedAt: Timestamp, eventId: String)? {
        do {
            return try await dbQueue.read { db in
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM profiles WHERE pubkey = ?", arguments: [pubkey]) else {
                    return nil
                }

                let metadata = self.reconstructProfileMetadata(from: row)
                let updatedAt = row["updated_at"] as? Timestamp ?? 0
                let eventId = row["event_id"] as? String ?? ""

                return (metadata, updatedAt, eventId)
            }
        } catch {
            logError(operation: "get profile metadata", parameter: pubkey, error: error)
            return nil
        }
    }
    
    public func getMultipleProfileMetadata(pubkeys: [String]) async -> [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] {
        guard !pubkeys.isEmpty else { return [:] }
        
        do {
            return try await dbQueue.read { db in
                var result: [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] = [:]
                
                // Batch fetch in groups to avoid SQLite limits
                let chunks = stride(from: 0, to: pubkeys.count, by: SQLiteConstants.queryBatchSize).map {
                    Array(pubkeys[$0..<min($0 + SQLiteConstants.queryBatchSize, pubkeys.count)])
                }
                
                for chunk in chunks {
                    let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
                    let sql = "SELECT * FROM profiles WHERE pubkey IN (\(placeholders))"

                    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(chunk))

                    for row in rows {
                        guard let pubkey = row["pubkey"] as? String else { continue }

                        let metadata = self.reconstructProfileMetadata(from: row)
                        let updatedAt = row["updated_at"] as? Timestamp ?? 0
                        let eventId = row["event_id"] as? String ?? ""

                        result[pubkey] = (metadata, updatedAt, eventId)
                    }
                }
                
                return result
            }
        } catch {
            logError(operation: "get multiple profile metadata", parameter: "batch", error: error)
            return [:]
        }
    }

    // MARK: - Decrypted Content Cache

    public func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        do {
            let cacheKey = "\(eventId):\(viewerPubkey)"
            return try await dbQueue.read { db in
                try String.fetchOne(db, sql: "SELECT content FROM decrypted_content WHERE cache_key = ?", arguments: [cacheKey])
            }
        } catch {
            if debugMode {
                NDKLogger.log(.error, category: .cache, "Error fetching decrypted content for \(eventId): \(error)")
            }
            return nil
        }
    }

    public func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        do {
            let cacheKey = "\(eventId):\(viewerPubkey)"
            try await dbQueue.write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO decrypted_content (cache_key, event_id, viewer_pubkey, content) VALUES (?, ?, ?, ?)",
                    arguments: [cacheKey, eventId, viewerPubkey, content]
                )
            }
            if debugMode {
                NDKLogger.log(.debug, category: .cache, "Stored decrypted content for event \(eventId) viewer \(viewerPubkey)")
            }
        } catch {
            if debugMode {
                NDKLogger.log(.error, category: .cache, "Error storing decrypted content for \(eventId): \(error)")
            }
        }
    }

    public func clearDecryptedContent() async {
        do {
            try await dbQueue.write { db in
                try db.execute(sql: "DELETE FROM decrypted_content")
            }
            if debugMode {
                NDKLogger.log(.info, category: .cache, "Cleared all decrypted content")
            }
        } catch {
            if debugMode {
                NDKLogger.log(.error, category: .cache, "Error clearing decrypted content: \(error)")
            }
        }
    }

    public func clearDecryptedContent(for viewerPubkey: String) async {
        do {
            try await dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM decrypted_content WHERE viewer_pubkey = ?",
                    arguments: [viewerPubkey]
                )
            }
            if debugMode {
                NDKLogger.log(.info, category: .cache, "Cleared decrypted content for viewer \(viewerPubkey)")
            }
        } catch {
            if debugMode {
                NDKLogger.log(.error, category: .cache, "Error clearing decrypted content for viewer: \(error)")
            }
        }
    }

    // MARK: - Generic Key-Value Store

    public func setValue(_ value: Data, forKey key: String, namespace: String) async throws {
        let currentTime = Timestamp.now
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO key_value_store (namespace, key, value, updated_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [namespace, key, value, currentTime]
            )
        }
    }

    public func getValue(forKey key: String, namespace: String) async -> Data? {
        do {
            return try await dbQueue.read { db in
                try Data.fetchOne(
                    db,
                    sql: "SELECT value FROM key_value_store WHERE namespace = ? AND key = ?",
                    arguments: [namespace, key]
                )
            }
        } catch {
            logError(operation: "get value", parameter: "\(namespace):\(key)", error: error)
            return nil
        }
    }

    public func deleteValue(forKey key: String, namespace: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM key_value_store WHERE namespace = ? AND key = ?",
                arguments: [namespace, key]
            )
        }
    }

    public func getValues(namespace: String, keyPrefix: String?) async -> [String: Data] {
        do {
            return try await dbQueue.read { db in
                let rows: [Row]
                if let prefix = keyPrefix {
                    rows = try Row.fetchAll(
                        db,
                        sql: "SELECT key, value FROM key_value_store WHERE namespace = ? AND key LIKE ?",
                        arguments: [namespace, "\(prefix)%"]
                    )
                } else {
                    rows = try Row.fetchAll(
                        db,
                        sql: "SELECT key, value FROM key_value_store WHERE namespace = ?",
                        arguments: [namespace]
                    )
                }

                var result: [String: Data] = [:]
                for row in rows {
                    if let key = row["key"] as? String,
                       let value = row["value"] as? Data {
                        result[key] = value
                    }
                }
                return result
            }
        } catch {
            logError(operation: "get values", parameter: namespace, error: error)
            return [:]
        }
    }

    // MARK: - Optimistic Publishing

    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        let eventId = event.id
        let targetRelaysJson = try JSONCoding.encodeToString(Array(relays))
        let currentTime = Timestamp.now

        try await dbQueue.write { db in
            // First save the event if it doesn't exist
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO events (id, pubkey, created_at, kind, content, sig, json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    eventId,
                    event.pubkey,
                    event.createdAt,
                    event.kind,
                    event.content,
                    event.sig,
                    try JSONCoding.encodeToString(event)
                ]
            )

            // Save tags if event was newly inserted
            let eventExists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE event_id = ?", arguments: [eventId]) ?? 0
            if eventExists == 0 {
                for (index, tag) in event.tags.enumerated() {
                    guard tag.count >= 2 else { continue }

                    try db.execute(
                        sql: "INSERT INTO tags (event_id, tag_name, tag_value, tag_index) VALUES (?, ?, ?, ?)",
                        arguments: [eventId, tag[0], tag[1], index]
                    )
                }
            }

            // Record the optimistic confirmation state
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO event_confirmations
                (event_id, state, relay_url, target_relays, created_at, confirmed_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [eventId, "optimistic", nil, targetRelaysJson, currentTime, nil]
            )
        }
    }

    public func confirmEvent(eventId: String, onRelay relay: String) async throws {
        let confirmedTime = Timestamp.now

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE event_confirmations
                SET state = ?, relay_url = ?, confirmed_at = ?
                WHERE event_id = ?
                """,
                arguments: ["confirmed", relay, confirmedTime, eventId]
            )
        }
    }

    public func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        do {
            return try await dbQueue.read { db in
                if let row = try Row.fetchOne(
                    db,
                    sql: "SELECT state, relay_url FROM event_confirmations WHERE event_id = ?",
                    arguments: [eventId]
                ) {
                    let state = row["state"] as? String ?? ""
                    let relayUrl = row["relay_url"] as? String

                    switch state {
                    case "optimistic":
                        return .optimistic
                    case "confirmed":
                        if let relay = relayUrl {
                            return .confirmed(fromRelay: relay)
                        } else {
                            return .optimistic
                        }
                    default:
                        return nil
                    }
                }
                return nil
            }
        } catch {
            logError(operation: "get confirmation state for", parameter: eventId, error: error)
            return nil
        }
    }

    public func getUnpublishedEvents(maxAge: TimeInterval = TimeConstants.hour, limit: Int? = nil) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        let cutoffTime = Timestamp.now - Timestamp(maxAge)

        do {
            return try await dbQueue.read { db in
                var sql = """
                    SELECT e.json, ec.target_relays
                    FROM events e
                    JOIN event_confirmations ec ON e.id = ec.event_id
                    WHERE ec.state = 'optimistic' AND ec.created_at >= ?
                    ORDER BY ec.created_at DESC
                    """

                var arguments: StatementArguments = [cutoffTime]

                if let limit = limit, limit > 0 {
                    sql += " LIMIT ?"
                    arguments += [limit]
                }

                let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)

                return rows.compactMap { row in
                    guard let jsonString = row["json"] as? String,
                          let jsonData = jsonString.data(using: .utf8),
                          let event = JSONCoding.safeDecode(NDKEvent.self, from: jsonData),
                          let targetRelaysJson = row["target_relays"] as? String,
                          let targetRelaysData = targetRelaysJson.data(using: .utf8) else {
                        return nil
                    }

                    let targetRelaysArray: [String]?
                    do {
                        targetRelaysArray = try JSONCoding.decode([String].self, from: targetRelaysData)
                    } catch {
                        NDKLogger.log(.warning, category: .cache, "Failed to decode target relays for event \(event.id): \(error.localizedDescription)")
                        return nil
                    }

                    guard let targetRelaysArray = targetRelaysArray else {
                        return nil
                    }

                    return (event: event, targetRelays: Set(targetRelaysArray))
                }
            }
        } catch {
            logError(operation: "get unpublished events", parameter: "all", error: error)
            return []
        }
    }

    // MARK: - Deletion Event Handling

    /// Process a kind:5 deletion event according to NIP-09
    private func processDeletionEvent(_ deletionEvent: NDKEvent) async {
        // Extract event IDs to delete from "e" tags
        let eventIdsToDelete = deletionEvent.tags.eventIds

        guard !eventIdsToDelete.isEmpty else { return }

        let now = Timestamp.now
        let deletionAuthor = deletionEvent.pubkey

        // Process all deletions in a single transaction for atomicity and efficiency
        do {
            try await dbQueue.write { db in
                for eventId in eventIdsToDelete {
                    // Check if the event exists and verify author in one query
                    if let existingPubkey = try String.fetchOne(
                        db,
                        sql: "SELECT pubkey FROM events WHERE id = ?",
                        arguments: [eventId]
                    ) {
                        // Verify the deletion event author matches the original event author
                        if existingPubkey == deletionAuthor {
                            // Delete the event and its tags
                            try db.execute(sql: "DELETE FROM events WHERE id = ?", arguments: [eventId])
                            try db.execute(sql: "DELETE FROM tags WHERE event_id = ?", arguments: [eventId])
                            NDKLogger.log(.debug, category: .cache, "Deleted event \(eventId)")
                        }
                    }
                }
            }

            // Add tombstones for non-existent events outside the transaction
            for eventId in eventIdsToDelete {
                if await getEvent(id: eventId) == nil {
                    deletionTombstones[eventId] = now
                    if debugMode {
                        NDKLogger.log(.debug, category: .cache, "Added tombstone for event \(eventId)")
                    }
                }
            }
        } catch {
            NDKLogger.log(.error, category: .cache, "Failed to process deletion event: \(error)")
        }
    }

    // MARK: - NIP-05 Identity Cache

    public func saveNIP05Claim(_ identifier: String, pubkey: String, retrievedAt: Date = Date()) async throws {
        let claimedAt = Timestamp.from(retrievedAt)

        do {
            try await dbQueue.write { [debugMode] db in
                // Check if entry already exists
                let existing = try Row.fetchOne(db, sql: """
                    SELECT status FROM nip05_cache
                    WHERE identifier = ? AND pubkey = ?
                """, arguments: [identifier, pubkey])

                // Only insert if it doesn't exist or is in invalid state
                if existing == nil || existing?["status"] as? String == NIP05VerificationStatus.invalid.rawValue {
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO nip05_cache
                        (identifier, pubkey, status, claimed_at)
                        VALUES (?, ?, ?, ?)
                    """, arguments: [identifier, pubkey, NIP05VerificationStatus.unverified.rawValue, claimedAt])

                    if debugMode {
                        NDKLogger.log(.debug, category: .cache, "Saved NIP-05 claim: \(identifier) for \(pubkey)")
                    }
                }
            }
        } catch {
            logError(operation: "save NIP-05 claim", parameter: identifier, error: error)
            throw error
        }
    }

    public func getNIP05Entry(_ identifier: String) async -> NIP05CacheEntry? {
        do {
            return try await dbQueue.read { db in
                if let row = try Row.fetchOne(db, sql: """
                    SELECT * FROM nip05_cache
                    WHERE identifier = ?
                    ORDER BY verified_at DESC, claimed_at DESC
                    LIMIT 1
                """, arguments: [identifier]) {
                    return self.nip05EntryFromRow(row)
                }
                return nil
            }
        } catch {
            logError(operation: "get NIP-05 entry", parameter: identifier, error: error)
            return nil
        }
    }

    public func getNIP05Entries(pubkey: String) async -> [NIP05CacheEntry] {
        do {
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM nip05_cache
                    WHERE pubkey = ?
                    ORDER BY status = 'verified' DESC, verified_at DESC, claimed_at DESC
                """, arguments: [pubkey])
                return rows.compactMap { row in
                    self.nip05EntryFromRow(row)
                }
            }
        } catch {
            logError(operation: "get NIP-05 entries for pubkey", parameter: pubkey, error: error)
            return []
        }
    }

    public func searchNIP05(_ prefix: String, limit: Int) async -> [NIP05CacheEntry] {
        do {
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM nip05_cache
                    WHERE identifier LIKE ?
                    ORDER BY
                        status = 'verified' DESC,
                        LENGTH(identifier) ASC,
                        verified_at DESC,
                        claimed_at DESC
                    LIMIT ?
                """, arguments: ["\(prefix)%", limit])

                return rows.compactMap { row in
                    self.nip05EntryFromRow(row)
                }
            }
        } catch {
            logError(operation: "search NIP-05", parameter: prefix, error: error)
            return []
        }
    }

    public func saveNIP05Resolution(_ entry: NIP05CacheEntry) async throws {
        let claimedAt = Timestamp.from(entry.claimedAt)
        let verifiedAt = entry.verifiedAt.map { Timestamp.from($0) }
        let lastCheckAt = entry.lastCheckAt.map { Timestamp.from($0) }
        let nip46RelaysJSON: String?
        if let relays = entry.nip46Relays {
            do {
                nip46RelaysJSON = try JSONCoding.encodeToString(relays)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to encode NIP-46 relays for \(entry.identifier): \(error.localizedDescription)")
                nip46RelaysJSON = nil
            }
        } else {
            nip46RelaysJSON = nil
        }

        do {
            try await dbQueue.write { [debugMode] db in
                try db.execute(sql: """
                    INSERT OR REPLACE INTO nip05_cache
                    (identifier, pubkey, status, nip46_relays, claimed_at,
                     verified_at, last_check_at, error_message, http_status_code)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    entry.identifier,
                    entry.pubkey,
                    entry.status.rawValue,
                    nip46RelaysJSON,
                    claimedAt,
                    verifiedAt,
                    lastCheckAt,
                    entry.errorMessage,
                    entry.httpStatusCode
                ])

                if debugMode {
                    NDKLogger.log(.debug, category: .cache,
                        "Saved NIP-05 resolution: \(entry.identifier) -> \(entry.pubkey) (\(entry.status))")
                }
            }
        } catch {
            logError(operation: "save NIP-05 resolution", parameter: entry.identifier, error: error)
            throw error
        }
    }

    public func invalidateNIP05(_ identifier: String, actualPubkey: String?) async throws {
        do {
            try await dbQueue.write { [debugMode] db in
                // Mark all entries for this identifier as invalid
                try db.execute(sql: """
                    UPDATE nip05_cache
                    SET status = ?, last_check_at = ?, error_message = ?
                    WHERE identifier = ?
                """, arguments: [
                    NIP05VerificationStatus.invalid.rawValue,
                    Timestamp.from(Date()),
                    "Belongs to different pubkey",
                    identifier
                ])

                // If we know the actual owner, save that as verified
                if let actualPubkey = actualPubkey {
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO nip05_cache
                        (identifier, pubkey, status, claimed_at, verified_at, last_check_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        identifier,
                        actualPubkey,
                        NIP05VerificationStatus.verified.rawValue,
                        Timestamp.from(Date()),
                        Timestamp.from(Date()),
                        Timestamp.now
                    ])
                }

                if debugMode {
                    NDKLogger.log(.debug, category: .cache,
                        "Invalidated NIP-05: \(identifier), actual owner: \(actualPubkey ?? "unknown")")
                }
            }
        } catch {
            logError(operation: "invalidate NIP-05", parameter: identifier, error: error)
            throw error
        }
    }

    public func needsNIP05Verification(_ identifier: String, maxAge: TimeInterval) async -> Bool {
        do {
            return try await dbQueue.read { db in
                let row = try Row.fetchOne(db, sql: """
                    SELECT status, verified_at, last_check_at FROM nip05_cache
                    WHERE identifier = ?
                    ORDER BY verified_at DESC
                    LIMIT 1
                """, arguments: [identifier])

                guard let row = row,
                      let status = row["status"] as? String else {
                    return true
                }

                if status == NIP05VerificationStatus.unverified.rawValue {
                    return true
                }

                let lastCheck = row["last_check_at"] as? Int64 ?? row["verified_at"] as? Int64
                if let lastCheck = lastCheck {
                    let lastCheckDate = Date(nostrTimestamp: lastCheck)
                    return Date().timeIntervalSince(lastCheckDate) > maxAge
                }

                return true
            }
        } catch {
            logError(operation: "check NIP-05 needs verification", parameter: identifier, error: error)
            return true
        }
    }

    public func getUnverifiedNIP05s(limit: Int) async -> [NIP05CacheEntry] {
        do {
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM nip05_cache
                    WHERE status = ?
                    ORDER BY claimed_at DESC
                    LIMIT ?
                """, arguments: [NIP05VerificationStatus.unverified.rawValue, limit])

                return rows.compactMap { row in
                    self.nip05EntryFromRow(row)
                }
            }
        } catch {
            logError(operation: "get unverified NIP-05s", parameter: "limit: \(limit)", error: error)
            return []
        }
    }

    public func canVerifyDomain(_ domain: String) async -> Bool {
        let rateLimitWindow: TimeInterval = TimeConstants.hour
        let maxAttemptsPerWindow = 10
        let now = Timestamp.from(Date())

        do {
            return try await dbQueue.read { db in
                let row = try Row.fetchOne(db, sql: """
                    SELECT attempt_count, window_start FROM nip05_rate_limit
                    WHERE domain = ?
                """, arguments: [domain])

                guard let row = row,
                      let attemptCount = row["attempt_count"] as? Int,
                      let windowStart = row["window_start"] as? Int64 else {
                    return true
                }

                if TimeInterval(now - windowStart) > rateLimitWindow {
                    return true
                }

                return attemptCount < maxAttemptsPerWindow
            }
        } catch {
            logError(operation: "check domain rate limit", parameter: domain, error: error)
            return true
        }
    }

    public func recordDomainVerificationAttempt(_ domain: String) async {
        let rateLimitWindow: TimeInterval = TimeConstants.hour
        let now = Timestamp.from(Date())

        do {
            try await dbQueue.write { db in
                let existing = try Row.fetchOne(db, sql: """
                    SELECT attempt_count, window_start FROM nip05_rate_limit
                    WHERE domain = ?
                """, arguments: [domain])

                if let existing = existing,
                   let windowStart = existing["window_start"] as? Int64,
                   TimeInterval(now - windowStart) <= rateLimitWindow {
                    try db.execute(sql: """
                        UPDATE nip05_rate_limit
                        SET attempt_count = attempt_count + 1
                        WHERE domain = ?
                    """, arguments: [domain])
                } else {
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO nip05_rate_limit
                        (domain, attempt_count, window_start)
                        VALUES (?, 1, ?)
                    """, arguments: [domain, now])
                }
            }
        } catch {
            logError(operation: "record domain verification attempt", parameter: domain, error: error)
        }
    }

    // MARK: - Relay Preferences Cache

    public func saveRelayPreferences(
        pubkey: String,
        writeRelays: [String]?,
        readRelays: [String]?,
        fetchedAt: Date,
        expiresAt: Date,
        checkedRelays: Set<String>?
    ) async throws {
        let fetchedAtInt = Timestamp.from(fetchedAt)
        let expiresAtInt = Timestamp.from(expiresAt)

        let writeRelaysJSON: String?
        if let writeRelays = writeRelays {
            do {
                writeRelaysJSON = try JSONCoding.encodeToString(writeRelays)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to encode write relays for \(pubkey): \(error.localizedDescription)")
                writeRelaysJSON = nil
            }
        } else {
            writeRelaysJSON = nil
        }

        let readRelaysJSON: String?
        if let readRelays = readRelays {
            do {
                readRelaysJSON = try JSONCoding.encodeToString(readRelays)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to encode read relays for \(pubkey): \(error.localizedDescription)")
                readRelaysJSON = nil
            }
        } else {
            readRelaysJSON = nil
        }

        let checkedRelaysJSON: String?
        if let checkedRelays = checkedRelays {
            do {
                checkedRelaysJSON = try JSONCoding.encodeToString(Array(checkedRelays))
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to encode checked relays for \(pubkey): \(error.localizedDescription)")
                checkedRelaysJSON = nil
            }
        } else {
            checkedRelaysJSON = nil
        }

        do {
            try await dbQueue.write { [debugMode] db in
                try db.execute(sql: """
                    INSERT OR REPLACE INTO relay_preferences
                    (pubkey, write_relays, read_relays, fetched_at, expires_at, checked_relays)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [
                    pubkey,
                    writeRelaysJSON,
                    readRelaysJSON,
                    fetchedAtInt,
                    expiresAtInt,
                    checkedRelaysJSON
                ])

                if debugMode {
                    NDKLogger.log(.debug, category: .cache, "Saved relay preferences for \(pubkey)")
                }
            }
        } catch {
            logError(operation: "save relay preferences", parameter: pubkey, error: error)
            throw error
        }
    }

    public func getRelayPreferences(
        pubkey: String
    ) async -> (writeRelays: [String]?, readRelays: [String]?, fetchedAt: Date, expiresAt: Date, checkedRelays: Set<String>?)? {
        do {
            return try await dbQueue.read { db in
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT write_relays, read_relays, fetched_at, expires_at, checked_relays
                    FROM relay_preferences
                    WHERE pubkey = ?
                """, arguments: [pubkey]) else {
                    return nil
                }

                guard let fetchedAtInt = row["fetched_at"] as? Int64,
                      let expiresAtInt = row["expires_at"] as? Int64 else {
                    return nil
                }

                let writeRelays: [String]?
                if let json = row["write_relays"] as? String {
                    writeRelays = JSONCoding.safeDecode([String].self, from: json)
                } else {
                    writeRelays = nil
                }

                let readRelays: [String]?
                if let json = row["read_relays"] as? String {
                    readRelays = JSONCoding.safeDecode([String].self, from: json)
                } else {
                    readRelays = nil
                }

                let checkedRelays: Set<String>?
                if let json = row["checked_relays"] as? String,
                   let array = JSONCoding.safeDecode([String].self, from: json) {
                    checkedRelays = Set(array)
                } else {
                    checkedRelays = nil
                }

                return (
                    writeRelays: writeRelays,
                    readRelays: readRelays,
                    fetchedAt: Date(nostrTimestamp: fetchedAtInt),
                    expiresAt: Date(nostrTimestamp: expiresAtInt),
                    checkedRelays: checkedRelays
                )
            }
        } catch {
            logError(operation: "get relay preferences", parameter: pubkey, error: error)
            return nil
        }
    }

    // MARK: - Relay Source Tracking

    public func processEvent(
        _ event: NDKEvent,
        from relay: String,
        subscriptionId: String
    ) async throws {
        // Skip ephemeral events (20000-29999)
        if EventKind.isEphemeral(event.kind) {
            NDKLogger.log(.trace, category: .cache, "Skipping ephemeral event in processEvent (kind: \(event.kind)): \(event.id)")
            return
        }

        // Track relay source in memory
        relaySourceTracking[event.id, default: []].insert(relay)

        // Check if event was tombstoned by a deletion event
        if deletionTombstones[event.id] != nil {
            if debugMode {
                NDKLogger.log(.debug, category: .cache, "Event \(event.id) was tombstoned, not saving")
            }
            return
        }

        // Process deletion events (NIP-09) before saving
        if event.kind == EventKind.deletion {
            await processDeletionEvent(event)
        }

        // Check if event already exists
        _ = await hasEvent(id: event.id)

        // Save event to database
        try await saveEvent(event)

        // Save relay source to database
        try await saveRelaySource(eventId: event.id, relay: relay, subscriptionId: subscriptionId)
    }

    public func getRelaySources(eventId: String) async -> Set<String> {
        do {
            let relayUrls = try await dbQueue.read { db in
                try String.fetchAll(
                    db,
                    sql: "SELECT relay_url FROM relay_sources WHERE event_id = ?",
                    arguments: [eventId]
                )
            }
            return Set(relayUrls)
        } catch {
            logError(operation: "get relay sources", parameter: eventId, error: error)
            return relaySourceTracking[eventId] ?? []
        }
    }

    private func saveRelaySource(eventId: String, relay: String, subscriptionId: String?) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO relay_sources (event_id, relay_url, subscription_id)
                VALUES (?, ?, ?)
                """,
                arguments: [eventId, relay, subscriptionId]
            )
        }
    }

    // MARK: - Negentropy & Statistics

    public func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        return try await dbQueue.read { db in
            var arguments = StatementArguments()
            var whereClauses: [String] = []
            var joins: [String] = []
            var tagIndex = 0

            if let filter = filter {
                SQLiteQueryBuilder.buildFilterClauses(
                    from: filter,
                    arguments: &arguments,
                    whereClauses: &whereClauses,
                    joins: &joins,
                    tagIndex: &tagIndex,
                    includeTimeRange: (from: from, to: to)
                )
            } else {
                whereClauses.append("e.created_at >= ? AND e.created_at < ?")
                arguments += [from, to]
            }

            let sql = SQLiteQueryBuilder.buildSelectQuery(
                joins: joins,
                whereClauses: whereClauses,
                orderBy: "e.created_at ASC"
            )

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)

            return rows.compactMap { row in
                guard let jsonString = row["json"] as? String,
                      let jsonData = jsonString.data(using: .utf8) else { return nil }
                return JSONCoding.safeDecode(NDKEvent.self, from: jsonData)
            }
        }
    }

    public func getEventIdsWithTimestamps(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [(id: String, timestamp: Timestamp)] {
        return try await dbQueue.read { db in
            var arguments = StatementArguments()
            var whereClauses: [String] = []
            var joins: [String] = []
            var tagIndex = 0

            if let filter = filter {
                SQLiteQueryBuilder.buildFilterClauses(
                    from: filter,
                    arguments: &arguments,
                    whereClauses: &whereClauses,
                    joins: &joins,
                    tagIndex: &tagIndex,
                    includeTimeRange: (from: from, to: to)
                )
            } else {
                whereClauses.append("e.created_at >= ? AND e.created_at < ?")
                arguments += [from, to]
            }

            let sql = SQLiteQueryBuilder.buildSelectIdsQuery(
                joins: joins,
                whereClauses: whereClauses,
                orderBy: "e.created_at ASC"
            )

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)

            return rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let createdAt = row["created_at"] as? Int64 else { return nil }
                return (id: id, timestamp: Timestamp(createdAt))
            }
        }
    }

    public func hasEvents(ids: [String]) async -> [String: Bool] {
        guard !ids.isEmpty else { return [:] }

        do {
            return try await dbQueue.read { db in
                var result: [String: Bool] = [:]

                for id in ids {
                    result[id] = false
                }

                let batchSize = SQLiteConstants.queryBatchSize
                for i in stride(from: 0, to: ids.count, by: batchSize) {
                    let endIndex = min(i + batchSize, ids.count)
                    let batch = Array(ids[i..<endIndex])

                    let placeholders = batch.map { _ in "?" }.joined(separator: ", ")
                    let sql = "SELECT id FROM events WHERE id IN (\(placeholders))"

                    var arguments = StatementArguments()
                    for id in batch {
                        arguments += [id]
                    }

                    let existingIds = try String.fetchAll(db, sql: sql, arguments: arguments)
                    for id in existingIds {
                        result[id] = true
                    }
                }

                return result
            }
        } catch {
            logError(operation: "check event existence", parameter: "multiple events", error: error)
            return [:]
        }
    }

    public func getStatistics() async throws -> CacheStatistics {
        return try await dbQueue.read { db in
            let totalEvents = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0

            let rows = try Row.fetchAll(db, sql: "SELECT kind, COUNT(*) as count FROM events GROUP BY kind ORDER BY count DESC")

            var eventsByKind: [Int: Int] = [:]
            for row in rows {
                let kind = row["kind"] as Int
                let count = row["count"] as Int
                eventsByKind[kind] = count
            }

            return CacheStatistics(totalEvents: totalEvents, eventsByKind: eventsByKind)
        }
    }

    // MARK: - Cache Management & Cleanup

    /// Get cache statistics
    public func getCacheStats() async -> (events: Int, profiles: Int, kvEntries: Int) {
        do {
            return try await dbQueue.read { db in
                let events = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
                let profiles = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profiles") ?? 0
                let kvEntries = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM key_value_store") ?? 0
                return (events, profiles, kvEntries)
            }
        } catch {
            return (0, 0, 0)
        }
    }

    public func clear() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM events")
            try db.execute(sql: "DELETE FROM tags")
            try db.execute(sql: "DELETE FROM profiles")
            try db.execute(sql: "DELETE FROM key_value_store")
            try db.execute(sql: "DELETE FROM decrypted_content")
        }
        // VACUUM must be run outside of a transaction
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }

    public func eventCount() async -> Int {
        do {
            return try await dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
            }
        } catch {
            return 0
        }
    }

    public func profileCount() async -> Int {
        do {
            return try await dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profiles") ?? 0
            }
        } catch {
            return 0
        }
    }

    // MARK: - Fetch Timestamp Tracking

    public func getLastFetchTime(for filter: NDKFilter) async -> Date? {
        let fingerprint = filter.fingerprint

        do {
            return try await dbQueue.read { db in
                if let row = try Row.fetchOne(db, sql: """
                    SELECT last_fetch FROM fetch_timestamps WHERE filter_fingerprint = ?
                """, arguments: [fingerprint]) {
                    let timestamp = row["last_fetch"] as Int64
                    return Date(nostrTimestamp: timestamp)
                }
                return nil
            }
        } catch {
            logError(operation: "get fetch timestamp", parameter: fingerprint, error: error)
            return nil
        }
    }

    public func recordFetchTime(for filter: NDKFilter, timestamp: Date) async {
        let fingerprint = filter.fingerprint
        let timestampInt = Timestamp.from(timestamp)

        let filterJSON: String
        do {
            filterJSON = try JSONCoding.encodeToString(filter)
        } catch {
            filterJSON = "{}"
        }

        do {
            try await dbQueue.write { db in
                try db.execute(sql: """
                    INSERT OR REPLACE INTO fetch_timestamps
                    (filter_fingerprint, last_fetch, filter_json, updated_at)
                    VALUES (?, ?, ?, ?)
                """, arguments: [fingerprint, timestampInt, filterJSON, timestampInt])
            }

            if debugMode {
                NDKLogger.log(.debug, category: .cache, "Recorded fetch timestamp for filter \(fingerprint)")
            }
        } catch {
            logError(operation: "record fetch timestamp", parameter: fingerprint, error: error)
        }
    }

    // MARK: - Testing Support (only for unit tests)

    #if DEBUG
    /// Insert raw profile data for testing migration scenarios
    /// - Warning: This method is only available in DEBUG builds for testing
    public func insertRawProfileForTesting(pubkey: String, json: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO profiles (pubkey, json, updated_at) VALUES (?, ?, ?)",
                arguments: [pubkey, json, Timestamp.now]
            )
        }
    }

    /// Get raw profile row for testing
    /// - Warning: This method is only available in DEBUG builds for testing
    public func getRawProfileForTesting(pubkey: String) async throws -> [String: Any]? {
        return try await dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM profiles WHERE pubkey = ?", arguments: [pubkey]) else {
                return nil
            }

            var result: [String: Any] = [:]
            for (column, dbValue) in row {
                // Convert DatabaseValue to appropriate Swift type
                if dbValue.isNull {
                    result[column] = NSNull()
                } else if let stringValue = String.fromDatabaseValue(dbValue) {
                    result[column] = stringValue
                } else if let intValue = Int64.fromDatabaseValue(dbValue) {
                    result[column] = intValue
                } else if let dataValue = Data.fromDatabaseValue(dbValue) {
                    result[column] = dataValue
                } else {
                    // Store the database value directly if we can't convert it
                    result[column] = dbValue
                }
            }
            return result
        }
    }
    #endif

    // MARK: - Reactive Observation

    /// Check if an event matches a filter using an optimized hybrid approach
    /// This ensures consistency with queryEvents SQL logic while optimizing performance
    internal func eventMatchesFilter(_ event: NDKEvent, filter: NDKFilter) async -> Bool {
        // 1. Perform fast, in-memory checks for non-tag properties.
        // If any of these fail, we can return false immediately without a DB query.
        if let kinds = filter.kinds, !kinds.isEmpty, !kinds.contains(event.kind) {
            return false
        }
        if let authors = filter.authors, !authors.isEmpty, !authors.contains(event.pubkey) {
            return false
        }
        if let since = filter.since, event.createdAt < since {
            return false
        }
        if let until = filter.until, event.createdAt > until {
            return false
        }

        // 2. Determine if a database query is necessary for tag-based filters.
        // These are the filters that require complex JOINs in SQL.
        let needsDBQueryForTags = (filter.tags != nil && !filter.tags!.isEmpty)
                               || (filter.events != nil && !filter.events!.isEmpty)
                               || (filter.pubkeys != nil && !filter.pubkeys!.isEmpty)

        if !needsDBQueryForTags {
            // If we passed all in-memory checks and there are no tag filters,
            // the event is a match. No DB query needed.
            return true
        }

        // 3. Fallback to the database query for complex tag-based filters.
        // This preserves our Single Source of Truth for the most complex logic.
        do {
            // Create a filter that targets only this specific event
            var singleEventFilter = filter
            singleEventFilter.ids = [event.id]

            // Query the database to see if this event matches all filter criteria
            let matchingEvents = try await queryEvents(singleEventFilter)

            // If the query returns the event, it matches the filter
            return !matchingEvents.isEmpty
        } catch {
            // On error, for tag filters we err on the side of including the event
            // to avoid missing notifications
            NDKLogger.log(.warning, category: .cache, "Failed to check event match via database for tag filters, using fallback: \(error)")
            return true
        }
    }

    // MARK: - Private Helpers

    /// Log an error if debugMode is enabled
    private func logError(operation: String, parameter: String, error: Error) {
        if debugMode {
            NDKLogger.log(.error, category: .cache, "NDKSQLiteCache: Failed to \(operation) \(parameter). Error: \(error)")
        }
    }

    /// Helper method to decode NDKEvent from database row JSON
    private nonisolated func decodeEventFromRow(_ row: Row) -> NDKEvent? {
        guard let jsonString = row["json"] as? String,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        return JSONCoding.safeDecode(NDKEvent.self, from: jsonData)
    }

    /// Helper method to decode NDKEvent from database row JSON (throwing version)
    private nonisolated func decodeEventFromRowThrowing(_ row: Row) throws -> NDKEvent? {
        guard let jsonString = row["json"] as? String,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        return try JSONCoding.decode(NDKEvent.self, from: jsonData)
    }

    /// Start periodic cleanup of tombstones
    private func startPeriodicCleanup() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(NetworkConstants.cleanupInterval * Double(TimeConstants.nanosecondsPerSecond)))
            await cleanupTombstones()
        }
    }

    /// Clean up expired tombstones
    private func cleanupTombstones() async {
        let now = Timestamp.now
        let expiredKeys = deletionTombstones.compactMap { (eventId, timestamp) -> String? in
            let age = TimeInterval(now - timestamp)
            return age > tombstoneTTL ? eventId : nil
        }

        for key in expiredKeys {
            deletionTombstones.removeValue(forKey: key)
        }

        if debugMode && !expiredKeys.isEmpty {
            NDKLogger.log(.debug, category: .cache, "Cleaned up \(expiredKeys.count) expired tombstones")
        }
    }

    /// Helper function to convert database row to NIP05CacheEntry
    private nonisolated func nip05EntryFromRow(_ row: Row) -> NIP05CacheEntry? {
        guard let identifier = row["identifier"] as? String,
              let pubkey = row["pubkey"] as? String,
              let statusString = row["status"] as? String,
              let status = NIP05VerificationStatus(rawValue: statusString),
              let claimedAtInt = row["claimed_at"] as? Int64 else {
            return nil
        }

        let nip46Relays: [String]?
        if let relaysJSON = row["nip46_relays"] as? String {
            nip46Relays = JSONCoding.safeDecode([String].self, from: relaysJSON)
        } else {
            nip46Relays = nil
        }

        return NIP05CacheEntry(
            identifier: identifier,
            pubkey: pubkey,
            status: status,
            nip46Relays: nip46Relays,
            claimedAt: Date(nostrTimestamp: claimedAtInt),
            verifiedAt: (row["verified_at"] as? Int64).map { Date(nostrTimestamp: $0) },
            lastCheckAt: (row["last_check_at"] as? Int64).map { Date(nostrTimestamp: $0) },
            errorMessage: row["error_message"] as? String,
            httpStatusCode: row["http_status_code"] as? Int
        )
    }

    // MARK: - Reactive Query Support

    public func observeEvents(
        matching filter: NDKFilter,
        includeExisting: Bool = true
    ) async -> AsyncThrowingStream<[NDKEvent], Error> {
        if debugMode {
            NDKLogger.log(.info, category: .cache, "🚀 observeEvents called with filter: \(filter), includeExisting: \(includeExisting)")
        }
        
        let dbQueue = self.dbQueue
        let debugMode = self.debugMode
        
        return AsyncThrowingStream { continuation in
            let observationId = UUID()
            
            Task {
                // Track existing event IDs when includeExisting is false
                var existingEventIds: Set<String> = []
                
                if !includeExisting {
                    // Query existing events to track their IDs
                    do {
                        let existingEvents = try await self.queryEvents(filter)
                        existingEventIds = Set(existingEvents.map { $0.id })
                        if self.debugMode {
                            NDKLogger.log(.info, category: .cache, "🔍 Tracking \(existingEventIds.count) existing event IDs for includeExisting:false")
                        }
                    } catch {
                        if debugMode {
                            NDKLogger.log(.error, category: .cache, "Failed to query existing events for tracking: \(error)")
                        }
                    }
                }
                
                // Create the observation inline to work around GRDB type constraints
                let observation = ValueObservation.tracking { [weak self] db -> [NDKEvent] in
                    guard let self = self else { return [] }
                    
                    var arguments = StatementArguments()
                    var whereClauses: [String] = []
                    var joins: [String] = []
                    var tagIndex = 0
                    
                    // Build filter clauses
                    SQLiteQueryBuilder.buildFilterClauses(
                        from: filter,
                        arguments: &arguments,
                        whereClauses: &whereClauses,
                        joins: &joins,
                        tagIndex: &tagIndex
                    )
                    
                    // Build and execute query
                    let sql = SQLiteQueryBuilder.buildSelectQuery(
                        joins: joins,
                        whereClauses: whereClauses,
                        limit: filter.limit,
                        orderBy: "e.created_at DESC"
                    )
                    
                    let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
                    
                    return rows.compactMap { row in
                        self.decodeEventFromRow(row)
                    }
                }
                
                // Start the observation
                let cancellable = observation.start(
                    in: dbQueue,
                    onError: { error in
                        continuation.finish(throwing: error)
                    },
                    onChange: { events in
                        if self.debugMode {
                            NDKLogger.log(.info, category: .cache, "🔔 GRDB observation triggered: \(events.count) events for filter \(filter)")
                        }
                        
                        // Filter events based on includeExisting flag
                        let eventsToEmit: [NDKEvent]
                        if includeExisting {
                            eventsToEmit = events
                        } else {
                            // Only emit events that weren't in the initial set
                            eventsToEmit = events.filter { !existingEventIds.contains($0.id) }
                            if self.debugMode && eventsToEmit.count != events.count {
                                NDKLogger.log(.info, category: .cache, "🔍 Filtered out \(events.count - eventsToEmit.count) existing events, emitting \(eventsToEmit.count) new events")
                            }
                        }
                        
                        if !eventsToEmit.isEmpty {
                            continuation.yield(eventsToEmit)
                        }
                    }
                )
                
                // Store the cancellable
                await self.storeObservation(id: observationId, cancellable: cancellable)
                
                // If includeExisting, immediately query and emit current events
                if includeExisting {
                    do {
                        let existingEvents = try await self.queryEvents(filter)
                        if self.debugMode {
                            NDKLogger.log(.info, category: .cache, "🔍 Initial query for filter \(filter): found \(existingEvents.count) existing events")
                        }
                        if !existingEvents.isEmpty {
                            continuation.yield(existingEvents)
                        }
                    } catch {
                        if debugMode {
                            NDKLogger.log(.error, category: .cache, "Failed to fetch existing events: \(error)")
                        }
                    }
                }
                
                // Set up cleanup when the stream is terminated
                continuation.onTermination = { @Sendable _ in
                    Task {
                        await self.removeObservation(id: observationId)
                    }
                }
            }
        }
    }
    
    /// Store an active observation
    private func storeObservation(id: UUID, cancellable: DatabaseCancellable) async {
        activeObservations[id] = cancellable
    }
    
    /// Remove and cancel an observation
    private func removeObservation(id: UUID) async {
        if let cancellable = activeObservations.removeValue(forKey: id) {
            cancellable.cancel()
        }
    }
    
    /// Create a reactive query for a single event by ID
    /// - Parameters:
    ///   - eventId: The event ID to observe
    ///   - includeExisting: Whether to emit the existing event immediately (default: true)
    /// - Returns: An AsyncThrowingStream that emits the event when it changes, or nil if deleted
    public func observeEvent(
        id eventId: String,
        includeExisting: Bool = true
    ) async -> AsyncThrowingStream<NDKEvent?, Error> {
        let dbQueue = self.dbQueue
        
        return AsyncThrowingStream { continuation in
            let observationId = UUID()
            
            Task {
                    // Create observation for single event
                    let observation = ValueObservation.tracking { [weak self] db -> NDKEvent? in
                        guard let self = self else { return nil }
                        
                        if let row = try Row.fetchOne(db, sql: "SELECT json FROM events WHERE id = ?", arguments: [eventId]) {
                            return self.decodeEventFromRow(row)
                        }
                        return nil
                    }
                    
                    // Start the observation
                    let cancellable = observation.start(
                        in: dbQueue,
                        onError: { error in
                            continuation.finish(throwing: error)
                        },
                        onChange: { event in
                            continuation.yield(event)
                        }
                    )
                    
                    // Store the cancellable
                    await self.storeObservation(id: observationId, cancellable: cancellable)
                    
                    // If includeExisting, immediately fetch and emit current event
                    if includeExisting {
                        if let existingEvent = await self.getEvent(id: eventId) {
                            continuation.yield(existingEvent)
                        }
                    }
                    
                    // Set up cleanup
                    continuation.onTermination = { @Sendable _ in
                        Task {
                            await self.removeObservation(id: observationId)
                        }
                    }
            }
        }
    }
    
    /// Observe profile changes for a specific pubkey with reactive updates
    /// - Parameters:
    ///   - pubkey: The public key to observe profile changes for
    ///   - includeExisting: Whether to include existing cached profile (default: true)
    /// - Returns: An AsyncThrowingStream that emits the profile when it changes, or nil if deleted
    public func observeProfile(
        pubkey: String,
        includeExisting: Bool = true
    ) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        let dbQueue = self.dbQueue
        let debugMode = self.debugMode
        
        return AsyncThrowingStream { continuation in
            let observationId = UUID()
            
            Task {
                // Create observation for profile metadata
                let observation = ValueObservation.tracking { [weak self] db -> NDKUserMetadata? in
                    guard let self = self else { return nil }
                    
                    // Query for the latest kind 0 event for this pubkey
                    let sql = """
                        SELECT e.json 
                        FROM events e
                        WHERE e.kind = 0 
                        AND e.pubkey = ?
                        ORDER BY e.created_at DESC
                        LIMIT 1
                    """
                    
                    if let row = try Row.fetchOne(db, sql: sql, arguments: [pubkey]) {
                        if let event = self.decodeEventFromRow(row) {
                            return NDKUserMetadata(event: event)
                        }
                    }
                    return nil
                }
                
                // Start the observation
                let cancellable = observation.start(
                    in: dbQueue,
                    onError: { error in
                        continuation.finish(throwing: error)
                    },
                    onChange: { profile in
                        if debugMode {
                            NDKLogger.log(.info, category: .cache, "🔔 Profile observation triggered for pubkey \(pubkey)")
                        }
                        continuation.yield(profile)
                    }
                )
                
                // Store the cancellable
                await self.storeObservation(id: observationId, cancellable: cancellable)
                
                // If includeExisting, immediately fetch and emit current profile
                if includeExisting {
                    // First yield nil to indicate we're starting
                    continuation.yield(nil)
                    
                    // Then fetch the actual profile
                    do {
                        let filter = NDKFilter(authors: [pubkey], kinds: [EventKind.metadata], limit: 1)
                        let profileEvents = try await self.queryEvents(filter)
                        if let profileEvent = profileEvents.first {
                            let metadata = NDKUserMetadata(event: profileEvent)
                            continuation.yield(metadata)
                        }
                    } catch {
                        if debugMode {
                            NDKLogger.log(.error, category: .cache, "Failed to fetch existing profile: \(error)")
                        }
                    }
                }
                
                // Set up cleanup
                continuation.onTermination = { @Sendable _ in
                    Task {
                        await self.removeObservation(id: observationId)
                    }
                }
            }
        }
    }
    
}

// MARK: - Cache Statistics Models

/// Statistics about cached events
public struct CacheStatistics {
    public let totalEvents: Int
    public let eventsByKind: [Int: Int]

    public init(totalEvents: Int, eventsByKind: [Int: Int]) {
        self.totalEvents = totalEvents
        self.eventsByKind = eventsByKind
    }
}