#!/usr/bin/env swift

import Foundation
import NDKSwift

// This example demonstrates how to use reactive queries with NDKSQLiteCache
// to observe database changes in real-time

@main
struct ReactiveQueriesDemo {
    static func main() async throws {
        print("🚀 NDKSwift Reactive Queries Demo")
        print("=================================\n")
        
        // Create NDK instance with SQLite cache
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(
            signer: signer,
            cache: try await NDKSQLiteCache(debugMode: true),
            configuration: NDKConfiguration(
                bundleIdentifier: "com.example.reactive-demo",
                relays: ["wss://relay.damus.io", "wss://relay.nostr.band"]
            )
        )
        
        // Connect to relays
        _ = try await ndk.connect()
        
        // Example 1: Observe all text notes (kind 1)
        print("📝 Example 1: Observing text notes")
        print("---------------------------------")
        
        let textNoteFilter = NDKFilter(kinds: [1], limit: 10)
        
        // Create a task to observe text notes
        let observationTask = Task {
            let eventStream = await (ndk.cache as? NDKSQLiteCache)?.observeEvents(matching: textNoteFilter)
            
            guard let stream = eventStream else {
                print("❌ Cache doesn't support reactive queries")
                return
            }
            
            print("👀 Watching for text notes...")
            
            do {
                for try await events in stream {
                    print("\n📬 Received \(events.count) event(s):")
                    for event in events.prefix(3) {
                        let preview = String(event.content.prefix(50))
                        print("  - [\(event.createdAt.date.formatted())] \(preview)...")
                    }
                }
            } catch {
                print("❌ Observation error: \(error)")
            }
        }
        
        // Let the observation run for a bit
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        // Example 2: Observe a specific user's profile
        print("\n\n👤 Example 2: Observing profile changes")
        print("---------------------------------------")
        
        let profileTask = Task {
            let profileStream = await (ndk.cache as? NDKSQLiteCache)?.observeProfile(
                pubkey: signer.publicKey.hex,
                includeExisting: true
            )
            
            guard let stream = profileStream else {
                print("❌ Cache doesn't support reactive queries")
                return
            }
            
            print("👀 Watching for profile changes...")
            
            do {
                for try await profile in stream {
                    if let profile = profile {
                        print("\n✅ Profile update:")
                        print("  Name: \(profile.name ?? "N/A")")
                        print("  About: \(profile.about ?? "N/A")")
                    } else {
                        print("\n❌ Profile deleted")
                    }
                }
            } catch {
                print("❌ Profile observation error: \(error)")
            }
        }
        
        // Simulate a profile update
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("\n📤 Publishing profile update...")
        let profileEvent = try await ndk.publishProfile(
            NDKUserProfile(
                name: "Reactive Demo User",
                about: "Testing reactive queries at \(Date().formatted())"
            )
        )
        
        // Let observations run a bit more
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Example 3: Observe with custom filter
        print("\n\n🔍 Example 3: Custom reactive filter")
        print("------------------------------------")
        
        // Create a filter for reactions to a specific event
        let targetEventId = "test123"
        let reactionFilter = NDKFilter(
            kinds: [7], // Reactions
            events: [targetEventId],
            limit: 20
        )
        
        let reactionTask = Task {
            let reactionStream = await (ndk.cache as? NDKSQLiteCache)?.observeEvents(
                matching: reactionFilter,
                includeExisting: false // Only new reactions
            )
            
            guard let stream = reactionStream else {
                print("❌ Cache doesn't support reactive queries")
                return
            }
            
            print("👀 Watching for new reactions to event \(targetEventId.prefix(8))...")
            
            do {
                for try await reactions in stream {
                    for reaction in reactions {
                        let emoji = reaction.content.isEmpty ? "👍" : reaction.content
                        print("  \(emoji) from \(reaction.pubkey.prefix(8))...")
                    }
                }
            } catch {
                print("❌ Reaction observation error: \(error)")
            }
        }
        
        // Wait a bit more
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        // Cancel all observations
        print("\n\n🛑 Stopping all observations...")
        observationTask.cancel()
        profileTask.cancel()
        reactionTask.cancel()
        
        // Disconnect
        await ndk.disconnect()
        
        print("\n✅ Demo completed!")
    }
}

// Helper extension for string prefix
extension String {
    func prefix(_ maxLength: Int) -> String {
        return String(self.prefix(maxLength))
    }
}