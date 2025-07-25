import Foundation
import GRDB

extension NDKSQLiteCache {
    static func registerV7FetchTimestampsMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7-fetch-timestamps") { db in
            // Create fetch_timestamps table to track when filters were last fetched
            try db.create(table: "fetch_timestamps") { t in
                t.column("filter_fingerprint", .text).primaryKey()
                t.column("last_fetch", .integer).notNull()
                t.column("filter_json", .text).notNull() // Store filter for debugging

                // Auto-update timestamp on row update
                t.column("updated_at", .integer).notNull().defaults(sql: "(CAST(strftime('%s', 'now') AS INTEGER))")
            }

            // Create index for efficient timestamp queries
            try db.create(index: "idx_fetch_timestamps_last_fetch", on: "fetch_timestamps", columns: ["last_fetch"])

            // Create cleanup trigger to remove old entries (older than 30 days)
            let cleanupThresholdSeconds = Int(TimeConstants.day * 30) // 30 days
            try db.execute(sql: """
                CREATE TRIGGER cleanup_old_fetch_timestamps
                AFTER INSERT ON fetch_timestamps
                FOR EACH ROW
                BEGIN
                    DELETE FROM fetch_timestamps
                    WHERE last_fetch < (CAST(strftime('%s', 'now') AS INTEGER) - \(cleanupThresholdSeconds));
                END;
            """)
        }
    }
}