import Foundation
import NDKSwift

// Simple NDKSwift demonstration
@main
struct SimpleDemoMain {
    static func main() async {
        print("🚀 NDKSwift Simple Demo")
        print("======================")

        // 1. Demonstrate Bech32 encoding
        print("\n📝 Testing Bech32 encoding...")
        do {
            let testPubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
            let npub = try Bech32.npub(from: testPubkey)
            let decoded = try Bech32.pubkey(from: npub)

            print("✅ Original: \(testPubkey)")
            print("✅ Encoded:  \(npub)")
            print("✅ Decoded:  \(decoded)")
            print("✅ Match: \(testPubkey == decoded)")
        } catch {
            print("❌ Bech32 error: \(error)")
        }

        // 2. Create and test events
        print("\n📄 Testing event creation...")
        let event = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Hello from NDKSwift! 🎉"
        )

        event.addTag(["t", "ndkswift"])
        event.addTag(["t", "demo"])

        do {
            let eventId = try event.generateID()
            print("✅ Event created with ID: \(eventId)")
            print("✅ Content: \(event.content)")
            print("✅ Tags: \(event.tags.count)")
        } catch {
            print("❌ Event error: \(error)")
        }

        // 3. Test filters
        print("\n🔍 Testing filters...")
        let filter = NDKFilter(
            authors: ["d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"],
            kinds: [EventKind.textNote],
            limit: 10
        )

        let matches = filter.matches(event: event)
        print("✅ Filter matches event: \(matches)")

        // 4. Test subscriptions with modern async API
        print("\n📡 Testing subscriptions...")
        let subscription = NDKSubscription(filters: [filter])

        // Simulate events in background
        Task {
            // Small delay to ensure subscription starts
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            await subscription.handleEvent(event, fromRelay: nil)

            let event2 = NDKEvent(
                pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "Second test event"
            )
            event2.id = "test_event_2"

            await subscription.handleEvent(event2, fromRelay: nil)
            await subscription.handleEOSE()
        }

        // Use modern async iteration
        var receivedEvents = 0
        do {
            for try await event in subscription {
                receivedEvents += 1
                print("📨 Received event \(receivedEvents): \(event.content)")
                if receivedEvents >= 2 {
                    break // Exit after receiving both test events
                }
            }
        } catch {
            print("❌ Subscription error: \(error)")
        }

        print("✅ Subscription received \(receivedEvents) events")

        // 5. Test NDK instance
        print("\n🏗️ Testing NDK instance...")
        let ndk = try await NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://nos.lol"
            ]
        )

        print("✅ NDK created with \(ndk.relays.count) relays")

        for relay in ndk.relays {
            print("   📡 Relay: \(relay.normalizedURL)")
        }

        // 6. Test cache
        print("\n💾 Testing cache...")
        if let cache = ndk.cache {
            try? await cache.saveEvent(event)

            let cachedEvents = await cache.queryEvents(filter)
            print("✅ Cache stored and retrieved \(cachedEvents.count) events")
        }

        // 7. Test user profiles
        print("\n👤 Testing user profiles...")
        let user = ndk.getUser("d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e")

        let profile = NDKUserProfile(
            name: "demo_user",
            displayName: "Demo User",
            about: "Testing NDKSwift functionality",
            picture: "https://example.com/avatar.jpg"
        )
        user.updateProfile(profile)

        print("✅ User: \(user.displayName ?? "Unknown")")
        print("✅ Short pubkey: \(user.shortPubkey)")

        print("\n🎉 Demo completed successfully!")
        print("==========================================")
        print("NDKSwift is working correctly! 🚀")
    }
}
