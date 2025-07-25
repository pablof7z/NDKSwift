import Foundation
import GRDB

extension NDKSQLiteCache {
    static func registerV1InitialMigration(_ migrator: inout DatabaseMigrator) {
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
    }
}