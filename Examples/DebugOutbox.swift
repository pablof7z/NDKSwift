import Foundation
import NDKSwift

@main
struct DebugOutbox {
    static func main() async {
        print("🔍 Starting debug outbox test...")
        
        // Create NDK instance with debug mode
        let ndk = NDK(relayUrls: ["wss://purplepag.es"])
        ndk.debugMode = true
        
        print("🔍 Connecting to relay...")
        await ndk.connect()
        
        // Wait for connection
        let connectedCount = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 5.0)
        print("🔍 Connected to \(connectedCount) relays")
        
        // Create a simple filter
        let filter = NDKFilter(
            authors: ["3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"],
            kinds: [1],
            limit: 1
        )
        
        print("🔍 Creating observer...")
        let observer = ndk.observe(filter: filter)
        
        print("🔍 Starting event iteration...")
        
        // Use a timeout task to prevent hanging forever
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            print("🔍 Timeout reached - no events received in 10 seconds")
            exit(1)
        }
        
        var eventCount = 0
        for await event in observer.events {
            eventCount += 1
            print("🔍 Received event #\(eventCount):")
            print("  - ID: \(event.id)")
            print("  - Content: \(event.content.prefix(100))...")
            
            if eventCount >= 1 {
                break
            }
        }
        
        timeoutTask.cancel()
        print("🔍 Test completed successfully!")
        exit(0)
    }
}