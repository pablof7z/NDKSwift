import Foundation
import GRDB

/// SQLite-backed cache implementation for NDKSwift
/// Provides efficient storage and querying of Nostr events
public actor NDKSQLiteCache: NDKCache {
    private let dbQueue: DatabaseQueue
    private let dbPath: String
    
    /// Initialize SQLite cache with optional custom path
    public init(path: String? = nil) async throws {
        if let customPath = path {
            self.dbPath = customPath
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.dbPath = documentsPath.appendingPathComponent("ndk_cache.db").path
        }
        
        self.dbQueue = try DatabaseQueue(path: dbPath)
        try await setupDatabase()
    }
    
    // MARK: - Database Setup
    
    private func setupDatabase() async throws {
        // Set pragmas outside of transaction
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA cache_size = -64000") // 64MB cache
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        
        try await dbQueue.write { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            
            // Create events table
            try db.create(table: "events", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("pubkey", .text).notNull()
                t.column("created_at", .integer).notNull()
                t.column("kind", .integer).notNull()
                t.column("content", .text)
                t.column("sig", .text).notNull()
                t.column("seen_at", .integer).defaults(sql: "(strftime('%s', 'now'))")
                t.column("json", .text).notNull()
            }
            
            // Create indexes
            try db.create(index: "idx_pubkey_kind_time", on: "events", columns: ["pubkey", "kind", "created_at"], ifNotExists: true)
            try db.create(index: "idx_kind_time", on: "events", columns: ["kind", "created_at"], ifNotExists: true)
            try db.create(index: "idx_created_at", on: "events", columns: ["created_at"], ifNotExists: true)
            
            // Create tags table
            try db.create(table: "tags", ifNotExists: true) { t in
                t.column("event_id", .text).notNull().references("events", onDelete: .cascade)
                t.column("tag_name", .text).notNull()
                t.column("tag_value", .text).notNull()
                t.column("tag_index", .integer).notNull()
            }
            
            // Create tag indexes
            try db.create(index: "idx_tags_name_value", on: "tags", columns: ["tag_name", "tag_value"], ifNotExists: true)
            try db.create(index: "idx_tags_event", on: "tags", columns: ["event_id"], ifNotExists: true)
            
            // Create profiles table
            try db.create(table: "profiles", ifNotExists: true) { t in
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
            
            // Create profile indexes for common searches
            try db.create(index: "idx_profiles_name", on: "profiles", columns: ["name"], ifNotExists: true)
            try db.create(index: "idx_profiles_nip05", on: "profiles", columns: ["nip05"], ifNotExists: true)
        }
    }
    
    // MARK: - Event Operations
    
    public func saveEvent(_ event: NDKEvent) async throws {
        guard let eventId = event.id else {
            throw NDKError.invalidEventID("Event has no ID")
        }
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(event)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        try await dbQueue.write { db in
            // Insert or replace event
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO events (id, pubkey, created_at, kind, content, sig, json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    eventId,
                    event.pubkey,
                    event.createdAt,
                    event.kind,
                    event.content,
                    event.sig ?? "",
                    jsonString
                ]
            )
            
            // Save tags
            try db.execute(sql: "DELETE FROM tags WHERE event_id = ?", arguments: [eventId])
            
            for (index, tag) in event.tags.enumerated() {
                guard tag.count >= 2 else { continue }
                
                try db.execute(
                    sql: "INSERT INTO tags (event_id, tag_name, tag_value, tag_index) VALUES (?, ?, ?, ?)",
                    arguments: [eventId, tag[0], tag[1], index]
                )
            }
        }
    }
    
    public func getEvent(id: String) async -> NDKEvent? {
        return try? await dbQueue.read { db in
            if let row = try Row.fetchOne(db, sql: "SELECT json FROM events WHERE id = ?", arguments: [id]),
               let jsonString = row["json"] as? String,
               let jsonData = jsonString.data(using: .utf8) {
                return try JSONDecoder().decode(NDKEvent.self, from: jsonData)
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
                    return try? JSONDecoder().decode(NDKEvent.self, from: jsonData)
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
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(profile)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
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
        return try? await dbQueue.read { db in
            if let row = try Row.fetchOne(db, sql: "SELECT json FROM profiles WHERE pubkey = ?", arguments: [pubkey]),
               let jsonString = row["json"] as? String,
               let jsonData = jsonString.data(using: .utf8) {
                return try JSONDecoder().decode(NDKUserProfile.self, from: jsonData)
            }
            return nil
        }
    }
    
    // MARK: - Performance-optimized profile methods
    
    /// Get just the profile name without deserializing the entire profile
    public func getProfileName(pubkey: String) async -> String? {
        return try? await dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM profiles WHERE pubkey = ?", arguments: [pubkey])
        }
    }
    
    /// Get profile picture URL without deserializing the entire profile
    public func getProfilePicture(pubkey: String) async -> String? {
        return try? await dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT picture FROM profiles WHERE pubkey = ?", arguments: [pubkey])
        }
    }
    
    /// Search profiles by name (useful for NIP-50 style searches)
    public func searchProfiles(nameContains: String, limit: Int = 50) async -> [(pubkey: String, name: String)] {
        return (try? await dbQueue.read { db in
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
        }) ?? []
    }
    
    // MARK: - Cache Management
    
    public func clear() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM events")
            try db.execute(sql: "DELETE FROM tags")
            try db.execute(sql: "DELETE FROM profiles")
        }
        // VACUUM must be run outside of a transaction
        try await dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }
    
    // MARK: - Statistics (optional helpers)
    
    public func eventCount() async -> Int {
        return (try? await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
        }) ?? 0
    }
    
    public func profileCount() async -> Int {
        return (try? await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profiles") ?? 0
        }) ?? 0
    }
}