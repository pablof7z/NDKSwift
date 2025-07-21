import Foundation
import GRDB

extension NDKSQLiteCache {
    static func registerV9NIP05CacheMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v9-nip05-cache") { db in
            // Create NIP-05 cache table
            try db.create(table: "nip05_cache", ifNotExists: true) { t in
                t.column("identifier", .text).notNull()
                t.column("pubkey", .text).notNull()
                t.column("status", .text).notNull()
                t.column("nip46_relays", .text)
                t.column("claimed_at", .integer).notNull()
                t.column("verified_at", .integer)
                t.column("last_check_at", .integer)
                t.column("error_message", .text)
                t.column("http_status_code", .integer)
                t.primaryKey(["identifier", "pubkey"])
            }
            
            // Create indexes for efficient queries
            try db.create(index: "idx_nip05_pubkey", 
                         on: "nip05_cache", 
                         columns: ["pubkey"], 
                         ifNotExists: true)
            
            try db.create(index: "idx_nip05_identifier", 
                         on: "nip05_cache", 
                         columns: ["identifier"], 
                         ifNotExists: true)
            
            try db.create(index: "idx_nip05_status", 
                         on: "nip05_cache", 
                         columns: ["status"], 
                         ifNotExists: true)
            
            // Case-insensitive search index for autocomplete
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_nip05_search ON nip05_cache(identifier COLLATE NOCASE)")
            
            // Create rate limiting table
            try db.create(table: "nip05_rate_limit", ifNotExists: true) { t in
                t.column("domain", .text).primaryKey()
                t.column("attempt_count", .integer).notNull().defaults(to: 0)
                t.column("window_start", .integer).notNull()
            }
        }
    }
}