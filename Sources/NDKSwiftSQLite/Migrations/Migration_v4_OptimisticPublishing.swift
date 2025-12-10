import Foundation
import NDKSwiftCore
import GRDB

extension NDKSQLiteCache {
    static func registerV4OptimisticPublishingMigration(_ migrator: inout DatabaseMigrator) {
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
    }
}