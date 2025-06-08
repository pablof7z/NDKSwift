#!/usr/bin/env swift

import Foundation
import NDKSwift

// MARK: - Comprehensive NDKSwift Demo Application

// This example demonstrates all major features of NDKSwift

class NostrDemo {
    private let ndk: NDK
    private let signer: NDKPrivateKeySigner
    private let user: NDKUser

    init() async throws {
        print("🚀 Starting NDKSwift Demo...")

        // Generate a new private key for this demo
        let privateKey = try CryptoUtils.generatePrivateKey()
        let publicKey = try CryptoUtils.publicKey(from: privateKey)

        print("📱 Generated demo identity:")
        print("   Private Key: \(privateKey)")
        print("   Public Key: \(publicKey)")

        // Create signer and user
        self.signer = NDKPrivateKeySigner(privateKey: privateKey)
        self.user = NDKUser(pubkey: publicKey)

        // Set up profile
        let profile = NDKUserProfile(
            name: "ndkswift_demo",
            displayName: "NDKSwift Demo",
            about: "Demonstrating NDKSwift functionality",
            picture: "https://nostr.build/i/nostr.jpg",
            nip05: "demo@ndkswift.example"
        )
        user.updateProfile(profile)

        // Initialize NDK with demo relays
        self.ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://nos.lol",
                "wss://relay.nostr.band",
            ],
            signer: signer,
            cacheAdapter: NDKInMemoryCache()
        )

        print("✅ NDKSwift initialized with \(ndk.relays.count) relays")
    }

    // MARK: - Main Demo Function

    func run() async {
        do {
            await demonstrateBech32Encoding()
            await demonstrateEventCreation()
            await demonstrateSubscriptions()
            await demonstrateRelayConnections()
            await demonstrateFiltering()
            await demonstrateCaching()
            await demonstrateUserProfiles()

            print("\n🎉 Demo completed successfully!")

        } catch {
            print("❌ Demo failed with error: \(error)")
        }
    }

    // MARK: - Bech32 Encoding Demo

    private func demonstrateBech32Encoding() async {
        print("\n📝 === Bech32 Encoding Demo ===")

        do {
            // Test npub encoding
            let npub = try Bech32.npub(from: user.pubkey)
            let decodedPubkey = try Bech32.pubkey(from: npub)

            print("Original pubkey: \(user.pubkey)")
            print("Encoded npub:    \(npub)")
            print("Decoded pubkey:  \(decodedPubkey)")
            print("✅ Round-trip successful: \(user.pubkey == decodedPubkey)")

            // Test nsec encoding
            let nsec = try Bech32.nsec(from: signer.privateKey)
            let decodedPrivkey = try Bech32.privateKey(from: nsec)

            print("\nPrivate key encoded as nsec: \(nsec)")
            print("✅ Private key round-trip successful: \(signer.privateKey == decodedPrivkey)")

        } catch {
            print("❌ Bech32 encoding failed: \(error)")
        }
    }

    // MARK: - Event Creation Demo

    private func demonstrateEventCreation() async {
        print("\n📄 === Event Creation Demo ===")

        do {
            // Create a text note
            let textNote = NDKEvent(
                pubkey: user.pubkey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "Hello Nostr! This is a demo message from NDKSwift 🎉"
            )

            // Add hashtags
            textNote.addTag(["t", "ndkswift"])
            textNote.addTag(["t", "nostr"])
            textNote.addTag(["t", "demo"])

            // Generate ID and sign
            let eventId = try textNote.generateID()
            textNote.sig = try await signer.sign(textNote)

            print("Created and signed text note:")
            print("   ID: \(eventId)")
            print("   Content: \(textNote.content)")
            print("   Tags: \(textNote.tags.count) tags")
            print("   Signature: \(textNote.sig?.prefix(16) ?? "")...")

            // Validate the event
            try textNote.validate()
            print("✅ Event validation successful")

            // Create a reply event
            let replyEvent = NDKEvent(
                pubkey: user.pubkey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.textNote,
                content: "This is a reply to my previous message!"
            )

            // Tag the original event
            replyEvent.addTag(["e", eventId, "", "reply"])
            replyEvent.addTag(["p", user.pubkey])

            let replyId = try replyEvent.generateID()
            print("\nCreated reply event: \(replyId)")
            print("✅ References original event: \(replyEvent.isReply)")

        } catch {
            print("❌ Event creation failed: \(error)")
        }
    }

    // MARK: - Subscription Demo

    private func demonstrateSubscriptions() async {
        print("\n📡 === Subscription Demo ===")

        // Demo 1: One-shot fetch using new API
        print("\n1️⃣ One-shot fetch demo:")
        let recentFilter = NDKFilter(
            kinds: [EventKind.textNote],
            since: Timestamp(Date().timeIntervalSince1970 - 3600), // Last hour
            limit: 5
        )
        
        do {
            let recentEvents = try await ndk.fetchEvents(recentFilter)
            print("Fetched \(recentEvents.count) recent events")
            for event in recentEvents.prefix(3) {
                print("   - \(event.content.prefix(50))...")
            }
        } catch {
            print("❌ Failed to fetch events: \(error)")
        }

        // Demo 2: Continuous subscription using AsyncStream
        print("\n2️⃣ Continuous subscription demo:")
        let liveFilter = NDKFilter(
            kinds: [EventKind.textNote],
            limit: 10
        )
        
        let subscription = ndk.subscribe(filters: [liveFilter])
        
        print("Created subscription with filter:")
        print("   Kinds: \(liveFilter.kinds ?? [])")
        print("   Limit: \(liveFilter.limit ?? 0)")
        
        // Simulate some events (since we're not connected to real relays)
        print("\n🧪 Simulating received events...")
        Task {
            // Simulate events arriving
            for i in 1 ... 3 {
                let simulatedEvent = NDKEvent(
                    pubkey: "demo\(i)",
                    createdAt: Timestamp(Date().timeIntervalSince1970),
                    kind: EventKind.textNote,
                    content: "Simulated event #\(i) for testing"
                )
                simulatedEvent.id = "sim_event_\(i)"
                subscription.handleEvent(simulatedEvent, fromRelay: nil)
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            subscription.handleEOSE()
        }
        
        // Demo 3: Handle events with the new AsyncStream API
        print("\n3️⃣ AsyncStream iteration demo:")
        var eventCount = 0
        
        // Create a task to handle the subscription
        let subscriptionTask = Task {
            for await update in subscription.updates {
                switch update {
                case .event(let event):
                    eventCount += 1
                    print("📨 Received event \(eventCount): \(event.content.prefix(50))...")
                case .eose:
                    print("🏁 End of stored events reached")
                    break // Exit the loop on EOSE for demo
                case .error(let error):
                    print("❌ Subscription error: \(error)")
                }
            }
        }
        
        // Wait a bit for events to be processed
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        subscriptionTask.cancel()
        
        print("\n✅ Subscription demo completed")
        print("   Events received: \(eventCount)")
    }

    // MARK: - Relay Connection Demo

    private func demonstrateRelayConnections() async {
        print("\n🔗 === Relay Connection Demo ===")

        for relay in ndk.relays {
            print("Relay: \(relay.url)")
            print("   Normalized URL: \(relay.normalizedURL)")
            print("   Connection State: \(relay.connectionState)")
            print("   Messages Sent: \(relay.stats.messagesSent)")
            print("   Messages Received: \(relay.stats.messagesReceived)")

            // Observe connection state changes
            relay.observeConnectionState { state in
                switch state {
                case .disconnected:
                    print("   📡 \(relay.url): Disconnected")
                case .connecting:
                    print("   🔄 \(relay.url): Connecting...")
                case .connected:
                    print("   ✅ \(relay.url): Connected!")
                case .disconnecting:
                    print("   ⏹️ \(relay.url): Disconnecting...")
                case let .failed(error):
                    print("   ❌ \(relay.url): Failed - \(error)")
                }
            }
        }

        print("\n🔌 Attempting to connect to relays...")
        await ndk.connect()

        // Wait a moment for connection attempts
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        print("Connection attempts completed")
    }

    // MARK: - Filtering Demo

    private func demonstrateFiltering() async {
        print("\n🔍 === Filtering Demo ===")

        // Create test events
        let events = [
            createTestEvent(author: "alice", kind: 1, content: "Hello from Alice!"),
            createTestEvent(author: "bob", kind: 1, content: "Bob here!"),
            createTestEvent(author: "alice", kind: 3, content: "Alice's contact list"),
            createTestEvent(author: "charlie", kind: 1, content: "Charlie speaking"),
        ]

        // Test different filters
        let filters = [
            NDKFilter(authors: ["alice"], label: "Alice's events"),
            NDKFilter(kinds: [1], label: "Text notes only"),
            NDKFilter(authors: ["alice"], kinds: [1], label: "Alice's text notes"),
        ]

        for filter in filters {
            let matches = events.filter { filter.matches(event: $0) }
            print("Filter '\(filter.label ?? "Unlabeled")': \(matches.count) matches")
            for match in matches {
                print("   - \(match.content)")
            }
        }

        // Test filter merging
        let filter1 = NDKFilter(authors: ["alice", "bob"], kinds: [1, 3])
        let filter2 = NDKFilter(authors: ["bob", "charlie"], kinds: [1, 2])

        if let merged = filter1.merged(with: filter2) {
            print("\nMerged filter result:")
            print("   Authors: \(merged.authors ?? [])")
            print("   Kinds: \(merged.kinds ?? [])")
        } else {
            print("\nFilters could not be merged (no overlap)")
        }
    }

    // MARK: - Caching Demo

    private func demonstrateCaching() async {
        print("\n💾 === Caching Demo ===")

        guard let cache = ndk.cacheAdapter else {
            print("❌ No cache adapter configured")
            return
        }

        // Create some test events
        let events = [
            createTestEvent(author: user.pubkey, kind: 1, content: "Cached message 1"),
            createTestEvent(author: user.pubkey, kind: 1, content: "Cached message 2"),
            createTestEvent(author: "other", kind: 3, content: "Someone else's contact list"),
        ]

        // Store events in cache
        let filter = NDKFilter(authors: [user.pubkey], kinds: [1])
        for event in events {
            await cache.setEvent(event, filters: [filter], relay: nil)
        }

        print("Stored \(events.count) events in cache")

        // Query cache
        let subscription = NDKSubscription(filters: [filter])
        let cachedEvents = await cache.query(subscription: subscription)

        print("Retrieved \(cachedEvents.count) events from cache:")
        for event in cachedEvents {
            print("   - \(event.content)")
        }

        // Test profile caching
        await cache.saveProfile(pubkey: user.pubkey, profile: user.profile!)
        if let cachedProfile = await cache.fetchProfile(pubkey: user.pubkey) {
            print("\nCached profile retrieved:")
            print("   Name: \(cachedProfile.name ?? "Unknown")")
            print("   About: \(cachedProfile.about ?? "No bio")")
        }
    }

    // MARK: - User Profile Demo

    private func demonstrateUserProfiles() async {
        print("\n👤 === User Profile Demo ===")

        print("Demo user profile:")
        print("   Pubkey: \(user.pubkey)")
        print("   Short pubkey: \(user.shortPubkey)")
        print("   Name: \(user.profile?.name ?? "Unknown")")
        print("   Display name: \(user.displayName)")
        print("   About: \(user.profile?.about ?? "No bio")")
        print("   NIP-05: \(user.profile?.nip05 ?? "Not verified")")

        // Test npub conversion
        do {
            let npub = try Bech32.npub(from: user.pubkey)
            let userFromNpub = ndk.getUser(npub: npub)
            print("\nCreated user from npub: \(npub)")
            print("   Matches original: \(userFromNpub?.pubkey == user.pubkey)")
        } catch {
            print("❌ Error with npub conversion: \(error)")
        }

        // Create additional test users
        let testUsers = [
            ("Alice", "alice123", "Alice loves Nostr and decentralization"),
            ("Bob", "bob456", "Bitcoin maximalist and Nostr enthusiast"),
            ("Charlie", "charlie789", "Building the future of social media"),
        ]

        print("\nCreated test users:")
        for (name, pubkey, about) in testUsers {
            let testUser = ndk.getUser(pubkey)
            let profile = NDKUserProfile(name: name.lowercased(), displayName: name, about: about)
            testUser.updateProfile(profile)
            print("   \(name): \(testUser.displayName) - \(testUser.shortPubkey)")
        }
    }

    // MARK: - Helper Methods

    private func createTestEvent(author: String, kind: Kind, content: String) -> NDKEvent {
        let event = NDKEvent(
            pubkey: author,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            content: content
        )
        event.id = "test_\(UUID().uuidString.prefix(8))"
        return event
    }
}


// MARK: - NDKFilter Extension for Demo

extension NDKFilter {
    var label: String? {
        get { return nil }
        set { /* Demo purposes only */ }
    }

    convenience init(authors: [String]? = nil, kinds: [Kind]? = nil, label _: String) {
        self.init(authors: authors, kinds: kinds)
        // In a real implementation, you'd store the label properly
    }
}

// MARK: - Main Execution

@main
struct NostrDemoApp {
    static func main() async {
        do {
            let demo = try await NostrDemo()
            await demo.run()
        } catch {
            print("❌ Failed to start demo: \(error)")
            exit(1)
        }
    }
}
