import Foundation

import CashuSwift
import GRDB

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
    
    // Cache observation properties
    private var observers: [FilterSignature: Set<WeakObserver>] = [:]
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
    
    // MARK: - Database Setup
    
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
        
        try migrator.migrate(dbQueue)
    }
    
    // MARK: - Helper Methods
    
    /// Log an error if debugMode is enabled
    /// - Parameters:
    ///   - operation: The operation that failed (e.g., "save event", "get profile")
    ///   - parameter: The parameter involved in the operation (e.g., event ID, pubkey)
    ///   - error: The error that occurred
    private func logError(operation: String, parameter: String, error: Error) {
        if debugMode {
            NDKLogger.log(.error, category: .cache, "NDKSQLiteCache: Failed to \(operation) \(parameter). Error: \(error)")
        }
    }
    
    /// Helper method to decode NDKEvent from database row JSON
    /// - Parameter row: Database row containing JSON data
    /// - Returns: Decoded NDKEvent or nil if decoding fails
    private nonisolated func decodeEventFromRow(_ row: Row) -> NDKEvent? {
        guard let jsonString = row["json"] as? String,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        return JSONCoding.safeDecode(NDKEvent.self, from: jsonData)
    }
    
    /// Helper method to decode NDKEvent from database row JSON (throwing version)
    /// - Parameter row: Database row containing JSON data
    /// - Returns: Decoded NDKEvent
    /// - Throws: Decoding error if JSON is invalid
    private nonisolated func decodeEventFromRowThrowing(_ row: Row) throws -> NDKEvent? {
        guard let jsonString = row["json"] as? String,
              let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        return try JSONCoding.decode(NDKEvent.self, from: jsonData)
    }
    
    // MARK: - Event Operations (NDKCache protocol)
    
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
    
    // MARK: - Profile Operations
    
    public func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        // Still store JSON for backward compatibility during transition
        let jsonString = try JSONCoding.encodeToString(profile)
        
        // Encode additional fields as property list for efficient storage
        let additionalFieldsData: Data?
        if !profile.allAdditionalFields.isEmpty {
            additionalFieldsData = try PropertyListSerialization.data(
                fromPropertyList: profile.allAdditionalFields,
                format: .binary,
                options: 0
            )
        } else {
            additionalFieldsData = nil
        }
        
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO profiles 
                (pubkey, name, display_name, about, picture, nip05, lud06, lud16, banner, website, updated_at, json, additional_fields)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    pubkey,
                    profile.name,
                    profile.displayName,
                    profile.about,
                    profile.picture,
                    profile.nip05,
                    profile.lud06,
                    profile.lud16,
                    profile.banner,
                    profile.website,
                    Timestamp.now,
                    jsonString,
                    additionalFieldsData
                ]
            )
        }
    }
    
    public func getProfile(pubkey: String) async -> NDKUserProfile? {
        do {
            return try await dbQueue.read { db in
                guard let row = try Row.fetchOne(db, 
                    sql: "SELECT name, display_name, about, picture, banner, nip05, lud16, lud06, website, additional_fields, json FROM profiles WHERE pubkey = ?", 
                    arguments: [pubkey]) else {
                    return nil
                }
                
                // First try to reconstruct from individual fields (semantic caching)
                if row["name"] != nil || row["display_name"] != nil {
                    var profile = NDKUserProfile(
                        name: row["name"] as? String,
                        displayName: row["display_name"] as? String,
                        about: row["about"] as? String,
                        picture: row["picture"] as? String,
                        banner: row["banner"] as? String,
                        nip05: row["nip05"] as? String,
                        lud16: row["lud16"] as? String,
                        lud06: row["lud06"] as? String,
                        website: row["website"] as? String
                    )
                    
                    // Decode additional fields from property list
                    if let additionalFieldsData = row["additional_fields"] as? Data,
                       let additionalFields = try? PropertyListSerialization.propertyList(from: additionalFieldsData, options: [], format: nil) as? [String: String] {
                        for (key, value) in additionalFields {
                            profile.setAdditionalField(key, value: value)
                        }
                    }
                    
                    return profile
                }
                
                // Fallback to JSON parsing for old data (before migration)
                if let jsonString = row["json"] as? String,
                   let jsonData = jsonString.data(using: .utf8) {
                    return try JSONCoding.decode(NDKUserProfile.self, from: jsonData)
                }
                
                return nil
            }
        } catch {
            logError(operation: "get profile", parameter: pubkey, error: error)
            return nil
        }
    }
    
    // MARK: - Performance-optimized profile methods
    
    public func getProfileName(pubkey: String) async -> String? {
        return try? await dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM profiles WHERE pubkey = ?", arguments: [pubkey])
        }
    }
    
    public func getProfilePicture(pubkey: String) async -> String? {
        return try? await dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT picture FROM profiles WHERE pubkey = ?", arguments: [pubkey])
        }
    }
    
    public func searchProfiles(nameContains: String, limit: Int = 50) async -> [(pubkey: String, name: String)] {
        do {
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db, 
                    sql: "SELECT pubkey, name FROM profiles WHERE name LIKE ? ORDER BY name LIMIT ?", 
                    arguments: ["%\(nameContains)%", limit]
                )
                return rows.compactMap { row in
                    guard let pubkey = row["pubkey"] as? String,
                          let name = row["name"] as? String else { return nil }
                    return (pubkey: pubkey, name: name)
                }
            }
        } catch {
            logError(operation: "search profiles", parameter: "query", error: error)
            return []
        }
    }
    
    // MARK: - Mint Operations (MintCache protocol)
    
    public func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        let jsonString = try JSONCoding.encodeToString(info)
        let currentTime = Timestamp.now
        
        // Extract units for searching
        var units: [String] = []
        if let methods = info.nuts?.nut04?.methods {
            units = methods.map { $0.unit }
        }
        let unitsJson = try JSONCoding.encodeToString(units)
        
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO mint_info 
                (url, name, pubkey, version, units, json, last_updated, last_accessed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    url,
                    info.name,
                    info.pubkey,
                    info.version,
                    unitsJson,
                    jsonString,
                    currentTime,
                    currentTime
                ]
            )
        }
    }
    
    public func getMintInfo(url: String) async -> NDKMintInfo? {
        do {
            return try await dbQueue.write { db in
                // Update last_accessed time
                try db.execute(
                    sql: "UPDATE mint_info SET last_accessed = ? WHERE url = ?",
                    arguments: [Timestamp.now, url]
                )
                
                // Fetch the data
                if let row = try Row.fetchOne(db, sql: "SELECT json FROM mint_info WHERE url = ?", arguments: [url]),
                   let jsonString = row["json"] as? String,
                   let jsonData = jsonString.data(using: .utf8) {
                    return try JSONCoding.decode(NDKMintInfo.self, from: jsonData)
                }
                return nil
            }
        } catch {
            logError(operation: "get mint info", parameter: url, error: error)
            return nil
        }
    }
    
    public func isMintInfoStale(url: String, maxAge: TimeInterval = TimeConstants.day) async -> Bool {
        let staleThreshold = Timestamp.now - Timestamp(maxAge)
        return (try? await dbQueue.read { db in
            if let lastUpdated = try Int64.fetchOne(db, sql: "SELECT last_updated FROM mint_info WHERE url = ?", arguments: [url]) {
                return lastUpdated < staleThreshold
            }
            return true // If not found, consider it stale
        }) ?? true
    }
    
    public func invalidateMintCache(url: String) async throws {
        try await dbQueue.write { db in
            // Delete mint info and keysets (cascade will handle keysets)
            try db.execute(sql: "DELETE FROM mint_info WHERE url = ?", arguments: [url])
        }
    }
    
    // MARK: - Keyset Operations
    
    public func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl: String) async throws {
        let jsonString = try JSONCoding.encodeToString(keyset)
        let keysJsonString = try JSONCoding.encodeToString(keyset.keys)
        let currentTime = Timestamp.now
        
        try await dbQueue.write { db in
            // Ensure mint_info exists first to avoid foreign key constraint violation
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO mint_info (url, json, last_updated, last_accessed)
                VALUES (?, '{}', ?, ?)
                """,
                arguments: [mintUrl, currentTime, currentTime]
            )
            
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO keysets 
                (keyset_id, mint_url, unit, active, input_fee_ppk, keys_json, last_updated, last_accessed, json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    keyset.keysetID,
                    mintUrl,
                    keyset.unit,
                    keyset.active,
                    keyset.inputFeePPK,
                    keysJsonString,
                    currentTime,
                    currentTime,
                    jsonString
                ]
            )
        }
    }
    
    public func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl: String) async throws {
        let currentTime = Timestamp.now
        
        try await dbQueue.write { db in
            // Ensure mint_info exists first to avoid foreign key constraint violation
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO mint_info (url, json, last_updated, last_accessed)
                VALUES (?, '{}', ?, ?)
                """,
                arguments: [mintUrl, currentTime, currentTime]
            )
            
            for keyset in keysets {
                let jsonString = try JSONCoding.encodeToString(keyset)
                let keysJsonString = try JSONCoding.encodeToString(keyset.keys)
                
                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO keysets 
                    (keyset_id, mint_url, unit, active, input_fee_ppk, keys_json, last_updated, last_accessed, json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        keyset.keysetID,
                        mintUrl,
                        keyset.unit,
                        keyset.active,
                        keyset.inputFeePPK,
                        keysJsonString,
                        currentTime,
                        currentTime,
                        jsonString
                    ]
                )
            }
        }
    }
    
    public func getKeyset(id: String) async -> CashuSwift.Keyset? {
        do {
            return try await dbQueue.write { db in
                // Update last_accessed time
                try db.execute(
                    sql: "UPDATE keysets SET last_accessed = ? WHERE keyset_id = ?",
                    arguments: [Timestamp.now, id]
                )
                
                // Fetch the data
                if let row = try Row.fetchOne(db, sql: "SELECT json FROM keysets WHERE keyset_id = ?", arguments: [id]),
                   let jsonString = row["json"] as? String,
                   let jsonData = jsonString.data(using: .utf8) {
                    return try JSONCoding.decode(CashuSwift.Keyset.self, from: jsonData)
                }
                return nil
            }
        } catch {
            logError(operation: "get keyset", parameter: id, error: error)
            return nil
        }
    }
    
    public func getKeysets(mintUrl: String) async -> [CashuSwift.Keyset] {
        do {
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT json FROM keysets WHERE mint_url = ? ORDER BY keyset_id", arguments: [mintUrl])
                return rows.compactMap { row in
                    guard let jsonString = row["json"] as? String,
                          let jsonData = jsonString.data(using: .utf8) else { return nil }
                    return JSONCoding.safeDecode(CashuSwift.Keyset.self, from: jsonData)
                }
            }
        } catch {
            logError(operation: "get keysets for mint", parameter: mintUrl, error: error)
            return []
        }
    }
    
    public func getActiveKeysets(mintUrl: String, unit: String) async -> [CashuSwift.Keyset] {
        do {
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(
                    db, 
                    sql: "SELECT json FROM keysets WHERE mint_url = ? AND unit = ? AND active = 1 ORDER BY keyset_id", 
                    arguments: [mintUrl, unit]
                )
                return rows.compactMap { row in
                    guard let jsonString = row["json"] as? String,
                          let jsonData = jsonString.data(using: .utf8) else { return nil }
                    return JSONCoding.safeDecode(CashuSwift.Keyset.self, from: jsonData)
                }
            }
        } catch {
            logError(operation: "get active keysets", parameter: "all", error: error)
            return []
        }
    }
    
    public func areKeysetsStale(mintUrl: String, maxAge: TimeInterval = TimeConstants.hour) async -> Bool {
        let staleThreshold = Timestamp.now - Timestamp(maxAge)
        return (try? await dbQueue.read { db in
            if let oldestUpdate = try Int64.fetchOne(
                db, 
                sql: "SELECT MIN(last_updated) FROM keysets WHERE mint_url = ?", 
                arguments: [mintUrl]
            ) {
                return oldestUpdate < staleThreshold
            }
            return true // If no keysets found, consider it stale
        }) ?? true
    }
    
    public func deleteKeysets(mintUrl: String) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM keysets WHERE mint_url = ?", arguments: [mintUrl])
        }
    }
    
    // MARK: - Mint Management
    
    public func getCachedMintUrls() async -> [String] {
        do {
            return try await dbQueue.read { db in
                try String.fetchAll(db, sql: "SELECT url FROM mint_info ORDER BY url")
            }
        } catch {
            logError(operation: "get cached mint URLs", parameter: "all", error: error)
            return []
        }
    }
    
    public func deleteMint(url: String) async throws {
        try await dbQueue.write { db in
            // Keysets will be deleted automatically due to foreign key constraint
            try db.execute(sql: "DELETE FROM mint_info WHERE url = ?", arguments: [url])
        }
    }
    
    // MARK: - Cache Size Management
    
    /// Prune the cache to a maximum number of mints based on LRU
    public func pruneMintCache(maxMints: Int) async throws {
        try await dbQueue.write { [debugMode] db in
            let mintCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mint_info") ?? 0
            
            if mintCount > maxMints {
                let overflow = mintCount - maxMints
                
                // Find the oldest accessed mints to delete
                let urlsToDelete = try String.fetchAll(
                    db,
                    sql: """
                    SELECT url FROM mint_info 
                    ORDER BY last_accessed ASC 
                    LIMIT ?
                    """,
                    arguments: [overflow]
                )
                
                // Delete the mints (cascade will handle keysets)
                for url in urlsToDelete {
                    try db.execute(sql: "DELETE FROM mint_info WHERE url = ?", arguments: [url])
                }
                
                if debugMode {
                    NDKLogger.log(.info, category: .cache, "Pruned \(urlsToDelete.count) mints from cache")
                }
            }
        }
    }
    
    /// Get cache statistics
    public func getCacheStats() async -> (events: Int, profiles: Int, mints: Int, keysets: Int) {
        do {
            return try await dbQueue.read { db in
                let events = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
                let profiles = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profiles") ?? 0
                let mints = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mint_info") ?? 0
                let keysets = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM keysets") ?? 0
                return (events, profiles, mints, keysets)
            }
        } catch {
            return (0, 0, 0, 0)
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
    
    // MARK: - Cache Management
    
    public func clear() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM events")
            try db.execute(sql: "DELETE FROM tags")
            try db.execute(sql: "DELETE FROM profiles")
            try db.execute(sql: "DELETE FROM mint_info")
            try db.execute(sql: "DELETE FROM keysets")
            try db.execute(sql: "DELETE FROM decrypted_content")
        }
        // VACUUM must be run outside of a transaction
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }
    
    // MARK: - Statistics
    
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
            for (column, value) in row {
                result[column] = value
            }
            return result
        }
    }
    #endif
    
    // MARK: - Reactive Observation
    
    public func observeEvents(
        matching filter: NDKFilter,
        observer: CacheObserver
    ) async -> ObservationHandle {
        let signature = FilterSignature(from: filter)
        let weakObserver = WeakObserver(observer: observer)
        
        // Add observer to the set for this filter signature
        if observers[signature] == nil {
            observers[signature] = []
        }
        observers[signature]?.insert(weakObserver)
        
        // Deliver existing cached events that match the filter
        let existingEvents = try? await queryEvents(filter)
        if let events = existingEvents, !events.isEmpty {
            if debugMode {
                NDKLogger.log(.debug, category: .cache, "Delivering \(events.count) existing cached events to observer")
            }
            for event in events {
                await observer.handleEvent(event)
            }
        }
        
        // Return handle that removes observer when cancelled
        return ObservationHandle { [weak self] in
            await self?.removeObserver(weakObserver, for: signature)
        }
    }
    
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
            // Event was deleted before it arrived, don't save it
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
        let exists = await hasEvent(id: event.id)
        
        // Save event to database
        try await saveEvent(event)
        
        // Save relay source to database
        try await saveRelaySource(eventId: event.id, relay: relay, subscriptionId: subscriptionId)
        
        // If event is new, notify observers
        if !exists {
            await notifyObservers(of: event)
        }
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
            // Fallback to in-memory tracking
            return relaySourceTracking[eventId] ?? []
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Save relay source information to database
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
    
    // MARK: - Private Deletion Event Processing
    
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
                    } else {
                        // Event not in cache yet - we'll add to tombstone after transaction
                        // (tombstones are in-memory only, not in database)
                    }
                }
            }
            
            // Add tombstones for non-existent events outside the transaction
            // This is safe because tombstones are only in-memory
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
    
    // MARK: - Private Observer Management
    
    private func removeObserver(_ observer: WeakObserver, for signature: FilterSignature) {
        observers[signature]?.remove(observer)
        
        // Clean up empty sets
        if observers[signature]?.isEmpty == true {
            observers.removeValue(forKey: signature)
        }
    }
    
    private func notifyObservers(of event: NDKEvent) async {
        // Clean up any nil weak references
        for (signature, observerSet) in observers {
            observers[signature] = observerSet.filter { $0.observer != nil }
        }
        
        // Find all observers whose filters match this event
        for (signature, observerSet) in observers {
            // Create filter from signature to check if event matches
            var filter = NDKFilter()
            filter.kinds = signature.kinds
            filter.authors = signature.authors
            
            // Add tag filters if present
            if let tags = signature.tags {
                for (tagName, values) in tags {
                    filter.addTagFilter(tagName, values: values)
                }
            }
            
            if await eventMatchesFilter(event, filter: filter) {
                // Notify all observers for this filter
                for weakObserver in observerSet {
                    if let observer = weakObserver.observer {
                        await observer.handleEvent(event)
                    }
                }
            }
        }
    }
    
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
    
    // MARK: - Optimistic Publishing Support
    
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
                            return .optimistic // Fallback if relay_url is missing
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
                          let targetRelaysData = targetRelaysJson.data(using: .utf8),
                          let targetRelaysArray = try? JSONCoding.decode([String].self, from: targetRelaysData) else {
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
    
    // MARK: - Negentropy Support
    
    public func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        return try await dbQueue.read { db in
            var arguments = StatementArguments()
            var whereClauses: [String] = []
            var joins: [String] = []
            var tagIndex = 0
            
            // Build filter clauses using helper
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
                // Just add time range
                whereClauses.append("e.created_at >= ? AND e.created_at < ?")
                arguments += [from, to]
            }
            
            // Build final query using helper
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
            
            // Build filter clauses using helper
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
                // Just add time range
                whereClauses.append("e.created_at >= ? AND e.created_at < ?")
                arguments += [from, to]
            }
            
            // Build final query using helper
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
                
                // Initialize all IDs as false
                for id in ids {
                    result[id] = false
                }
                
                // Query in batches to avoid SQLite limits
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
            // Return empty dictionary on error
            return [:]
        }
    }
    
    // MARK: - Statistics
    
    /// Get cache statistics including total events and breakdown by kind
    public func getStatistics() async throws -> CacheStatistics {
        return try await dbQueue.read { db in
            // Get total event count
            let totalEvents = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
            
            // Get events grouped by kind
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
    
    // MARK: - Cleanup Methods
    
    /// Start periodic cleanup of nil observers and tombstones
    private func startPeriodicCleanup() async {
        while !Task.isCancelled {
            // Wait for 5 minutes between cleanups
            try? await Task.sleep(nanoseconds: UInt64(NetworkConstants.cleanupInterval * Double(TimeConstants.nanosecondsPerSecond)))
            
            await cleanupObservers()
            await cleanupTombstones()
        }
    }
    
    /// Clean up nil observers from all filter signatures
    private func cleanupObservers() async {
        var emptySignatures: [FilterSignature] = []
        
        // Clean up nil observers and track empty signatures
        for (signature, observerSet) in observers {
            let activeObservers = observerSet.filter { $0.observer != nil }
            
            if activeObservers.isEmpty {
                emptySignatures.append(signature)
            } else {
                observers[signature] = activeObservers
            }
        }
        
        // Remove empty signatures
        for signature in emptySignatures {
            observers.removeValue(forKey: signature)
        }
        
        if debugMode && !emptySignatures.isEmpty {
            NDKLogger.log(.debug, category: .cache, "Cleaned up \(emptySignatures.count) empty observer signatures")
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
    
    // MARK: - Fetch Timestamp Tracking
    
    /// Get the last fetch time for a filter
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
    
    /// Record the fetch time for a filter
    public func recordFetchTime(for filter: NDKFilter, timestamp: Date) async {
        let fingerprint = filter.fingerprint
        let timestampInt = Timestamp.from(timestamp)
        
        // Encode filter as JSON for debugging purposes
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
    
    // MARK: - NIP-05 Cache Operations
    
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
        let nip46RelaysJSON = entry.nip46Relays.flatMap { try? JSONCoding.encodeToString($0) }
        
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
                        Int64(Date().timeIntervalSince1970)
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
                    return true // No entry, needs verification
                }
                
                // Unverified always needs verification
                if status == NIP05VerificationStatus.unverified.rawValue {
                    return true
                }
                
                // Check age of last verification
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
        let rateLimitWindow: TimeInterval = TimeConstants.hour // 1 hour
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
                    return true // No rate limit entry, allow
                }
                
                // Check if window has expired
                if TimeInterval(now - windowStart) > rateLimitWindow {
                    return true // Window expired, allow
                }
                
                return attemptCount < maxAttemptsPerWindow
            }
        } catch {
            logError(operation: "check domain rate limit", parameter: domain, error: error)
            return true // Allow on error
        }
    }
    
    public func recordDomainVerificationAttempt(_ domain: String) async {
        let rateLimitWindow: TimeInterval = TimeConstants.hour // 1 hour
        let now = Timestamp.from(Date())
        
        do {
            try await dbQueue.write { db in
                // Check existing entry
                let existing = try Row.fetchOne(db, sql: """
                    SELECT attempt_count, window_start FROM nip05_rate_limit
                    WHERE domain = ?
                """, arguments: [domain])
                
                if let existing = existing,
                   let windowStart = existing["window_start"] as? Int64,
                   TimeInterval(now - windowStart) <= rateLimitWindow {
                    // Increment counter within window
                    try db.execute(sql: """
                        UPDATE nip05_rate_limit 
                        SET attempt_count = attempt_count + 1
                        WHERE domain = ?
                    """, arguments: [domain])
                } else {
                    // Start new window
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
    
    // Helper function to convert database row to NIP05CacheEntry
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
        
        // Encode relay arrays as JSON
        let writeRelaysJSON = writeRelays != nil ? try? JSONCoding.encodeToString(writeRelays!) : nil
        let readRelaysJSON = readRelays != nil ? try? JSONCoding.encodeToString(readRelays!) : nil
        let checkedRelaysJSON = checkedRelays != nil ? try? JSONCoding.encodeToString(Array(checkedRelays!)) : nil
        
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
                
                // Decode relay arrays
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
    
    deinit {
        cleanupTask?.cancel()
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