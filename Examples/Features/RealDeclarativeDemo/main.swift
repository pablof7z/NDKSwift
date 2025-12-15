// Real Declarative API Demo with actual relay connections
// Run with: swift run --package-path Examples RealDeclarativeDemo

import Foundation
import NDKSwift

// Run the demo
@main
struct RealDeclarativeDemo {
    static func main() async {
        // Set a hard fucking timeout that actually exits
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            print("\n💀 HARD TIMEOUT - KILLING THIS SHIT")
            exit(1)
        }
        print("🚀 Starting minimal NDK test 2")
        print("============================\n")

        // Enable reasonable logging
        NDKLogger.setLogLevel(.info)
        NDKLogger.setLogNetworkTraffic(false)

        print("1. Creating NDK instance...")
        let ndk = NDK(relayUrls: [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.nostr.band",
        ])

        print("2. Connecting to relays...")
        await ndk.connect()

        print("3. Waiting for relays to connect...")
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)

        print("4. waitForRelayConnections returned: \(connected)")

        // Check if we can get relay status through public API
        print("\n5. Relay connection result: \(connected) relays connected")

        // Test observing some data
        print("\n6. Observing kind:1 events...")
        let filter = NDKFilter(kinds: [1], limit: 5)
        print("   Filter: \(filter)")
        let dataSource = ndk.subscribe(filter: filter)
        print("   DataSource created: \(dataSource)")

        // Count events received
        var eventCount = 0
        let startTime = Date()

        print("   Starting event iteration...")

        // Simple timeout approach
        var receivedAnyEvent = false
        let timeoutDate = Date().addingTimeInterval(5)

        for await event in dataSource.events {
            receivedAnyEvent = true
            eventCount += 1
            print("  📝 Event #\(eventCount): \(event.id)")
            print("     Author: \(event.pubkey)")
            print("     Content: \(String(event.content.prefix(100)))...")

            if eventCount >= 5 || Date() > timeoutDate {
                break
            }
        }

        if !receivedAnyEvent {
            print("\n❌ No events received!")
        } else {
            print("\n✅ Received \(eventCount) events!")
        }

        let duration = Date().timeIntervalSince(startTime)
        print("\nReceived \(eventCount) events in \(String(format: "%.2f", duration))s")

        print("\nTest completed!")

        // Exit to prevent hanging
        exit(0)
    }
}
