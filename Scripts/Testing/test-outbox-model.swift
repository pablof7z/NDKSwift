#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test example for outbox model:
// 1. Connects to relay.primal.net
// 2. Creates an event indicating it wants to publish to relay.damus.io
// 3. Validates that NDK connects to damus relay and publishes the event

@main
struct TestOutboxModel {
    static func main() async throws {
        print("🚀 Starting Outbox Model Test")
        print("This test will:")
        print("1. Connect to relay.primal.net")
        print("2. Create an event with p-tags indicating it should go to relay.damus.io")
        print("3. Verify that NDK connects to damus relay and publishes the event\n")
        
        // Create signer
        let privateKey = try NDKPrivateKey.generate()
        let signer = NDKPrivateKeySigner(privateKey: privateKey)
        let publicKey = signer.publicKey
        
        print("📝 Generated test keypair")
        print("Public key: \(publicKey.hex)")
        
        // Initialize NDK with primal relay
        let ndk = NDK(explicitRelayUrls: [RelayConstants.primal])
        
        // Set up tracking for relay connections and events
        var connectedRelays: Set<String> = []
        var publishedEvents: [(relay: String, eventId: String)] = []
        
        // Monitor relay connections
        Task {
            for await notification in NotificationCenter.default.notifications(named: .ndkRelayConnected) {
                if let relay = notification.object as? NDKRelay {
                    connectedRelays.insert(relay.url)
                    print("✅ Connected to relay: \(relay.url)")
                }
            }
        }
        
        // Monitor event publishing
        Task {
            for await notification in NotificationCenter.default.notifications(named: .ndkEventPublished) {
                if let userInfo = notification.userInfo,
                   let event = userInfo["event"] as? NDKEvent,
                   let relay = userInfo["relay"] as? NDKRelay {
                    publishedEvents.append((relay: relay.url, eventId: event.id))
                    print("📤 Published event \(event.id) to \(relay.url)")
                }
            }
        }
        
        // Connect to initial relay
        print("\n🔌 Connecting to relay.primal.net...")
        try await ndk.connect()
        
        // Wait a moment for connection
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Create test users to tag (these would normally be real pubkeys)
        let testUser1 = try NDKPrivateKey.generate().publicKey
        let testUser2 = try NDKPrivateKey.generate().publicKey
        
        // Create event with p-tags
        print("\n📝 Creating event with p-tags...")
        let event = try NDKEvent(
            kind: .text,
            content: "Test outbox model event - should be published to relay.damus.io",
            tags: [
                ["p", testUser1.hex, RelayConstants.damus, "mention"],
                ["p", testUser2.hex, RelayConstants.damus, "mention"]
            ],
            publicKey: publicKey
        )
        
        // Sign the event
        try await event.sign(withSigner: signer)
        print("✍️ Event signed: \(event.id)")
        
        // Publish the event
        print("\n📤 Publishing event...")
        let publishedRelays = try await event.publish(on: ndk)
        
        print("Published to \(publishedRelays.count) relay(s)")
        for relay in publishedRelays {
            print("  - \(relay.url)")
        }
        
        // Wait a bit to see if damus relay gets connected
        print("\n⏳ Waiting for outbox model to kick in...")
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Verify results
        print("\n📊 Results:")
        print("Connected relays: \(connectedRelays.sorted())")
        print("Published events:")
        for (relay, eventId) in publishedEvents {
            print("  - Event \(eventId) to \(relay)")
        }
        
        // Check if damus relay was connected to
        let damusConnected = connectedRelays.contains(RelayConstants.damus + "/")
        print("\n✅ Damus relay connected: \(damusConnected)")
        
        // Check if event was published to damus
        let publishedToDamus = publishedEvents.contains { $0.relay == RelayConstants.damus + "/" }
        print("✅ Event published to damus: \(publishedToDamus)")
        
        if damusConnected && publishedToDamus {
            print("\n🎉 SUCCESS: Outbox model working correctly!")
            print("Event was published to relay.damus.io based on p-tags")
        } else {
            print("\n❌ FAILURE: Outbox model did not work as expected")
            if !damusConnected {
                print("  - Did not connect to relay.damus.io")
            }
            if !publishedToDamus {
                print("  - Did not publish event to relay.damus.io")
            }
        }
        
        // Disconnect
        ndk.disconnect()
        print("\n👋 Test complete")
    }
}