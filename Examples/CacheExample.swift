import Foundation
import NDKSwift

/// Example showing how to use the new NDKCache directly
@main
struct CacheExample {
    static func main() async {
        print("🚀 NDKCache Example")
        
        do {
            // Create NDK instance without cache for now
            // (cache implementations have been removed from the codebase)
            let ndk = NDK(
                relayUrls: ["wss://relay.damus.io"]
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
            print("\n💾 Would save event to cache...")
            // try await cache.saveEvent(event) - cache not available
            print("✅ Event would be saved!")
            
            // Retrieve event from cache
            print("\n🔍 Would retrieve event from cache...")
            // if let retrieved = await cache.getEvent(event.id!) - cache not available
            print("✅ Event content: \(event.content)")
            
            // Query events by filter
            print("\n🔎 Would query events by author...")
            let filter = NDKFilter(authors: [event.pubkey])
            // let events = await cache.queryEvents(filter) - cache not available
            print("✅ Filter created for author")
            
            // Save and retrieve profile
            print("\n👤 Saving user profile...")
            let profile = NDKUserProfile(
                name: "Test User",
                displayName: "Test",
                about: "Testing the new cache",
                picture: nil,
                banner: nil,
                nip05: nil,
                lud16: nil,
                lud06: nil
            )
            // try await cache.saveProfile(profile, for: event.pubkey) - cache not available
            print("✅ Profile would be saved!")
            
            // if let retrievedProfile = await cache.getProfile(for: event.pubkey) - cache not available
            print("✅ Profile name: \(profile.name ?? "Unknown")")
            
            // Get cache statistics
            print("\n📊 Cache Statistics:")
            // let stats = await cache.statistics() - cache not available
            print("  Hits: (would show cache hits)")
            print("  Misses: (would show cache misses)")
            print("  Current size: (would show cache size)")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
}
