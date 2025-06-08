import Foundation
import NDKSwift

/// Example showing how to use the new NDKCache directly
@main
struct CacheExample {
    static func main() async {
        print("🚀 NDKCache Example")
        
        do {
            // Create cache instance
            let cache = try await NDKCache()
            
            // Create NDK instance with cache
            let ndk = NDK(
                relayUrls: ["wss://relay.damus.io"],
                cache: cache
            )
            
            // Example event
            let event = NDKEvent(
                pubkey: "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
                kind: 1,
                tags: [],
                content: "Hello from NDKSwift with new cache!"
            )
            event.id = try event.generateID()
            
            // Save event to cache
            print("\n💾 Saving event to cache...")
            try await cache.saveEvent(event)
            print("✅ Event saved!")
            
            // Retrieve event from cache
            print("\n🔍 Retrieving event from cache...")
            if let retrieved = await cache.getEvent(event.id!) {
                print("✅ Event retrieved: \(retrieved.content)")
            }
            
            // Query events by filter
            print("\n🔎 Querying events by author...")
            let filter = NDKFilter(authors: [event.pubkey])
            let events = await cache.queryEvents(filter)
            print("✅ Found \(events.count) event(s)")
            
            // Save and retrieve profile
            print("\n👤 Saving user profile...")
            let profile = NDKUserProfile(
                name: "Test User",
                displayName: "Test",
                about: "Testing the new cache",
                picture: nil,
                banner: nil,
                nip05: nil,
                lud06: nil,
                lud16: nil
            )
            try await cache.saveProfile(profile, for: event.pubkey)
            print("✅ Profile saved!")
            
            if let retrievedProfile = await cache.getProfile(for: event.pubkey) {
                print("✅ Profile retrieved: \(retrievedProfile.name ?? "Unknown")")
            }
            
            // Get cache statistics
            print("\n📊 Cache Statistics:")
            let stats = await cache.statistics()
            print("  Hits: \(stats.hits)")
            print("  Misses: \(stats.misses)")
            print("  Current size: \(stats.currentSize)")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}