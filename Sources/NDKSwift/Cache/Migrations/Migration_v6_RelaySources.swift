import Foundation
import GRDB

extension NDKSQLiteCache {
    static func registerV6RelaySourcesMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v6-relay-sources") { db in
            // Create relay_sources table to track which relays provided each event
            try db.create(table: "relay_sources") { t in
                t.column("event_id", .text).notNull()
                t.column("relay_url", .text).notNull()
                t.column("first_seen", .integer).notNull().defaults(sql: "(CAST(strftime('%s', 'now') AS INTEGER))")
                t.column("subscription_id", .text) // Track which subscription received this event
                
                // Composite primary key ensures one entry per event-relay pair
                t.primaryKey(["event_id", "relay_url"])
            }
            
            // Create indexes for efficient queries
            try db.create(index: "idx_relay_sources_event", on: "relay_sources", columns: ["event_id"])
            try db.create(index: "idx_relay_sources_relay", on: "relay_sources", columns: ["relay_url"])
            try db.create(index: "idx_relay_sources_time", on: "relay_sources", columns: ["first_seen"])
            
            // Foreign key to events table (cascade delete when event is deleted)
            try db.execute(sql: """
                CREATE TRIGGER cleanup_relay_sources_on_event_delete
                AFTER DELETE ON events
                FOR EACH ROW
                BEGIN
                    DELETE FROM relay_sources WHERE event_id = OLD.id;
                END;
            """)
        }
    }
}