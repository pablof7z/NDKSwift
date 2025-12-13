import Foundation
import GRDB
import NDKSwiftCore

extension NDKSQLiteCache {
    static func registerV5DecryptedContentMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5-decrypted-content") { db in
            // Create decrypted_content table with composite key
            try db.create(table: "decrypted_content") { t in
                t.column("cache_key", .text).primaryKey() // Format: "eventId:viewerPubkey"
                t.column("event_id", .text).notNull()
                t.column("viewer_pubkey", .text).notNull()
                t.column("content", .text).notNull()
                t.column("decrypted_at", .integer).notNull().defaults(sql: "(CAST(strftime('%s', 'now') AS INTEGER))")
            }

            // Create indexes for efficient lookups and cleanup
            try db.create(index: "idx_decrypted_content_viewer", on: "decrypted_content", columns: ["viewer_pubkey"])
            try db.create(index: "idx_decrypted_content_time", on: "decrypted_content", columns: ["decrypted_at"])
        }
    }
}
