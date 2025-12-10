import GRDB

extension NDKSQLiteCache {
    static func registerV13KeyValueStoreMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v13_key_value_store") { db in
            // Create generic key-value store table
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS key_value_store (
                    namespace TEXT NOT NULL,
                    key TEXT NOT NULL,
                    value BLOB NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (namespace, key)
                )
            """)

            // Create index for prefix queries
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_kv_namespace ON key_value_store(namespace)
            """)
        }
    }
}
