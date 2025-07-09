#!/usr/bin/env swift

import Foundation
import NDKSwift

// Example: NDKSwift uses Outbox Model by default
// This demonstrates how outbox model works automatically

@main
struct OutboxDemo {
    static func main() async {
        print("🚀 NDKSwift Outbox Model Demo")
        print("================================")
        print("Note: Outbox model is enabled by default!\n")

        // Initialize NDK with some relays
        let ndk = NDK()

        // Add some relays
        _ = ndk.addRelay(url: "wss://relay.damus.io")
        _ = ndk.addRelay(url: "wss://nos.lol")
        _ = ndk.addRelay(url: "wss://relay.nostr.band")

        print("📡 Added relays:")
        for relay in await ndk.relays {
            print("   - \(relay.url)")
        }

        // Create a private key signer for demo
        let privateKey = NDKPrivateKeySigner.generateKey()
        guard let signer = NDKPrivateKeySigner(privateKey: privateKey) else {
            print("❌ Failed to create signer")
            return
        }

        ndk.signer = signer
        let pubkey = signer.publicKey()

        print("\n🔑 Generated keypair:")
        print("   Public key: \(pubkey)")

        // Connect to relays
        print("\n📡 Connecting to relays...")
        await ndk.connect()

        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Demo 1: Track user relay preferences
        print("\n📋 Demo 1: Tracking User Relay Preferences")
        print("==========================================")

        // Track user to enable outbox model
        await ndk.outbox.trackUser(pubkey)

        print("✅ User tracked for outbox model")

        // Demo 2: Publish with intelligent relay selection
        print("\n📤 Demo 2: Publishing with Outbox Model")
        print("======================================")

        let noteEvent = NDKEvent(ndk: ndk)
        noteEvent.kind = 1
        noteEvent.content = "Hello from NDKSwift with Outbox Model! 🚀"
        noteEvent.pubkey = pubkey
        noteEvent.createdAt = Timestamp(Date().timeIntervalSince1970)

        // Add some tags
        noteEvent.tags = [
            ["t", "nostr"],
            ["t", "ndkswift"]
        ]

        print("📝 Publishing note: \(noteEvent.content)")

        do {
            // Just call publish() - outbox model is used automatically!
            let publishedRelays = try await ndk.publish(noteEvent)

            print("\n✅ Published successfully using outbox model!")
            print("   Successful relays: \(publishedRelays.count)")
            for relay in publishedRelays {
                print("   - \(relay.url): ✓")
            }

        } catch {
            print("❌ Failed to publish: \(error)")
        }

        // Demo 3: Fetch with outbox model
        print("\n📥 Demo 3: Fetching with Outbox Model")
        print("=====================================")

        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [1],
            limit: 10
        )

        print("🔍 Fetching events for author: \(pubkey)")

        do {
            // Just call fetchEvents() - outbox model is used automatically!
            let events = try await ndk.fetchEvents(filter)

            print("✅ Fetched \(events.count) events")

            for event in events.prefix(3) {
                print("\n📄 Event:")
                print("   ID: \(event.id ?? "unknown")")
                print("   Content: \(event.content)")
                print("   Created: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
            }

        } catch {
            print("❌ Failed to fetch: \(error)")
        }

        // Demo 4: Subscribe with outbox model
        print("\n📡 Demo 4: Subscribing with Outbox Model")
        print("========================================")

        let subscriptionFilter = NDKFilter(
            kinds: [1],
            limit: 5
        )

        print("🔔 Creating subscription for text notes...")

        do {
            // For subscriptions, we'll use the regular NDK subscribe method
            // The outbox model can be used for one-shot fetches
            let subscription = ndk.subscribe(filters: [subscriptionFilter])
            
            Task {
                for await event in subscription {
                    print("\n🆕 New event received:")
                    print("   Author: \(event.pubkey)")
                    print("   Content: \(String(event.content.prefix(50)))...")
                }
            }

            print("✅ Subscription active")

            // Wait a bit for events
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            // Close subscription
            subscription.close()
            print("✅ Subscription closed")

        } catch {
            print("❌ Failed to subscribe: \(error)")
        }

        // Demo 5: Relay health and ranking
        print("\n🏥 Demo 5: Relay Health and Ranking")
        print("===================================")

        // Get relay recommendations for the user
        let recommendedRelays = await ndk.outbox.getRecommendedRelays(for: pubkey)
        
        print("📊 Recommended relays for user:")
        for (index, relay) in recommendedRelays.enumerated() {
            let score = await ndk.outbox.getRelayScore(relay: relay, for: pubkey)
            let health = score > 0.8 ? "🟢" : score > 0.5 ? "🟡" : "🔴"
            print("   \(index + 1). \(health) \(relay): \(String(format: "%.1f%%", score * 100))")
        }

        // Demo 6: Disabling outbox model
        print("\n🔧 Demo 6: Disabling Outbox Model")
        print("=================================")
        
        // Create a new NDK instance with outbox disabled
        let ndkNoOutbox = NDK()
        ndkNoOutbox.outboxEnabled = false
        
        // Add relays
        _ = ndkNoOutbox.addRelay(url: "wss://relay.damus.io")
        _ = ndkNoOutbox.addRelay(url: "wss://nos.lol")
        
        // Set up signer
        ndkNoOutbox.signer = signer
        
        print("📡 Connecting without outbox model...")
        await ndkNoOutbox.connect()
        
        let simpleNote = NDKEvent(ndk: ndkNoOutbox)
        simpleNote.kind = 1
        simpleNote.content = "This is published directly without outbox model"
        simpleNote.pubkey = pubkey
        simpleNote.createdAt = Timestamp(Date().timeIntervalSince1970)
        
        do {
            let publishedRelays = try await ndkNoOutbox.publish(simpleNote)
            print("✅ Published to \(publishedRelays.count) relays (outbox disabled)")
        } catch {
            print("❌ Failed to publish: \(error)")
        }
        
        await ndkNoOutbox.disconnect()

        // Cleanup
        print("\n🧹 Cleaning up...")
        await ndk.disconnect()

        print("\n✅ Demo completed!")
    }
}
