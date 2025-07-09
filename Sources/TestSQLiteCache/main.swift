import Foundation
import NDKSwift

/// E2E test demonstrating SQLite cache functionality
/// Tests all major cache operations: save, retrieve, query, delete
@main
struct TestSQLiteCache {
    static func main() async {
        print("🧪 Starting SQLite Cache E2E Test")
        print("=" * 50)
        
        do {
            // Create a temporary cache for testing
            let tempDir = FileManager.default.temporaryDirectory
            let dbPath = tempDir.appendingPathComponent("test_cache_\(UUID().uuidString).db").path
            
            print("📁 Creating SQLite cache at: \(dbPath)")
            let cache = try await NDKSQLiteCache(path: dbPath)
            
            // Create test signer
            let signer = try NDKPrivateKeySigner.generate()
            let pubkey = try await signer.pubkey
            
            print("\n👤 Created test identity: \(String(pubkey.prefix(16)))...")
            
            // Initialize NDK with the cache
            let ndk = NDK(signer: signer, cache: cache)
            
            // Test 1: Save and retrieve events
            print("\n📝 Test 1: Save and Retrieve Events")
            print("-" * 40)
            
            // Create some test events
            var events: [NDKEvent] = []
            for i in 1...5 {
                let event = NDKEvent(
                    pubkey: pubkey,
                    kind: 1,
                    content: "Test note #\(i) - \(Date().ISO8601Format())"
                )
                event.ndk = ndk
                try await event.sign()
                events.append(event)
                
                // Save to cache
                try await cache.saveEvent(event)
                print("✅ Saved event \(i): \(String(event.id!.prefix(8)))...")
            }
            
            // Retrieve events by ID
            print("\n🔍 Retrieving events by ID...")
            for event in events {
                if let retrieved = await cache.getEvent(id: event.id!) {
                    print("✅ Retrieved event: \(String(retrieved.id!.prefix(8)))... - \(retrieved.content)")
                } else {
                    print("❌ Failed to retrieve event: \(event.id!)")
                }
            }
            
            // Test 2: Query events by filter
            print("\n🔎 Test 2: Query Events by Filter")
            print("-" * 40)
            
            // Query by author
            let authorFilter = NDKFilter(authors: [pubkey])
            let authorEvents = try await cache.queryEvents(authorFilter)
            print("✅ Found \(authorEvents.count) events by author \(String(pubkey.prefix(16)))...")
            
            // Query by kind
            let kindFilter = NDKFilter(kinds: [1])
            let kindEvents = try await cache.queryEvents(kindFilter)
            print("✅ Found \(kindEvents.count) events of kind 1")
            
            // Query with limit
            let limitFilter = NDKFilter(authors: [pubkey], limit: 3)
            let limitedEvents = try await cache.queryEvents(limitFilter)
            print("✅ Found \(limitedEvents.count) events with limit 3")
            
            // Test 3: Events with tags
            print("\n🏷️  Test 3: Events with Tags")
            print("-" * 40)
            
            // Create event with tags
            let taggedEvent = NDKEvent(
                pubkey: pubkey,
                kind: 1,
                tags: [
                    ["e", "abc123", "wss://relay.example.com", "reply"],
                    ["p", pubkey]
                ],
                content: "Reply to another note"
            )
            taggedEvent.ndk = ndk
            try await taggedEvent.sign()
            try await cache.saveEvent(taggedEvent)
            print("✅ Saved event with tags: \(String(taggedEvent.id!.prefix(8)))...")
            
            // Query by tag
            let tagFilter = NDKFilter(tags: ["e": ["abc123"]])
            let taggedEvents = try await cache.queryEvents(tagFilter)
            print("✅ Found \(taggedEvents.count) events with e-tag 'abc123'")
            
            // Test 4: Profile storage
            print("\n👥 Test 4: Profile Storage")
            print("-" * 40)
            
            let profile = NDKUserProfile(
                name: "Test User",
                displayName: "Test Display Name",
                about: "This is a test profile",
                picture: "https://example.com/avatar.jpg",
                banner: "https://example.com/banner.jpg",
                nip05: "test@example.com",
                lud16: "test@ln.example.com",
                website: "https://example.com"
            )
            
            try await cache.saveProfile(profile, pubkey: pubkey)
            print("✅ Saved profile for \(String(pubkey.prefix(16)))...")
            
            if let retrieved = await cache.getProfile(pubkey: pubkey) {
                print("✅ Retrieved profile: \(retrieved.name ?? "unnamed") - \(retrieved.about ?? "no bio")")
            } else {
                print("❌ Failed to retrieve profile")
            }
            
            // Test 5: Time-based queries
            print("\n⏰ Test 5: Time-based Queries")
            print("-" * 40)
            
            let now = Int64(Date().timeIntervalSince1970)
            let hourAgo = now - 3600
            
            // Create an old event
            let oldEvent = NDKEvent(
                pubkey: pubkey,
                createdAt: hourAgo - 100, // More than an hour ago
                kind: 1,
                content: "Old event"
            )
            oldEvent.ndk = ndk
            try await oldEvent.sign()
            try await cache.saveEvent(oldEvent)
            
            // Query recent events (last hour)
            let recentFilter = NDKFilter(since: hourAgo)
            let recentEvents = try await cache.queryEvents(recentFilter)
            print("✅ Found \(recentEvents.count) events from the last hour")
            
            // Query old events
            let oldFilter = NDKFilter(until: hourAgo)
            let oldEvents = try await cache.queryEvents(oldFilter)
            print("✅ Found \(oldEvents.count) events older than an hour")
            
            // Test 6: Delete operations
            print("\n🗑️  Test 6: Delete Operations")
            print("-" * 40)
            
            let eventToDelete = events.first!
            try await cache.deleteEvent(id: eventToDelete.id!)
            print("✅ Deleted event \(String(eventToDelete.id!.prefix(8)))...")
            
            if await cache.getEvent(id: eventToDelete.id!) != nil {
                print("❌ Event still exists after deletion!")
            } else {
                print("✅ Event successfully deleted")
            }
            
            // Test 7: Statistics
            print("\n📊 Test 7: Cache Statistics")
            print("-" * 40)
            
            let eventCount = await cache.eventCount()
            let profileCount = await cache.profileCount()
            
            print("📈 Total events in cache: \(eventCount)")
            print("📈 Total profiles in cache: \(profileCount)")
            
            // Test 8: Clear cache
            print("\n🧹 Test 8: Clear Cache")
            print("-" * 40)
            
            try await cache.clear()
            print("✅ Cleared all cache data")
            
            let afterClearCount = await cache.eventCount()
            print("📈 Events after clear: \(afterClearCount)")
            
            if afterClearCount == 0 {
                print("✅ Cache successfully cleared")
            } else {
                print("❌ Cache still contains data after clear!")
            }
            
            // Cleanup
            try FileManager.default.removeItem(atPath: dbPath)
            print("\n✅ Test database cleaned up")
            
            print("\n🎉 All SQLite cache tests completed successfully!")
            
        } catch {
            print("\n❌ Test failed with error: \(error)")
            exit(1)
        }
    }
}

// Helper extension for string repetition
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}