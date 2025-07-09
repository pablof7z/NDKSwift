import Foundation
import NDKSwift

// Test to validate cache functionality

@main
struct TestCacheValidation {
    static func main() async {
        print("🚀 Starting cache validation test...")
        
        do {
            // Create a cache instance
            let cache = SimpleMemoryCache()
            
            // Test 1: Save and retrieve a single event
            print("\n📝 Test 1: Save and retrieve single event")
            let privateKey = Crypto.generatePrivateKey()
            let publicKey = try Crypto.getPublicKey(from: privateKey)
            
            let event1 = NDKEvent(
                pubkey: publicKey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "First test event"
            )
            event1.id = try event1.generateID()
            
            // Save event
            try await cache.saveEvent(event1)
            print("✅ Event saved")
            
            // Retrieve event
            if let retrieved = await cache.getEvent(id: event1.id!) {
                print("✅ Event retrieved successfully")
                print("   Content: \(retrieved.content)")
                assert(retrieved.content == event1.content, "Content mismatch")
            } else {
                print("❌ Failed to retrieve event")
                exit(1)
            }
            
            // Test 2: Query events by filter
            print("\n🔍 Test 2: Query events by filter")
            
            // Add more events
            let event2 = NDKEvent(
                pubkey: publicKey,
                createdAt: Timestamp(Date().timeIntervalSince1970 - 60),
                kind: EventKind.textNote,
                content: "Second test event"
            )
            event2.id = try event2.generateID()
            try await cache.saveEvent(event2)
            
            let event3 = NDKEvent(
                pubkey: "different_pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970 - 120),
                kind: EventKind.textNote,
                content: "Event from different author"
            )
            event3.id = try event3.generateID()
            try await cache.saveEvent(event3)
            
            // Query by author
            let authorFilter = NDKFilter(authors: [publicKey])
            let authorEvents = await cache.queryEvents(authorFilter)
            print("✅ Found \(authorEvents.count) events from author")
            assert(authorEvents.count == 2, "Should find 2 events from author")
            
            // Query by kind
            let kindFilter = NDKFilter(kinds: [EventKind.textNote])
            let kindEvents = await cache.queryEvents(kindFilter)
            print("✅ Found \(kindEvents.count) text note events")
            assert(kindEvents.count == 3, "Should find 3 text note events")
            
            // Query with limit
            let limitFilter = NDKFilter(kinds: [EventKind.textNote], limit: 2)
            let limitedEvents = await cache.queryEvents(limitFilter)
            print("✅ Found \(limitedEvents.count) events with limit")
            assert(limitedEvents.count == 2, "Should find 2 events with limit")
            
            // Test 3: Profile caching
            print("\n👤 Test 3: Profile caching")
            let profile = NDKUserProfile(
                name: "test_user",
                displayName: "Test User",
                about: "This is a test profile",
                picture: "https://example.com/avatar.jpg"
            )
            
            try await cache.saveProfile(profile, pubkey: publicKey)
            print("✅ Profile saved")
            
            if let retrievedProfile = await cache.getProfile(pubkey: publicKey) {
                print("✅ Profile retrieved successfully")
                print("   Name: \(retrievedProfile.name ?? "nil")")
                print("   Display: \(retrievedProfile.displayName ?? "nil")")
                assert(retrievedProfile.name == profile.name, "Profile name mismatch")
            } else {
                print("❌ Failed to retrieve profile")
                exit(1)
            }
            
            // Test 4: NDK integration with cache
            print("\n🔗 Test 4: NDK integration with cache")
            let ndk = NDK(
                relayUrls: ["wss://relay.damus.io"],
                cache: cache
            )
            
            // Create and save an event through NDK
            let signer = try NDKPrivateKeySigner(privateKey: privateKey)
            ndk.signer = signer
            
            let ndkEvent = NDKEvent(
                pubkey: publicKey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "Event saved through NDK"
            )
            ndkEvent.id = try ndkEvent.generateID()
            ndkEvent.sig = try await signer.sign(ndkEvent)
            
            // Save to cache through NDK
            if let ndkCache = ndk.cache {
                try await ndkCache.saveEvent(ndkEvent)
                print("✅ Event saved through NDK cache")
                
                // Verify it's in cache
                if let cached = await ndkCache.getEvent(id: ndkEvent.id!) {
                    print("✅ Event found in NDK cache")
                    print("   Content: \(cached.content)")
                }
            }
            
            // Test 5: Cache statistics
            print("\n📊 Test 5: Cache statistics")
            let eventCount = await cache.eventCount()
            let profileCount = await cache.profileCount()
            print("✅ Cache contains:")
            print("   Events: \(eventCount)")
            print("   Profiles: \(profileCount)")
            assert(eventCount == 4, "Should have 4 events in cache")
            assert(profileCount == 1, "Should have 1 profile in cache")
            
            // Test 6: Clear cache
            print("\n🗑️ Test 6: Clear cache")
            try await cache.clear()
            print("✅ Cache cleared")
            
            let afterClearCount = await cache.eventCount()
            assert(afterClearCount == 0, "Cache should be empty after clear")
            print("✅ Cache is empty")
            
            print("\n🎉 All cache tests passed!")
            
        } catch {
            print("❌ Test failed: \(error)")
            exit(1)
        }
    }
}