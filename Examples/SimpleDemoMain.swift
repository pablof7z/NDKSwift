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

        // 4. Test subscriptions
        print("\n📡 Testing subscriptions...")
        let subscription = NDKSubscription(filters: [filter])

        var receivedEvents = 0
        subscription.onEvent { event in
            receivedEvents += 1
            print("📨 Received event \(receivedEvents): \(event.content)")
        }

        subscription.onEOSE {
            print("🏁 EOSE received")
        }

        // Simulate events
        subscription.handleEvent(event, fromRelay: nil as NDKRelay?)

        let event2 = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Second test event"
        )
        event2.id = "test_event_2"

        subscription.handleEvent(event2, fromRelay: nil as NDKRelay?)
        subscription.handleEOSE()

        print("✅ Subscription received \(subscription.events.count) events")

        // 5. Test NDK instance
        print("\n🏗️ Testing NDK instance...")
        let ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://nos.lol",
            ],
            cacheAdapter: NDKInMemoryCache()
        )

        print("✅ NDK created with \(ndk.relays.count) relays")

        for relay in ndk.relays {
            print("   📡 Relay: \(relay.normalizedURL)")
        }

        // 6. Test cache
        print("\n💾 Testing cache...")
        if let cache = ndk.cacheAdapter {
            await cache.setEvent(event, filters: [filter], relay: nil)

            let cachedEvents = await cache.query(subscription: subscription)
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
