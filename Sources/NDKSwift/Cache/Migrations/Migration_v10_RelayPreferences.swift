import Foundation
import GRDB

extension NDKSQLiteCache {
    static func registerV10RelayPreferencesMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v10-relay-preferences") { db in
            // Create relay_preferences table
            try db.create(table: "relay_preferences", ifNotExists: true) { t in
                t.column("pubkey", .text).primaryKey()
                t.column("write_relays", .text)      // JSON array of write relay URLs
                t.column("read_relays", .text)       // JSON array of read relay URLs
                t.column("fetched_at", .integer).notNull()
                t.column("expires_at", .integer).notNull()
                t.column("checked_relays", .text)    // JSON array of relays that sent EOSE (for negative cache)
            }

            // Create index on expires_at for efficient cleanup
            try db.create(index: "idx_relay_preferences_expires_at",
                          on: "relay_preferences",
                          columns: ["expires_at"],
                          ifNotExists: true)
        }
    }
}