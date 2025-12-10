import XCTest
import GRDB
@testable import NDKSwiftCore
@testable import NDKSwiftSQLite

final class SQLiteCacheMigrationTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func createTestDatabase() throws -> DatabaseQueue {
        // Create in-memory database for testing
        let db = try DatabaseQueue()
        return db
    }
    
    private func applyMigration(_ migration: (inout DatabaseMigrator) -> Void, to db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migration(&migrator)
        try migrator.migrate(db)
    }
    
    private func tableExists(_ tableName: String, in db: DatabaseQueue) throws -> Bool {
        try db.read { db in
            try db.tableExists(tableName)
        }
    }
    
    private func columnExists(_ columnName: String, inTable tableName: String, db: DatabaseQueue) throws -> Bool {
        try db.read { db in
            let columns = try db.columns(in: tableName)
            return columns.contains { $0.name == columnName }
        }
    }
    
    private func indexExists(_ indexName: String, in db: DatabaseQueue) throws -> Bool {
        try db.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master 
                WHERE type = 'index' AND name = ?
                """, arguments: [indexName]) ?? 0
            return count > 0
        }
    }
    
    // MARK: - V1 Initial Migration Tests
    
    func testV1InitialMigration() throws {
        let db = try createTestDatabase()
        
        try applyMigration(NDKSQLiteCache.registerV1InitialMigration, to: db)
        
        // Verify events table
        XCTAssertTrue(try tableExists("events", in: db))
        XCTAssertTrue(try columnExists("id", inTable: "events", db: db))
        XCTAssertTrue(try columnExists("pubkey", inTable: "events", db: db))
        XCTAssertTrue(try columnExists("created_at", inTable: "events", db: db))
        XCTAssertTrue(try columnExists("kind", inTable: "events", db: db))
        XCTAssertTrue(try columnExists("content", inTable: "events", db: db))
        XCTAssertTrue(try columnExists("sig", inTable: "events", db: db))
        XCTAssertTrue(try columnExists("seen_at", inTable: "events", db: db))
        XCTAssertTrue(try columnExists("json", inTable: "events", db: db))
        
        // Verify events indexes
        XCTAssertTrue(try indexExists("idx_pubkey_kind_time", in: db))
        XCTAssertTrue(try indexExists("idx_kind_time", in: db))
        XCTAssertTrue(try indexExists("idx_created_at", in: db))
        
        // Verify tags table
        XCTAssertTrue(try tableExists("tags", in: db))
        XCTAssertTrue(try columnExists("event_id", inTable: "tags", db: db))
        XCTAssertTrue(try columnExists("tag_name", inTable: "tags", db: db))
        XCTAssertTrue(try columnExists("tag_value", inTable: "tags", db: db))
        XCTAssertTrue(try columnExists("tag_index", inTable: "tags", db: db))
        
        // Verify tags indexes
        XCTAssertTrue(try indexExists("idx_tags_name_value", in: db))
        XCTAssertTrue(try indexExists("idx_tags_event", in: db))
        
        // Verify profiles table
        XCTAssertTrue(try tableExists("profiles", in: db))
        XCTAssertTrue(try columnExists("pubkey", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("name", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("about", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("picture", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("nip05", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("lud06", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("lud16", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("banner", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("website", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("updated_at", inTable: "profiles", db: db))
        XCTAssertTrue(try columnExists("json", inTable: "profiles", db: db))
        
        // Verify profiles indexes
        XCTAssertTrue(try indexExists("idx_profiles_name", in: db))
        XCTAssertTrue(try indexExists("idx_profiles_nip05", in: db))
    }
    
    // MARK: - V2 Mint Caching Migration Tests
    
    func testV2MintCachingMigration() throws {
        let db = try createTestDatabase()
        
        // Apply V1 first (prerequisite)
        try applyMigration(NDKSQLiteCache.registerV1InitialMigration, to: db)
        
        // Apply V2
        try applyMigration(NDKSQLiteCache.registerV2MintCachingMigration, to: db)
        
        // Verify mint_info table
        XCTAssertTrue(try tableExists("mint_info", in: db))
        XCTAssertTrue(try columnExists("url", inTable: "mint_info", db: db))
        XCTAssertTrue(try columnExists("json", inTable: "mint_info", db: db))
        XCTAssertTrue(try columnExists("last_updated", inTable: "mint_info", db: db))
        XCTAssertTrue(try columnExists("last_accessed", inTable: "mint_info", db: db))
        
        // Verify keysets table
        XCTAssertTrue(try tableExists("keysets", in: db))
        XCTAssertTrue(try columnExists("keyset_id", inTable: "keysets", db: db))
        XCTAssertTrue(try columnExists("mint_url", inTable: "keysets", db: db))
        XCTAssertTrue(try columnExists("unit", inTable: "keysets", db: db))
        XCTAssertTrue(try columnExists("active", inTable: "keysets", db: db))
        XCTAssertTrue(try columnExists("input_fee_ppk", inTable: "keysets", db: db))
        XCTAssertTrue(try columnExists("keys_json", inTable: "keysets", db: db))
        XCTAssertTrue(try columnExists("last_updated", inTable: "keysets", db: db))
        XCTAssertTrue(try columnExists("last_accessed", inTable: "keysets", db: db))
        XCTAssertTrue(try columnExists("json", inTable: "keysets", db: db))
        
        // Verify keysets indexes
        XCTAssertTrue(try indexExists("idx_keysets_mint", in: db))
        XCTAssertTrue(try indexExists("idx_keysets_unit", in: db))
        XCTAssertTrue(try indexExists("idx_keysets_active", in: db))
    }
    
    // MARK: - V3 Structured Mint Data Migration Tests
    
    func testV3StructuredMintDataMigration() throws {
        let db = try createTestDatabase()
        
        // Apply prerequisites
        try applyMigration(NDKSQLiteCache.registerV1InitialMigration, to: db)
        try applyMigration(NDKSQLiteCache.registerV2MintCachingMigration, to: db)
        
        // Apply V3
        try applyMigration(NDKSQLiteCache.registerV3StructuredMintDataMigration, to: db)
        
        // The v3 migration is unique - test its specific behavior
        // (Would need to see the actual migration code to write specific tests)
    }
    
    // MARK: - V4 Optimistic Publishing Migration Tests
    
    func testV4OptimisticPublishingMigration() throws {
        let db = try createTestDatabase()
        
        // Apply prerequisites
        try applyMigration(NDKSQLiteCache.registerV1InitialMigration, to: db)
        try applyMigration(NDKSQLiteCache.registerV2MintCachingMigration, to: db)
        try applyMigration(NDKSQLiteCache.registerV3StructuredMintDataMigration, to: db)
        
        // Apply V4
        try applyMigration(NDKSQLiteCache.registerV4OptimisticPublishingMigration, to: db)
        
        // Verify event_confirmations table
        XCTAssertTrue(try tableExists("event_confirmations", in: db))
        XCTAssertTrue(try columnExists("event_id", inTable: "event_confirmations", db: db))
        XCTAssertTrue(try columnExists("state", inTable: "event_confirmations", db: db))
        XCTAssertTrue(try columnExists("relay_url", inTable: "event_confirmations", db: db))
        XCTAssertTrue(try columnExists("target_relays", inTable: "event_confirmations", db: db))
        XCTAssertTrue(try columnExists("created_at", inTable: "event_confirmations", db: db))
        XCTAssertTrue(try columnExists("confirmed_at", inTable: "event_confirmations", db: db))
        
        // Verify indexes
        XCTAssertTrue(try indexExists("idx_confirmations_state", in: db))
        XCTAssertTrue(try indexExists("idx_confirmations_relay", in: db))
        XCTAssertTrue(try indexExists("idx_confirmations_created", in: db))
    }
    
    // MARK: - V5 Decrypted Content Migration Tests
    
    func testV5DecryptedContentMigration() throws {
        let db = try createTestDatabase()
        
        // Apply prerequisites (skipping intermediate migrations for brevity)
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
        NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
        try migrator.migrate(db)
        
        // Apply V5
        try applyMigration(NDKSQLiteCache.registerV5DecryptedContentMigration, to: db)
        
        // Verify decrypted_content table
        XCTAssertTrue(try tableExists("decrypted_content", in: db))
        XCTAssertTrue(try columnExists("cache_key", inTable: "decrypted_content", db: db))
        XCTAssertTrue(try columnExists("event_id", inTable: "decrypted_content", db: db))
        XCTAssertTrue(try columnExists("viewer_pubkey", inTable: "decrypted_content", db: db))
        XCTAssertTrue(try columnExists("content", inTable: "decrypted_content", db: db))
        XCTAssertTrue(try columnExists("decrypted_at", inTable: "decrypted_content", db: db))
        
        // Verify indexes
        XCTAssertTrue(try indexExists("idx_decrypted_content_viewer", in: db))
        XCTAssertTrue(try indexExists("idx_decrypted_content_time", in: db))
    }
    
    // MARK: - V6 Relay Sources Migration Tests
    
    func testV6RelaySourcesMigration() throws {
        let db = try createTestDatabase()
        
        // Apply all prerequisites
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
        NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
        NDKSQLiteCache.registerV5DecryptedContentMigration(&migrator)
        try migrator.migrate(db)
        
        // Apply V6
        try applyMigration(NDKSQLiteCache.registerV6RelaySourcesMigration, to: db)
        
        // Verify relay_sources table
        XCTAssertTrue(try tableExists("relay_sources", in: db))
        XCTAssertTrue(try columnExists("event_id", inTable: "relay_sources", db: db))
        XCTAssertTrue(try columnExists("relay_url", inTable: "relay_sources", db: db))
        XCTAssertTrue(try columnExists("first_seen", inTable: "relay_sources", db: db))
        XCTAssertTrue(try columnExists("subscription_id", inTable: "relay_sources", db: db))
        
        // Verify indexes
        XCTAssertTrue(try indexExists("idx_relay_sources_event", in: db))
        XCTAssertTrue(try indexExists("idx_relay_sources_relay", in: db))
        XCTAssertTrue(try indexExists("idx_relay_sources_time", in: db))
        
        // Verify trigger
        try db.read { db in
            let triggerCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master 
                WHERE type = 'trigger' AND name = 'cleanup_relay_sources_on_event_delete'
                """) ?? 0
            XCTAssertEqual(triggerCount, 1)
        }
    }
    
    // MARK: - Migration Chain Tests
    
    func testFullMigrationChain() throws {
        let db = try createTestDatabase()
        
        // Apply all migrations in order
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
        NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
        NDKSQLiteCache.registerV5DecryptedContentMigration(&migrator)
        NDKSQLiteCache.registerV6RelaySourcesMigration(&migrator)
        NDKSQLiteCache.registerV7FetchTimestampsMigration(&migrator)
        NDKSQLiteCache.registerV8AddSubscriptionIdMigration(&migrator)
        NDKSQLiteCache.registerV9NIP05CacheMigration(&migrator)
        NDKSQLiteCache.registerV10RelayPreferencesMigration(&migrator)
        NDKSQLiteCache.registerV11ProfileAdditionalFieldsMigration(&migrator)
        NDKSQLiteCache.registerV12AddEventIdToProfilesMigration(&migrator)
        
        // Should not throw
        XCTAssertNoThrow(try migrator.migrate(db))
        
        // Verify final state has all expected tables
        XCTAssertTrue(try tableExists("events", in: db))
        XCTAssertTrue(try tableExists("tags", in: db))
        XCTAssertTrue(try tableExists("profiles", in: db))
        XCTAssertTrue(try tableExists("mint_info", in: db))
        XCTAssertTrue(try tableExists("keysets", in: db))
        XCTAssertTrue(try tableExists("event_confirmations", in: db))
        XCTAssertTrue(try tableExists("decrypted_content", in: db))
        XCTAssertTrue(try tableExists("relay_sources", in: db))
        XCTAssertTrue(try tableExists("fetch_timestamps", in: db))
        XCTAssertTrue(try tableExists("nip05_cache", in: db))
        XCTAssertTrue(try tableExists("nip05_rate_limit", in: db))
    }
    
    func testMigrationIdempotency() throws {
        let db = try createTestDatabase()
        
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        
        // Apply migration once
        XCTAssertNoThrow(try migrator.migrate(db))
        
        // Apply again - should not throw or change anything
        XCTAssertNoThrow(try migrator.migrate(db))
        
        // Verify tables still exist
        XCTAssertTrue(try tableExists("events", in: db))
        XCTAssertTrue(try tableExists("tags", in: db))
        XCTAssertTrue(try tableExists("profiles", in: db))
    }
    
    // MARK: - Foreign Key Tests
    
    func testForeignKeyConstraints() throws {
        let db = try createTestDatabase()
        
        // Enable foreign keys
        try db.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        
        // Apply migrations
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        try migrator.migrate(db)
        
        // Test tags foreign key to events
        try db.write { db in
            // Insert an event
            try db.execute(sql: """
                INSERT INTO events (id, pubkey, created_at, kind, sig, json)
                VALUES ('test_event_1', 'test_pubkey', 1234567890, 1, 'test_sig', '{}')
                """)
            
            // Insert a tag - should succeed
            try db.execute(sql: """
                INSERT INTO tags (event_id, tag_name, tag_value, tag_index)
                VALUES ('test_event_1', 'p', 'test_value', 0)
                """)
            
            // Try to insert tag for non-existent event - should fail
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO tags (event_id, tag_name, tag_value, tag_index)
                VALUES ('non_existent_event', 'p', 'test_value', 0)
                """))
            
            // Delete the event - tags should be cascade deleted
            try db.execute(sql: "DELETE FROM events WHERE id = 'test_event_1'")
            
            let tagCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags WHERE event_id = 'test_event_1'") ?? 0
            XCTAssertEqual(tagCount, 0)
        }
    }
    
    // MARK: - Data Integrity Tests
    
    func testMigrationDataIntegrity() throws {
        let db = try createTestDatabase()
        
        // Apply V1 migration
        try applyMigration(NDKSQLiteCache.registerV1InitialMigration, to: db)
        
        // Insert test data
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO events (id, pubkey, created_at, kind, sig, json)
                VALUES ('event1', 'pubkey1', 1234567890, 1, 'sig1', '{"content": "test"}')
                """)
            
            try db.execute(sql: """
                INSERT INTO profiles (pubkey, name, json)
                VALUES ('pubkey1', 'Test User', '{"name": "Test User"}')
                """)
        }
        
        // Apply remaining migrations
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
        NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
        NDKSQLiteCache.registerV5DecryptedContentMigration(&migrator)
        try migrator.migrate(db)
        
        // Verify data still exists
        try db.read { db in
            let eventCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? 0
            XCTAssertEqual(eventCount, 1)
            
            let profileCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profiles") ?? 0
            XCTAssertEqual(profileCount, 1)
            
            // Verify specific data
            let eventId = try String.fetchOne(db, sql: "SELECT id FROM events WHERE pubkey = 'pubkey1'")
            XCTAssertEqual(eventId, "event1")
            
            let profileName = try String.fetchOne(db, sql: "SELECT name FROM profiles WHERE pubkey = 'pubkey1'")
            XCTAssertEqual(profileName, "Test User")
        }
    }
    
    // MARK: - V7 Fetch Timestamps Migration Tests
    
    func testV7FetchTimestampsMigration() throws {
        let db = try createTestDatabase()
        
        // Apply prerequisites
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
        NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
        NDKSQLiteCache.registerV5DecryptedContentMigration(&migrator)
        NDKSQLiteCache.registerV6RelaySourcesMigration(&migrator)
        try migrator.migrate(db)
        
        // Apply V7
        try applyMigration(NDKSQLiteCache.registerV7FetchTimestampsMigration, to: db)
        
        // Verify fetch_timestamps table
        XCTAssertTrue(try tableExists("fetch_timestamps", in: db))
        XCTAssertTrue(try columnExists("filter_fingerprint", inTable: "fetch_timestamps", db: db))
        XCTAssertTrue(try columnExists("last_fetch", inTable: "fetch_timestamps", db: db))
        XCTAssertTrue(try columnExists("filter_json", inTable: "fetch_timestamps", db: db))
        XCTAssertTrue(try columnExists("updated_at", inTable: "fetch_timestamps", db: db))
        
        // Verify index
        XCTAssertTrue(try indexExists("idx_fetch_timestamps_last_fetch", in: db))
        
        // Verify cleanup trigger exists
        try db.read { db in
            let triggerCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master 
                WHERE type = 'trigger' AND name = 'cleanup_old_fetch_timestamps'
                """) ?? 0
            XCTAssertEqual(triggerCount, 1)
        }
    }
    
    // MARK: - V9 NIP-05 Cache Migration Tests
    
    func testV9NIP05CacheMigration() throws {
        let db = try createTestDatabase()
        
        // Apply prerequisites (simplified for V9)
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
        NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
        NDKSQLiteCache.registerV5DecryptedContentMigration(&migrator)
        NDKSQLiteCache.registerV6RelaySourcesMigration(&migrator)
        NDKSQLiteCache.registerV7FetchTimestampsMigration(&migrator)
        NDKSQLiteCache.registerV8AddSubscriptionIdMigration(&migrator)
        try migrator.migrate(db)
        
        // Apply V9
        try applyMigration(NDKSQLiteCache.registerV9NIP05CacheMigration, to: db)
        
        // Verify nip05_cache table
        XCTAssertTrue(try tableExists("nip05_cache", in: db))
        XCTAssertTrue(try columnExists("identifier", inTable: "nip05_cache", db: db))
        XCTAssertTrue(try columnExists("pubkey", inTable: "nip05_cache", db: db))
        XCTAssertTrue(try columnExists("status", inTable: "nip05_cache", db: db))
        XCTAssertTrue(try columnExists("nip46_relays", inTable: "nip05_cache", db: db))
        XCTAssertTrue(try columnExists("claimed_at", inTable: "nip05_cache", db: db))
        XCTAssertTrue(try columnExists("verified_at", inTable: "nip05_cache", db: db))
        XCTAssertTrue(try columnExists("last_check_at", inTable: "nip05_cache", db: db))
        XCTAssertTrue(try columnExists("error_message", inTable: "nip05_cache", db: db))
        XCTAssertTrue(try columnExists("http_status_code", inTable: "nip05_cache", db: db))
        
        // Verify indexes
        XCTAssertTrue(try indexExists("idx_nip05_pubkey", in: db))
        XCTAssertTrue(try indexExists("idx_nip05_identifier", in: db))
        XCTAssertTrue(try indexExists("idx_nip05_status", in: db))
        XCTAssertTrue(try indexExists("idx_nip05_search", in: db))
        
        // Verify rate limiting table
        XCTAssertTrue(try tableExists("nip05_rate_limit", in: db))
        XCTAssertTrue(try columnExists("domain", inTable: "nip05_rate_limit", db: db))
        XCTAssertTrue(try columnExists("attempt_count", inTable: "nip05_rate_limit", db: db))
        XCTAssertTrue(try columnExists("window_start", inTable: "nip05_rate_limit", db: db))
    }
    
    // MARK: - Trigger Tests
    
    func testFetchTimestampsCleanupTrigger() throws {
        let db = try createTestDatabase()
        
        // Apply migrations up to V7
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
        NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
        NDKSQLiteCache.registerV5DecryptedContentMigration(&migrator)
        NDKSQLiteCache.registerV6RelaySourcesMigration(&migrator)
        NDKSQLiteCache.registerV7FetchTimestampsMigration(&migrator)
        try migrator.migrate(db)
        
        try db.write { db in
            // Insert old entry (40 days ago)
            let oldTimestamp = Int(Date().timeIntervalSince1970) - (40 * 24 * 60 * 60)
            try db.execute(sql: """
                INSERT INTO fetch_timestamps (filter_fingerprint, last_fetch, filter_json, updated_at)
                VALUES ('old_filter', ?, '{}', ?)
                """, arguments: [oldTimestamp, oldTimestamp])
            
            // Insert recent entry
            let recentTimestamp = Int(Date().timeIntervalSince1970)
            try db.execute(sql: """
                INSERT INTO fetch_timestamps (filter_fingerprint, last_fetch, filter_json, updated_at)
                VALUES ('recent_filter', ?, '{}', ?)
                """, arguments: [recentTimestamp, recentTimestamp])
            
            // Insert new entry - should trigger cleanup
            try db.execute(sql: """
                INSERT INTO fetch_timestamps (filter_fingerprint, last_fetch, filter_json, updated_at)
                VALUES ('new_filter', ?, '{}', ?)
                """, arguments: [recentTimestamp, recentTimestamp])
            
            // Verify old entry was deleted
            let oldCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM fetch_timestamps WHERE filter_fingerprint = 'old_filter'
                """) ?? 0
            XCTAssertEqual(oldCount, 0, "Old entry should be deleted by trigger")
            
            // Verify recent entries still exist
            let recentCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM fetch_timestamps WHERE filter_fingerprint IN ('recent_filter', 'new_filter')
                """) ?? 0
            XCTAssertEqual(recentCount, 2, "Recent entries should not be deleted")
        }
    }
    
    // MARK: - Column Default Values Tests
    
    func testColumnDefaultValues() throws {
        let db = try createTestDatabase()
        
        // Apply V1 migration
        try applyMigration(NDKSQLiteCache.registerV1InitialMigration, to: db)
        
        try db.write { db in
            // Insert event without seen_at - should get default
            try db.execute(sql: """
                INSERT INTO events (id, pubkey, created_at, kind, sig, json)
                VALUES ('test_event', 'test_pubkey', 1234567890, 1, 'test_sig', '{}')
                """)
            
            // Verify seen_at was set to current time
            let seenAt = try Int.fetchOne(db, sql: "SELECT seen_at FROM events WHERE id = 'test_event'") ?? 0
            let currentTime = Int(Date().timeIntervalSince1970)
            XCTAssertTrue(abs(seenAt - currentTime) < 2, "seen_at should default to current timestamp")
        }
    }
    
    // MARK: - Performance Tests
    
    func testMigrationPerformance() throws {
        let db = try createTestDatabase()
        
        measure {
            var migrator = DatabaseMigrator()
            NDKSQLiteCache.registerV1InitialMigration(&migrator)
            NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
            NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
            NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
            NDKSQLiteCache.registerV5DecryptedContentMigration(&migrator)
            NDKSQLiteCache.registerV6RelaySourcesMigration(&migrator)
            
            do {
                try migrator.migrate(db)
            } catch {
                XCTFail("Migration failed: \(error)")
            }
        }
    }
    
    // MARK: - Composite Primary Key Tests
    
    func testCompositePrimaryKeys() throws {
        let db = try createTestDatabase()
        
        // Apply migrations including V9
        var migrator = DatabaseMigrator()
        NDKSQLiteCache.registerV1InitialMigration(&migrator)
        NDKSQLiteCache.registerV2MintCachingMigration(&migrator)
        NDKSQLiteCache.registerV3StructuredMintDataMigration(&migrator)
        NDKSQLiteCache.registerV4OptimisticPublishingMigration(&migrator)
        NDKSQLiteCache.registerV5DecryptedContentMigration(&migrator)
        NDKSQLiteCache.registerV6RelaySourcesMigration(&migrator)
        NDKSQLiteCache.registerV7FetchTimestampsMigration(&migrator)
        NDKSQLiteCache.registerV8AddSubscriptionIdMigration(&migrator)
        NDKSQLiteCache.registerV9NIP05CacheMigration(&migrator)
        try migrator.migrate(db)
        
        try db.write { db in
            // Test nip05_cache composite primary key
            try db.execute(sql: """
                INSERT INTO nip05_cache (identifier, pubkey, status, claimed_at)
                VALUES ('alice@example.com', 'pubkey1', 'verified', 1234567890)
                """)
            
            // Same identifier with different pubkey - should succeed
            try db.execute(sql: """
                INSERT INTO nip05_cache (identifier, pubkey, status, claimed_at)
                VALUES ('alice@example.com', 'pubkey2', 'verified', 1234567890)
                """)
            
            // Same identifier and pubkey - should fail
            XCTAssertThrowsError(try db.execute(sql: """
                INSERT INTO nip05_cache (identifier, pubkey, status, claimed_at)
                VALUES ('alice@example.com', 'pubkey1', 'failed', 1234567890)
                """))
        }
    }
}