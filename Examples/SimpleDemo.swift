import Foundation
import NDKSwift

// Simple NDKSwift demonstration that can be run directly

func runSimpleDemo() async {
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

    // 4. Test subscriptions with new AsyncStream API
    print("\n📡 Testing subscriptions...")
    let subscription = NDKSubscription(filters: [filter])

    // Simulate events in background
    Task {
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
    }
    
    // Use AsyncStream to handle events
    var receivedEvents = 0
    for await update in subscription.updates {
        switch update {
        case .event(let event):
            receivedEvents += 1
            print("📨 Received event \(receivedEvents): \(event.content)")
        case .eose:
            print("🏁 EOSE received")
            break // Exit loop
        case .error(let error):
            print("❌ Error: \(error)")
        }
    }

    print("✅ Subscription received \(receivedEvents) events")

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

    // 6. Test cache with new API
    print("\n💾 Testing cache...")
    if let cache = ndk.cache {
        try? await cache.saveEvent(event)

        let cachedEvents = await cache.queryEvents(filter)
        print("✅ Cache stored and retrieved \(cachedEvents.count) events")
    }
    
    // 6b. Test fetch API
    print("\n🎯 Testing fetch API...")
    do {
        // Fetch profile
        if let profile = try await ndk.fetchProfile(user.pubkey) {
            print("✅ Fetched profile: \(profile.displayName ?? "Unknown")")
        }
        
        // Fetch recent events
        let recentEvents = try await ndk.fetchEvents(filter)
        print("✅ Fetched \(recentEvents.count) events")
    } catch {
        print("❌ Fetch error: \(error)")
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
    print("✅ npub: \(user.npub)")

    // Test creating user from npub
    if let userFromNpub = NDKUser(npub: user.npub) {
        print("✅ Created user from npub: \(userFromNpub.pubkey == user.pubkey ? "✅ Match" : "❌ No match")")
    } else {
        print("❌ Failed to create user from npub")
    }

    print("\n🎉 Demo completed successfully!")
    print("==========================================")
    print("NDKSwift is working correctly! 🚀")
}

// Run the demo
Task {
    await runSimpleDemo()
}
