#!/usr/bin/env swift

import Foundation
import NDKSwift

// Example: Relay Tracking with NDKSwift
// This demonstrates how to track which relays events are published to and seen on

@main
struct RelayTrackingDemo {
    static func main() async {
        print("🔍 NDKSwift Relay Tracking Demo")
        print("================================\n")

        // Initialize NDK
        let ndk = NDK()

        // Add some relays
        _ = ndk.addRelay(url: "wss://relay.damus.io")
        _ = ndk.addRelay(url: "wss://nos.lol")
        _ = ndk.addRelay(url: "wss://relay.nostr.band")
        _ = ndk.addRelay(url: "wss://nostr.wine")

        // Create a signer
        let privateKey = NDKPrivateKeySigner.generateKey()
        guard let signer = NDKPrivateKeySigner(privateKey: privateKey) else {
            print("❌ Failed to create signer")
            return
        }

        ndk.signer = signer

        // Connect to relays
        print("📡 Connecting to relays...")
        await ndk.connect()

        // Wait a bit for connections
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Create an event
        let event = NDKEvent(ndk: ndk)
        event.kind = 1
        event.content = "Testing relay tracking! 🔍"
        event.pubkey = signer.publicKey()
        event.createdAt = Timestamp(Date().timeIntervalSince1970)

        print("\n📝 Publishing event...")

        do {
            // Publish the event
            let publishedRelays = try await ndk.publish(event: event)

            print("\n✅ Event published!")
            print("   Event ID: \(event.id ?? "unknown")")

            // Show detailed relay status
            print("\n📊 Relay Publishing Status:")
            for (relay, status) in event.relayPublishStatuses.sorted(by: { $0.key < $1.key }) {
                let statusIcon: String
                let statusText: String

                switch status {
                case .succeeded:
                    statusIcon = "✅"
                    statusText = "Success"
                case let .failed(reason):
                    statusIcon = "❌"
                    statusText = "Failed: \(reason)"
                case .pending:
                    statusIcon = "⏳"
                    statusText = "Pending"
                case .inProgress:
                    statusIcon = "🔄"
                    statusText = "In Progress"
                case .rateLimited:
                    statusIcon = "⚠️"
                    statusText = "Rate Limited"
                case let .retrying(attempt):
                    statusIcon = "🔁"
                    statusText = "Retrying (attempt \(attempt))"
                }

                print("   \(statusIcon) \(relay): \(statusText)")
            }

            // Summary
            print("\n📈 Publishing Summary:")
            print("   Total relays: \(event.relayPublishStatuses.count)")
            print("   Successful: \(event.successfullyPublishedRelays.count)")
            print("   Failed: \(event.failedPublishRelays.count)")
            print("   Published: \(event.wasPublished ? "Yes" : "No")")

            // List successful relays
            if !event.successfullyPublishedRelays.isEmpty {
                print("\n✅ Successfully published to:")
                for relay in event.successfullyPublishedRelays {
                    print("   - \(relay)")
                }
            }

            // List failed relays
            if !event.failedPublishRelays.isEmpty {
                print("\n❌ Failed to publish to:")
                for relay in event.failedPublishRelays {
                    print("   - \(relay)")
                }
            }

            // Now fetch the event to see where it's seen
            print("\n🔍 Fetching event to track where it's seen...")

            if let eventId = event.id {
                let filter = NDKFilter(ids: [eventId])
                let fetchedEvents = try await ndk.fetchEvents(filters: [filter])

                if let fetchedEvent = fetchedEvents.first {
                    print("\n👁️ Event seen on \(fetchedEvent.seenOnRelays.count) relay(s):")
                    for relay in fetchedEvent.seenOnRelays.sorted() {
                        print("   - \(relay)")
                    }

                    // Show which relay it came from
                    if let sourceRelay = fetchedEvent.relay {
                        print("\n📥 This copy received from: \(sourceRelay.url)")
                    }
                }
            }

            // Demonstrate subscription tracking
            print("\n📡 Setting up subscription to track new events...")

            let subFilter = NDKFilter(kinds: [1], limit: 5)
            let subscription = ndk.subscribe(filters: [subFilter]) { receivedEvent in
                print("\n🆕 New event received:")
                print("   ID: \(receivedEvent.id ?? "unknown")")
                print("   Author: \(receivedEvent.pubkey)")
                print("   Seen on relays: \(receivedEvent.seenOnRelays.joined(separator: ", "))")

                if let relay = receivedEvent.relay {
                    print("   Received from: \(relay.url)")
                }
            }

            // Wait for some events
            print("⏳ Waiting 5 seconds for events...")
            try await Task.sleep(nanoseconds: 5_000_000_000)

            subscription.close()

        } catch {
            print("❌ Error: \(error)")
        }

        // Disconnect
        await ndk.disconnect()
        print("\n✅ Demo completed!")
    }
}
