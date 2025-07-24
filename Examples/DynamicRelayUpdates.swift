#!/usr/bin/env swift

import Foundation
import NDKSwift

/// Example demonstrating dynamic relay updates in the outbox model
@main
struct DynamicRelayUpdatesExample {
    static func main() async {
        print("🚀 Dynamic Relay Updates Example")
        print("================================\n")
        
        // Create NDK instance
        let ndk = NDK()
        
        // Add some default relays
        await ndk.addRelay(RelayConstants.damus)
        await ndk.addRelay(RelayConstants.nosLol)
        
        // Connect to relays
        await ndk.connect()
        await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 5)
        
        print("✅ Connected to relays\n")
        
        // Monitor relay updates
        Task {
            print("👀 Monitoring relay updates...")
            for await update in await ndk.outbox.relayUpdates {
                print("\n🔔 Relay Update Event:")
                print("   Author: \(update.pubkey.prefix(8))...")
                print("   Read relays: \(update.relays.readRelays)")
                print("   Write relays: \(update.relays.writeRelays)")
                print("   Affected subscriptions: \(update.affectedSubscriptionIds)")
                print("   Timestamp: \(update.timestamp)")
            }
        }
        
        // Create a follow list (simulating unknown authors)
        let followList = [
            "d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a", // walker
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", // fiatjaf
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"  // jack
        ]
        
        print("📋 Creating subscription for \(followList.count) authors\n")
        
        // Create a data source with these authors
        let filter = NDKFilter(
            authors: followList,
            kinds: [1], // Text notes
            limit: 10
        )
        
        let dataSource = ndk.observe(filter: filter)
        
        // Track received events
        var eventCount = 0
        let startTime = Date()
        
        print("📡 Waiting for events (30 seconds)...\n")
        
        // Observe events
        Task {
            for await event in dataSource.events {
                eventCount += 1
                let authorPrefix = event.pubkey.prefix(8)
                let contentPreview = String(event.content.prefix(50))
                print("📝 Event #\(eventCount) from \(authorPrefix): \(contentPreview)...")
            }
        }
        
        // Periodically show stats
        for i in 1...6 {
            try? await Task.sleep(nanoseconds: 5 * TimeConstants.nanosecondsPerSecond) // 5 seconds
            
            let stats = await ndk.outbox.getRelayUpdateStats()
            let elapsed = Int(Date().timeIntervalSince(startTime))
            
            print("\n📊 Stats at T+\(elapsed)s:")
            print("   Events received: \(eventCount)")
            print("   Active subscriptions: \(stats.activeSubscriptions)")
            print("   Unknown authors: \(stats.totalUnknownAuthors)")
            print("   Update subscriptions: \(stats.totalUpdateSubscriptions)")
        }
        
        print("\n🎉 Example complete!")
        print("   Total events received: \(eventCount)")
        print("   This example demonstrates how subscriptions are dynamically")
        print("   updated as relay information becomes available.\n")
    }
}

// Example output:
// 🚀 Dynamic Relay Updates Example
// ================================
//
// ✅ Connected to relays
//
// 👀 Monitoring relay updates...
// 📋 Creating subscription for 3 authors
//
// 📡 Waiting for events (30 seconds)...
//
// 📝 Event #1 from d61f3bc5: Bitcoin is the future of money...
//
// 🔔 Relay Update Event:
//    Author: 3bf0c63f...
//    Read relays: ["wss://relay.snort.social", "wss://relay.nostr.band"]
//    Write relays: ["wss://relay.snort.social"]
//    Affected subscriptions: ["notes_authors_3_xK9Q"]
//    Timestamp: 2024-12-30 10:15:23
//
// 📝 Event #2 from 3bf0c63f: Just published a new NIP proposal...
//
// 📊 Stats at T+5s:
//    Events received: 2
//    Active subscriptions: 1
//    Unknown authors: 2
//    Update subscriptions: 1