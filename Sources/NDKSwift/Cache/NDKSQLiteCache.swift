import Foundation

import CashuSwift
import GRDB


/// SQLite-backed cache implementation for NDKSwift
/// Provides efficient storage and querying of Nostr events with proper migration support
public actor NDKSQLiteCache: NDKCache {
    private let dbQueue: DatabaseQueue
    private let dbPath: String
    private let debugMode: Bool
    
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
    }
    
    // MARK: - Database Setup
    
    private func setupPragmas() async throws {
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA cache_size = -64000") // 64MB cache
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
        
        try migrator.migrate(dbQueue)
    }
    
    // MARK: - Event Operations (NDKCache protocol)
    
    public func saveEvent(_ event: NDKEvent) async throws {
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
            if debugMode {
                print("NDKSQLiteCache: Failed to save event \(eventId). Error: \(error)")
            }
            throw error
        }
    }
    
    public func getEvent(id: String) async -> NDKEvent? {
        do {
            return try await dbQueue.read { db in
                if let row = try Row.fetchOne(db, sql: "SELECT json FROM events WHERE id = ?", arguments: [id]),
                   let jsonString = row["json"] as? String,
                   let jsonData = jsonString.data(using: .utf8) {
                    return try JSONCoding.decode(NDKEvent.self, from: jsonData)
                }
                return nil
            }
        } catch {
            if debugMode {
                print("NDKSQLiteCache: Failed to get event \(id). Error: \(error)")
            }
            return nil
        }
    }
    
    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        print("[NDKSQLiteCache.queryEvents] Starting query with filter: ids=\(filter.ids?.joined(separator: ",") ?? "nil"), authors=\(filter.authors?.joined(separator: ",") ?? "nil"), kinds=\(filter.kinds?.map { String($0) }.joined(separator: ",") ?? "nil")")
        
        return try await dbQueue.read { db in
            print("[NDKSQLiteCache.queryEvents] Inside dbQueue.read block")
            var sql = "SELECT DISTINCT e.json FROM events e"
            var arguments = StatementArguments()
            var whereClauses: [String] = []
            var joins: [String] = []
            var tagIndex = 0
            
            // Build WHERE clauses
            
            // IDs filter
            if let ids = filter.ids, !ids.isEmpty {
                print("[NDKSQLiteCache.queryEvents] Adding IDs filter for \(ids.count) IDs")
                let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
                whereClauses.append("e.id IN (\(placeholders))")
                for id in ids {
                    arguments += [id]
                }
            }
            
            // Authors filter
            if let authors = filter.authors, !authors.isEmpty {
                print("[NDKSQLiteCache.queryEvents] Adding authors filter for \(authors.count) authors")
                let placeholders = authors.map { _ in "?" }.joined(separator: ", ")
                whereClauses.append("e.pubkey IN (\(placeholders))")
                for author in authors {
                    arguments += [author]
                }
            }
            
            // Kinds filter
            if let kinds = filter.kinds, !kinds.isEmpty {
                let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
                whereClauses.append("e.kind IN (\(placeholders))")
                for kind in kinds {
                    arguments += [kind]
                }
            }
            
            // Time filters
            if let since = filter.since {
                whereClauses.append("e.created_at >= ?")
                arguments += [since]
            }
            
            if let until = filter.until {
                whereClauses.append("e.created_at <= ?")
                arguments += [until]
            }
            
            // Tag filters
            if let tags = filter.tags {
                for (tagName, tagValues) in tags {
                    if !tagValues.isEmpty {
                        let alias = "t\(tagIndex)"
                        joins.append("JOIN tags \(alias) ON e.id = \(alias).event_id")
                        
                        let placeholders = tagValues.map { _ in "?" }.joined(separator: ", ")
                        whereClauses.append("\(alias).tag_name = ? AND \(alias).tag_value IN (\(placeholders))")
                        
                        arguments += [tagName]
                        for value in tagValues {
                            arguments += [value]
                        }
                        
                        tagIndex += 1
                    }
                }
            }
            
            // Build final query
            if !joins.isEmpty {
                sql += " " + joins.joined(separator: " ")
            }
            
            if !whereClauses.isEmpty {
                sql += " WHERE " + whereClauses.joined(separator: " AND ")
            }
            
            sql += " ORDER BY e.created_at DESC"
            
            if let limit = filter.limit, limit > 0 {
                sql += " LIMIT \(limit)"
            }
            
            // Execute query
            print("[NDKSQLiteCache.queryEvents] Executing SQL: \(sql)")
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            print("[NDKSQLiteCache.queryEvents] Query returned \(rows.count) rows")
            
            let events: [NDKEvent] = rows.compactMap { row in
                guard let jsonString = row["json"] as? String,
                      let jsonData = jsonString.data(using: .utf8) else { return nil }
                return JSONCoding.safeDecode(NDKEvent.self, from: jsonData)
            }
            
            print("[NDKSQLiteCache.queryEvents] Decoded \(events.count) events")
            print("[NDKSQLiteCache.queryEvents] Exiting dbQueue.read block")
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
        let jsonString = try JSONCoding.encodeToString(profile)
        
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO profiles 
                (pubkey, name, about, picture, nip05, lud06, lud16, banner, website, updated_at, json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    pubkey,
                    profile.name,
                    profile.about,
                    profile.picture,
                    profile.nip05,
                    profile.lud06,
                    profile.lud16,
                    profile.banner,
                    profile.website,
                    Int64(Date().timeIntervalSince1970),
                    jsonString
                ]
            )
        }
    }
    
    public func getProfile(pubkey: String) async -> NDKUserProfile? {
        do {
            return try await dbQueue.read { db in
                if let row = try Row.fetchOne(db, sql: "SELECT json FROM profiles WHERE pubkey = ?", arguments: [pubkey]),
                   let jsonString = row["json"] as? String,
                   let jsonData = jsonString.data(using: .utf8) {
                    return try JSONCoding.decode(NDKUserProfile.self, from: jsonData)
                }
                return nil
            }
        } catch {
            if debugMode {
                print("NDKSQLiteCache: Failed to get profile \(pubkey). Error: \(error)")
            }
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
            if debugMode {
                print("NDKSQLiteCache: Failed to search profiles. Error: \(error)")
            }
            return []
        }
    }
    
    // MARK: - Mint Operations (MintCache protocol)
    
    public func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        let jsonString = try JSONCoding.encodeToString(info)
        let currentTime = Int64(Date().timeIntervalSince1970)
        
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
                    arguments: [Int64(Date().timeIntervalSince1970), url]
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
            if debugMode {
                print("NDKSQLiteCache: Failed to get mint info \(url). Error: \(error)")
            }
            return nil
        }
    }
    
    public func isMintInfoStale(url: String, maxAge: TimeInterval = 86400) async -> Bool {
        let staleThreshold = Int64(Date().timeIntervalSince1970 - maxAge)
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
        let currentTime = Int64(Date().timeIntervalSince1970)
        
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
        let currentTime = Int64(Date().timeIntervalSince1970)
        
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
                    arguments: [Int64(Date().timeIntervalSince1970), id]
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
            if debugMode {
                print("NDKSQLiteCache: Failed to get keyset \(id). Error: \(error)")
            }
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
            if debugMode {
                print("NDKSQLiteCache: Failed to get keysets for mint \(mintUrl). Error: \(error)")
            }
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
            if debugMode {
                print("NDKSQLiteCache: Failed to get active keysets. Error: \(error)")
            }
            return []
        }
    }
    
    public func areKeysetsStale(mintUrl: String, maxAge: TimeInterval = 3600) async -> Bool {
        let staleThreshold = Int64(Date().timeIntervalSince1970 - maxAge)
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
            if debugMode {
                print("NDKSQLiteCache: Failed to get cached mint URLs. Error: \(error)")
            }
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
        try await dbQueue.write { db in
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
                
                if self.debugMode {
                    print("NDKSQLiteCache: Pruned \(urlsToDelete.count) mints from cache")
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
                print("[NDKSQLiteCache] Error fetching decrypted content for \(eventId): \(error)")
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
                print("[NDKSQLiteCache] Stored decrypted content for event \(eventId) viewer \(viewerPubkey)")
            }
        } catch {
            if debugMode {
                print("[NDKSQLiteCache] Error storing decrypted content for \(eventId): \(error)")
            }
        }
    }
    
    public func clearDecryptedContent() async {
        do {
            try await dbQueue.write { db in
                try db.execute(sql: "DELETE FROM decrypted_content")
            }
            if debugMode {
                print("[NDKSQLiteCache] Cleared all decrypted content")
            }
        } catch {
            if debugMode {
                print("[NDKSQLiteCache] Error clearing decrypted content: \(error)")
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
                print("[NDKSQLiteCache] Cleared decrypted content for viewer \(viewerPubkey)")
            }
        } catch {
            if debugMode {
                print("[NDKSQLiteCache] Error clearing decrypted content for viewer: \(error)")
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
    
    // MARK: - Optimistic Publishing Support
    
    public func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        let eventId = event.id
        let targetRelaysJson = try JSONCoding.encodeToString(Array(relays))
        let currentTime = Int64(Date().timeIntervalSince1970)
        
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
        let confirmedTime = Int64(Date().timeIntervalSince1970)
        
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
            if debugMode {
                print("NDKSQLiteCache: Failed to get confirmation state for \(eventId). Error: \(error)")
            }
            return nil
        }
    }
    
    public func getUnpublishedEvents(maxAge: TimeInterval = 3600, limit: Int? = nil) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        let cutoffTime = Int64(Date().timeIntervalSince1970 - maxAge)
        
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
                          let targetRelaysArray = try? JSONDecoder().decode([String].self, from: targetRelaysData) else {
                        return nil
                    }
                    
                    return (event: event, targetRelays: Set(targetRelaysArray))
                }
            }
        } catch {
            if debugMode {
                print("NDKSQLiteCache: Failed to get unpublished events. Error: \(error)")
            }
            return []
        }
    }
    
    // MARK: - Negentropy Support
    
    public func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        return try await dbQueue.read { db in
            var sql = "SELECT DISTINCT e.json FROM events e"
            var arguments = StatementArguments()
            var whereClauses: [String] = []
            var joins: [String] = []
            var tagIndex = 0
            
            // Time range
            whereClauses.append("e.created_at >= ? AND e.created_at < ?")
            arguments += [from, to]
            
            // Apply additional filter conditions if provided
            if let filter = filter {
                // Authors filter
                if let authors = filter.authors, !authors.isEmpty {
                    let placeholders = authors.map { _ in "?" }.joined(separator: ", ")
                    whereClauses.append("e.pubkey IN (\(placeholders))")
                    for author in authors {
                        arguments += [author]
                    }
                }
                
                // Kinds filter
                if let kinds = filter.kinds, !kinds.isEmpty {
                    let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
                    whereClauses.append("e.kind IN (\(placeholders))")
                    for kind in kinds {
                        arguments += [kind]
                    }
                }
                
                // Tag filters
                if let tags = filter.tags {
                    for (tagName, tagValues) in tags {
                        if !tagValues.isEmpty {
                            let alias = "t\(tagIndex)"
                            joins.append("JOIN tags \(alias) ON e.id = \(alias).event_id")
                            
                            let placeholders = tagValues.map { _ in "?" }.joined(separator: ", ")
                            whereClauses.append("\(alias).tag_name = ? AND \(alias).tag_value IN (\(placeholders))")
                            
                            arguments += [tagName]
                            for value in tagValues {
                                arguments += [value]
                            }
                            
                            tagIndex += 1
                        }
                    }
                }
            }
            
            // Build final query
            if !joins.isEmpty {
                sql += " " + joins.joined(separator: " ")
            }
            
            if !whereClauses.isEmpty {
                sql += " WHERE " + whereClauses.joined(separator: " AND ")
            }
            
            sql += " ORDER BY e.created_at ASC"
            
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
            var sql = "SELECT DISTINCT e.id, e.created_at FROM events e"
            var arguments = StatementArguments()
            var whereClauses: [String] = []
            var joins: [String] = []
            var tagIndex = 0
            
            // Time range
            whereClauses.append("e.created_at >= ? AND e.created_at < ?")
            arguments += [from, to]
            
            // Apply additional filter conditions if provided
            if let filter = filter {
                // Authors filter
                if let authors = filter.authors, !authors.isEmpty {
                    let placeholders = authors.map { _ in "?" }.joined(separator: ", ")
                    whereClauses.append("e.pubkey IN (\(placeholders))")
                    for author in authors {
                        arguments += [author]
                    }
                }
                
                // Kinds filter
                if let kinds = filter.kinds, !kinds.isEmpty {
                    let placeholders = kinds.map { _ in "?" }.joined(separator: ", ")
                    whereClauses.append("e.kind IN (\(placeholders))")
                    for kind in kinds {
                        arguments += [kind]
                    }
                }
                
                // Tag filters
                if let tags = filter.tags {
                    for (tagName, tagValues) in tags {
                        if !tagValues.isEmpty {
                            let alias = "t\(tagIndex)"
                            joins.append("JOIN tags \(alias) ON e.id = \(alias).event_id")
                            
                            let placeholders = tagValues.map { _ in "?" }.joined(separator: ", ")
                            whereClauses.append("\(alias).tag_name = ? AND \(alias).tag_value IN (\(placeholders))")
                            
                            arguments += [tagName]
                            for value in tagValues {
                                arguments += [value]
                            }
                            
                            tagIndex += 1
                        }
                    }
                }
            }
            
            // Build final query
            if !joins.isEmpty {
                sql += " " + joins.joined(separator: " ")
            }
            
            if !whereClauses.isEmpty {
                sql += " WHERE " + whereClauses.joined(separator: " AND ")
            }
            
            sql += " ORDER BY e.created_at ASC"
            
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
                
                // Query in batches of 100 to avoid SQLite limits
                let batchSize = 100
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
            if debugMode {
                print("NDKSQLiteCache: Failed to check event existence. Error: \(error)")
            }
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