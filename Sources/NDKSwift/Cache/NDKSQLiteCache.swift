import Foundation
import GRDB
import CashuSwift


/// SQLite-backed cache implementation for NDKSwift
/// Provides efficient storage and querying of Nostr events with proper migration support
public actor NDKSQLiteCache: NDKCache, MintCache {
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
        
        // v1: Initial schema - events and profiles
        migrator.registerMigration("v1-initial") { db in
            // Create events table
            try db.create(table: "events") { t in
                t.column("id", .text).primaryKey()
                t.column("pubkey", .text).notNull()
                t.column("created_at", .integer).notNull()
                t.column("kind", .integer).notNull()
                t.column("content", .text)
                t.column("sig", .text).notNull()
                t.column("seen_at", .integer).defaults(sql: "(CAST(strftime('%s', 'now') AS INTEGER))")
                t.column("json", .text).notNull()
            }
            
            // Create indexes
            try db.create(index: "idx_pubkey_kind_time", on: "events", columns: ["pubkey", "kind", "created_at"])
            try db.create(index: "idx_kind_time", on: "events", columns: ["kind", "created_at"])
            try db.create(index: "idx_created_at", on: "events", columns: ["created_at"])
            
            // Create tags table
            try db.create(table: "tags") { t in
                t.column("event_id", .text).notNull().references("events", onDelete: .cascade)
                t.column("tag_name", .text).notNull()
                t.column("tag_value", .text).notNull()
                t.column("tag_index", .integer).notNull()
            }
            
            // Create tag indexes
            try db.create(index: "idx_tags_name_value", on: "tags", columns: ["tag_name", "tag_value"])
            try db.create(index: "idx_tags_event", on: "tags", columns: ["event_id"])
            
            // Create profiles table
            try db.create(table: "profiles") { t in
                t.column("pubkey", .text).primaryKey()
                t.column("name", .text)
                t.column("about", .text)
                t.column("picture", .text)
                t.column("nip05", .text)
                t.column("lud06", .text)
                t.column("lud16", .text)
                t.column("banner", .text)
                t.column("website", .text)
                t.column("updated_at", .integer)
                t.column("json", .text).notNull()
            }
            
            // Create profile indexes
            try db.create(index: "idx_profiles_name", on: "profiles", columns: ["name"])
            try db.create(index: "idx_profiles_nip05", on: "profiles", columns: ["nip05"])
        }
        
        // v2: Add mint caching with JSON storage
        migrator.registerMigration("v2-mint-caching-json") { db in
            // Create mint_info table with JSON storage
            try db.create(table: "mint_info") { t in
                t.column("url", .text).primaryKey()
                t.column("json", .text).notNull()
                t.column("last_updated", .integer).notNull()
                t.column("last_accessed", .integer).notNull()
            }
            
            // Create keysets table
            try db.create(table: "keysets") { t in
                t.column("keyset_id", .text).primaryKey()
                t.column("mint_url", .text).notNull().references("mint_info", column: "url", onDelete: .cascade)
                t.column("unit", .text).notNull()
                t.column("active", .boolean).defaults(to: true)
                t.column("input_fee_ppk", .integer).defaults(to: 0)
                t.column("keys_json", .text).notNull()
                t.column("last_updated", .integer).notNull()
                t.column("last_accessed", .integer).notNull()
                t.column("json", .text).notNull()
            }
            
            // Create indexes for keysets
            try db.create(index: "idx_keysets_mint", on: "keysets", columns: ["mint_url"])
            try db.create(index: "idx_keysets_unit", on: "keysets", columns: ["unit"])
            try db.create(index: "idx_keysets_active", on: "keysets", columns: ["active"])
        }
        
        // v3: Add structured mint data columns for better querying
        migrator.registerMigration("v3-structured-mint-data") { db in
            // Add structured columns to mint_info
            try db.alter(table: "mint_info") { t in
                t.add(column: "name", .text)
                t.add(column: "pubkey", .text)
                t.add(column: "version", .text)
                t.add(column: "units", .text) // JSON array of supported units
            }
            
            // Create index for mint name searches
            try db.create(index: "idx_mint_info_name", on: "mint_info", columns: ["name"])
            
            // Migrate existing JSON data to structured columns
            let cursor = try Row.fetchCursor(db, sql: "SELECT url, json FROM mint_info")
            while let row = try cursor.next() {
                if let url = row["url"] as? String,
                   let jsonString = row["json"] as? String,
                   let jsonData = jsonString.data(using: .utf8),
                   let info = try? JSONDecoder().decode(NDKMintInfo.self, from: jsonData) {
                    
                    let unitsJson = (try? JSONEncoder().encode(info.nuts?.nut04?.methods?.map { $0.unit } ?? [])) ?? Data()
                    let unitsString = String(data: unitsJson, encoding: .utf8)
                    
                    try db.execute(
                        sql: """
                        UPDATE mint_info 
                        SET name = ?, pubkey = ?, version = ?, units = ?
                        WHERE url = ?
                        """,
                        arguments: [info.name, info.pubkey, info.version, unitsString, url]
                    )
                }
            }
        }
        
        // v4: Add optimistic publishing support
        migrator.registerMigration("v4-optimistic-publishing") { db in
            // Create event_confirmations table to track optimistic publishing states
            try db.create(table: "event_confirmations") { t in
                t.column("event_id", .text).primaryKey().references("events", onDelete: .cascade)
                t.column("state", .text).notNull() // "optimistic" or "confirmed"
                t.column("relay_url", .text) // null for optimistic, relay URL for confirmed
                t.column("target_relays", .text) // JSON array of target relay URLs
                t.column("created_at", .integer).notNull().defaults(sql: "(CAST(strftime('%s', 'now') AS INTEGER))")
                t.column("confirmed_at", .integer) // null until confirmed
            }
            
            // Create indexes for efficient querying
            try db.create(index: "idx_confirmations_state", on: "event_confirmations", columns: ["state"])
            try db.create(index: "idx_confirmations_relay", on: "event_confirmations", columns: ["relay_url"])
            try db.create(index: "idx_confirmations_created", on: "event_confirmations", columns: ["created_at"])
        }
        
        // v5: Add decrypted content caching
        migrator.registerMigration("v5-decrypted-content") { db in
            // Create decrypted_content table
            try db.create(table: "decrypted_content") { t in
                t.column("event_id", .text).primaryKey()
                t.column("content", .text).notNull()
                t.column("decrypted_at", .integer).notNull().defaults(sql: "(CAST(strftime('%s', 'now') AS INTEGER))")
            }
            
            // Create index on decrypted_at for potential age-based cleanup
            try db.create(index: "idx_decrypted_content_time", on: "decrypted_content", columns: ["decrypted_at"])
        }
        
        try await migrator.migrate(dbQueue)
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
        return try await dbQueue.read { db in
            var sql = "SELECT DISTINCT e.json FROM events e"
            var arguments = StatementArguments()
            var whereClauses: [String] = []
            var joins: [String] = []
            var tagIndex = 0
            
            // Build WHERE clauses
            
            // IDs filter
            if let ids = filter.ids, !ids.isEmpty {
                let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
                whereClauses.append("e.id IN (\(placeholders))")
                for id in ids {
                    arguments += [id]
                }
            }
            
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
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            
            return rows.compactMap { row in
                guard let jsonString = row["json"] as? String,
                      let jsonData = jsonString.data(using: .utf8) else { return nil }
                return JSONCoding.safeDecode(NDKEvent.self, from: jsonData)
            }
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
    
    public func getDecryptedContent(for eventId: String) async -> String? {
        do {
            return try await dbQueue.read { db in
                try String.fetchOne(db, sql: "SELECT content FROM decrypted_content WHERE event_id = ?", arguments: [eventId])
            }
        } catch {
            if debugMode {
                print("[NDKSQLiteCache] Error fetching decrypted content for \(eventId): \(error)")
            }
            return nil
        }
    }
    
    public func storeDecryptedContent(_ content: String, for eventId: String) async {
        do {
            try await dbQueue.write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO decrypted_content (event_id, content) VALUES (?, ?)",
                    arguments: [eventId, content]
                )
            }
            if debugMode {
                print("[NDKSQLiteCache] Stored decrypted content for event \(eventId)")
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
}