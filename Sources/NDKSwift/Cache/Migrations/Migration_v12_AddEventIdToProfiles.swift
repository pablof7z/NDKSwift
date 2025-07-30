import GRDB

extension NDKSQLiteCache {
    static func registerV12AddEventIdToProfilesMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v12-add-event-id-to-profiles") { db in
            // Add event_id column to profiles table to track which event this profile data came from
            try db.alter(table: "profiles") { t in
                t.add(column: "event_id", .text)
            }
            
            // Create index on event_id for faster lookups
            try db.create(index: "idx_profiles_event_id", on: "profiles", columns: ["event_id"])
        }
    }
}