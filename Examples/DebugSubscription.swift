import Foundation
import NDKSwift

@main
struct DebugSubscription {
    static func main() async throws {
        // Enable debug logging
        NDKLogger.logLevel = .debug
        
        print("🔍 DEBUG: Testing subscription flow\n")
        
        // Create NDK
        let ndk = NDK(relayUrls: ["wss://relay.primal.net"])
        
        // Connect
        await ndk.connect()
        print("\n✅ Connected to relay\n")
        
        // Create filter
        let filter = NDKFilter(kinds: [1])
        print("📋 Filter created: kinds=[\(filter.kinds?.map { String($0) }.joined(separator: ",") ?? "")], limit=\(filter.limit ?? 0)\n")
        
        // Create data source
        print("🎯 Creating data source...")
        let dataSource = ndk.observe(filter: filter, cachePolicy: .networkOnly)
        print("✅ Data source created\n")
        
        // Wait a bit to let subscription setup complete
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        print("⏳ Waiting for events (5 second timeout)...\n")
        
        var eventsReceived = 0
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            print("\n⏰ Timeout reached")
        }
        
        // Try to receive events
        for await event in dataSource.events {
            eventsReceived += 1
            print("\n🎉 EVENT RECEIVED IN DATA SOURCE!")
            print("   ID: \(event.id)")
            print("   Content: \(String(event.content.prefix(50)))...")
            timeoutTask.cancel()
            break
        }
        
        print("\n📊 Final result: \(eventsReceived) events received")
        
        if eventsReceived == 0 {
            print("❌ PROBLEM CONFIRMED: Events not reaching data source")
        } else {
            print("✅ Event flow working correctly")
        }
        
        await ndk.disconnect()
    }
}