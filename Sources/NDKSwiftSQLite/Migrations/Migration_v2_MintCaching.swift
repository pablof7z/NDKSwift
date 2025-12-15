import Foundation
import GRDB
import NDKSwiftCore

extension NDKSQLiteCache {
    static func registerV2MintCachingMigration(_ migrator: inout DatabaseMigrator) {
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
    }
}
