#!/usr/bin/env swift

import Foundation
import NDKSwift

// Example: Using the Outbox Model with NDKSwift
// This demonstrates intelligent relay selection and publishing

@main
struct OutboxDemo {
    static func main() async {
        print("🚀 NDKSwift Outbox Model Demo")
        print("================================\n")

        // Initialize NDK with some relays
        let ndk = NDK()

        // Add some relays
        _ = ndk.addRelay(url: "wss://relay.damus.io")
        _ = ndk.addRelay(url: "wss://nos.lol")
        _ = ndk.addRelay(url: "wss://relay.nostr.band")

        print("📡 Added relays:")
        for relay in ndk.relays {
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

        await ndk.setRelaysForUser(
            pubkey: pubkey,
            readRelays: ["wss://relay.damus.io", "wss://nos.lol"],
            writeRelays: ["wss://relay.damus.io", "wss://relay.nostr.band"]
        )

        if let relayInfo = await ndk.getRelaysForUser(pubkey: pubkey) {
            print("✅ User relay preferences tracked:")
            print("   Read relays: \(relayInfo.readRelayUrls)")
            print("   Write relays: \(relayInfo.writeRelayUrls)")
        }

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
            ["t", "ndkswift"],
        ]

        print("📝 Publishing note: \(noteEvent.content)")

        do {
            // Publish using outbox model
            let result = try await ndk.publishWithOutbox(noteEvent)

            print("\n✅ Published successfully!")
            print("   Total relays: \(result.relayResults.count)")
            print("   Successful: \(result.successfulRelays.count)")
            print("   Failed: \(result.failedRelays.count)")

            for (relay, success) in result.relayResults {
                print("   - \(relay): \(success ? "✓" : "✗")")
            }

            print("\n📊 Selection details:")
            print("   Method: \(result.selectionMethod)")
            print("   Publish time: \(String(format: "%.2f", result.publishTime))s")

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
            let events = try await ndk.fetchEventsWithOutbox(
                filter: filter,
                config: OutboxFetchConfig(
                    minSuccessfulRelays: 2,
                    timeoutInterval: 5.0
                )
            )

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
            let subscription = try await ndk.subscribeWithOutbox(
                filters: [subscriptionFilter],
                eventHandler: { event in
                    print("\n🆕 New event received:")
                    print("   Author: \(event.pubkey)")
                    print("   Content: \(String(event.content.prefix(50)))...")
                }
            )

            print("✅ Subscription active on \(subscription.targetRelays.count) relays")

            // Wait a bit for events
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            print("\n📊 Subscription stats:")
            print("   Events received: \(subscription.eventCount)")
            print("   Unique events: \(subscription.seenEventIds.count)")

            // Close subscription
            await ndk.closeOutboxSubscription(subscription.id)
            print("✅ Subscription closed")

        } catch {
            print("❌ Failed to subscribe: \(error)")
        }

        // Demo 5: Relay health and ranking
        print("\n🏥 Demo 5: Relay Health and Ranking")
        print("===================================")

        let relayScores = await ndk.getRelayScores()

        print("📊 Relay health scores:")
        for (relay, score) in relayScores.sorted(by: { $0.value > $1.value }).prefix(5) {
            let health = score > 0.8 ? "🟢" : score > 0.5 ? "🟡" : "🔴"
            print("   \(health) \(relay): \(String(format: "%.1f%%", score * 100))")
        }

        // Cleanup
        print("\n🧹 Cleaning up...")
        await ndk.disconnect()

        print("\n✅ Demo completed!")
    }
}
