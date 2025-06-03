import Foundation
import NDKSwift

// Comprehensive NDKSwift Demo Application
@main
struct NostrDemoMain {
    static func main() async {
        print("🚀 NDKSwift Comprehensive Demo")
        print("==============================")
        
        do {
            // 1. Test Bech32 encoding/decoding
            print("\n📝 1. Testing Bech32 Encoding/Decoding")
            print("=====================================")
            try testBech32()
            
            // 2. Test event creation and validation
            print("\n📄 2. Testing Event Creation")
            print("===========================")
            try testEventCreation()
            
            // 3. Test filters
            print("\n🔍 3. Testing Filters")
            print("====================")
            testFilters()
            
            // 4. Test subscriptions
            print("\n📡 4. Testing Subscriptions")
            print("==========================")
            await testSubscriptions()
            
            // 5. Test NDK instance
            print("\n🏗️ 5. Testing NDK Instance")
            print("==========================")
            await testNDKInstance()
            
            // 6. Test user profiles
            print("\n👤 6. Testing User Profiles")
            print("==========================")
            testUserProfiles()
            
            print("\n🎉 All tests completed successfully!")
            print("====================================")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func testBech32() throws {
        // Test npub encoding/decoding
        let testPubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let npub = try Bech32.npub(from: testPubkey)
        let decodedPubkey = try Bech32.pubkey(from: npub)
        
        print("✅ npub encoding:")
        print("   Original: \(testPubkey)")
        print("   Encoded:  \(npub)")
        print("   Decoded:  \(decodedPubkey)")
        print("   Match:    \(testPubkey == decodedPubkey)")
        
        // Test nsec encoding/decoding
        let testPrivkey = "5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a"
        let nsec = try Bech32.nsec(from: testPrivkey)
        let decodedPrivkey = try Bech32.privateKey(from: nsec)
        
        print("\n✅ nsec encoding:")
        print("   Original: \(testPrivkey)")
        print("   Encoded:  \(nsec)")
        print("   Decoded:  \(decodedPrivkey)")
        print("   Match:    \(testPrivkey == decodedPrivkey)")
        
        // Test note encoding/decoding
        let testEventId = "e771af0b05c8e95fcdf6feb3500544d2fb1ccd384788e9f490bb3ee28e8ed66f"
        let note = try Bech32.note(from: testEventId)
        let decodedEventId = try Bech32.eventId(from: note)
        
        print("\n✅ note encoding:")
        print("   Original: \(testEventId)")
        print("   Encoded:  \(note)")
        print("   Decoded:  \(decodedEventId)")
        print("   Match:    \(testEventId == decodedEventId)")
    }
    
    static func testEventCreation() throws {
        let event = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Hello from NDKSwift! 🎉 This is a test note."
        )
        
        // Add tags
        event.addTag(["t", "ndkswift"])
        event.addTag(["t", "testing"])
        event.addTag(["p", "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"])
        
        // Generate event ID
        let eventId = try event.generateID()
        
        print("✅ Event created:")
        print("   ID:        \(eventId)")
        print("   Kind:      \(event.kind)")
        print("   Content:   \(event.content)")
        print("   Tags:      \(event.tags.count) tags")
        print("   Created:   \(Date(timeIntervalSince1970: Double(event.createdAt)))")
        
        // Test event validation
        do {
            try event.validate()
            print("✅ Event validation passed")
        } catch {
            print("❌ Event validation failed: \(error)")
        }
    }
    
    static func testFilters() {
        print("Creating various filters...")
        
        // Filter 1: Text notes from specific authors
        let filter1 = NDKFilter(
            authors: ["d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"],
            kinds: [EventKind.textNote],
            limit: 20
        )
        print("✅ Filter 1: Text notes from specific author")
        
        // Filter 2: Recent events
        let oneHourAgo = Timestamp(Date().timeIntervalSince1970 - 3600)
        let filter2 = NDKFilter(
            kinds: [EventKind.textNote, EventKind.deletion],
            since: oneHourAgo,
            limit: 50
        )
        print("✅ Filter 2: Recent events (last hour)")
        
        // Filter 3: All text notes with limit
        let filter3 = NDKFilter(
            kinds: [EventKind.textNote],
            limit: 10
        )
        print("✅ Filter 3: All text notes with limit")
        
        // Test filter matching
        let testEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Test event"
        )
        
        print("\nTesting filter matching:")
        print("   Filter 1 matches: \(filter1.matches(event: testEvent))")
        print("   Filter 2 matches: \(filter2.matches(event: testEvent))")
        print("   Filter 3 matches: \(filter3.matches(event: testEvent))")
        
        // Test filter merging
        if let merged = filter1.merged(with: filter2) {
            print("\n✅ Filters 1 and 2 merged successfully")
            print("   Merged kinds: \(merged.kinds ?? [])")
        } else {
            print("\n❌ Filters 1 and 2 are not compatible for merging")
        }
    }
    
    static func testSubscriptions() async {
        print("Creating subscription...")
        
        let filter = NDKFilter(
            kinds: [EventKind.textNote],
            limit: 5
        )
        
        let subscription = NDKSubscription(filters: [filter])
        
        var eventCount = 0
        var eoseReceived = false
        
        // Set up event handler
        subscription.onEvent { event in
            eventCount += 1
            print("📨 Event \(eventCount): \(event.content)")
        }
        
        // Set up EOSE handler
        subscription.onEOSE {
            eoseReceived = true
            print("🏁 EOSE received")
        }
        
        // Simulate receiving events
        print("\nSimulating event stream...")
        
        for i in 1...3 {
            let event = NDKEvent(
                pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "Test event #\(i)"
            )
            event.id = "test_event_\(i)"
            
            subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        }
        
        subscription.handleEOSE()
        
        print("\n✅ Subscription summary:")
        print("   Events received: \(eventCount)")
        print("   EOSE received:   \(eoseReceived)")
        print("   Stored events:   \(subscription.events.count)")
        
        // Test async stream
        print("\nTesting async stream API...")
        let streamSubscription = NDKSubscription(filters: [filter])
        
        Task {
            var streamCount = 0
            for await event in streamSubscription.eventStream() {
                streamCount += 1
                print("🌊 Stream event: \(event.content)")
                if streamCount >= 2 {
                    break
                }
            }
        }
        
        // Send events to stream
        for i in 1...2 {
            let event = NDKEvent(
                pubkey: "test_pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "Stream event #\(i)"
            )
            event.id = "stream_event_\(i)"
            streamSubscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        }
        
        // Give stream time to process
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
    }
    
    static func testNDKInstance() async {
        print("Creating NDK instance...")
        
        let ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://nos.lol",
                "wss://relay.nostr.band"
            ],
            cacheAdapter: NDKInMemoryCache()
        )
        
        print("✅ NDK instance created:")
        print("   Relays:       \(ndk.relays.count)")
        print("   Cache:        \(ndk.cacheAdapter != nil ? "Enabled" : "Disabled")")
        print("   Active user:  \(ndk.activeUser?.pubkey ?? "None")")
        
        print("\nRelay details:")
        for relay in ndk.relays {
            print("   📡 \(relay.normalizedURL)")
            print("      Status: \(relay.connectionState)")
        }
        
        // Test subscription creation
        let filter = NDKFilter(kinds: [EventKind.textNote], limit: 10)
        let subscription = ndk.subscribe(filters: [filter])
        
        print("\n✅ Created subscription:")
        print("   ID:      \(subscription.id)")
        print("   Filters: \(subscription.filters.count)")
        print("   Active:  \(subscription.isActive)")
        
        // Test cache functionality
        if let cache = ndk.cacheAdapter {
            let testEvent = NDKEvent(
                pubkey: "test_pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "Cached test event"
            )
            testEvent.id = "cached_event_id"
            
            await cache.setEvent(testEvent, filters: [filter], relay: nil)
            
            let cachedEvents = await cache.query(subscription: subscription)
            print("\n✅ Cache test:")
            print("   Stored events: 1")
            print("   Retrieved:     \(cachedEvents.count)")
        }
    }
    
    static func testUserProfiles() {
        print("Creating user profiles...")
        
        // Create NDK instance for user management
        let ndk = NDK()
        
        // Test user creation from pubkey
        let user1 = ndk.getUser("d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e")
        
        print("✅ User 1 created:")
        print("   Pubkey:       \(user1.pubkey)")
        print("   Short pubkey: \(user1.shortPubkey)")
        print("   Display name: \(user1.displayName ?? "Not set")")
        
        // Set profile
        let profile1 = NDKUserProfile(
            name: "alice",
            displayName: "Alice",
            about: "NDKSwift test user",
            picture: "https://example.com/alice.jpg",
            nip05: "alice@example.com"
        )
        user1.updateProfile(profile1)
        
        print("\n✅ Profile updated:")
        print("   Name:         \(user1.profile?.name ?? "N/A")")
        print("   Display name: \(user1.displayName ?? "N/A")")
        print("   About:        \(user1.profile?.about ?? "N/A")")
        print("   NIP-05:       \(user1.profile?.nip05 ?? "N/A")")
        
        // Test user creation from npub
        do {
            let npub = try Bech32.npub(from: "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")
            let user2 = ndk.getUser(npub: npub)
            
            print("\n✅ User 2 created from npub:")
            print("   npub:         \(npub)")
            if let user2 = user2 {
                print("   Pubkey:       \(user2.pubkey)")
                print("   Short pubkey: \(user2.shortPubkey)")
            }
        } catch {
            print("\n❌ Failed to create user from npub: \(error)")
        }
        
        // Test multiple users
        print("\n✅ Testing multiple users:")
        let testPubkeys = [
            "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        ]
        
        for (index, pubkey) in testPubkeys.enumerated() {
            let user = ndk.getUser(pubkey)
            let name = "user\(index + 1)"
            user.updateProfile(NDKUserProfile(
                name: name,
                displayName: "Test User \(index + 1)"
            ))
            print("   \(name): \(user.displayName ?? "Unknown") - \(user.shortPubkey)")
        }
    }
}