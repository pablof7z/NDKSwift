import Foundation
import NDKSwift

struct Example03_Subscribe {
    static func run() async throws {
        print("📡 NDKSwift Example: Subscribe to Events")
        print("========================================\n")
        
        // Step 1: Setup NDK
        let ndk = NDK(relayUrls: [RelayConstants.primal, RelayConstants.damus])
        await ndk.connect()
        print("✅ Connected to relays")
        
        // Step 2: Create a filter for subscription
        // Let's subscribe to text notes (kind 1) from the last 5 minutes
        let filter = NDKFilter(
            kinds: [EventKind.textNote],
            since: Timestamp(Date().addingTimeInterval(-300).timeIntervalSince1970), // 5 minutes ago
            limit: 10
        )
        
        print("\n📋 Subscribing to recent text notes...")
        print("🔍 Filter: kind=1, last 5 minutes, limit=10")
        
        // Step 3: Method 1 - Fetch events using observe with cache
        print("\n1️⃣ Fetching events (from cache and relays):")
        let dataSource = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)
        
        // Collect events for a short time
        var collectedEvents: [NDKEvent] = []
        let collectTask = Task {
            for await event in dataSource.events {
                collectedEvents.append(event)
                if collectedEvents.count >= 10 {
                    break
                }
            }
        }
        
        // Wait a bit then stop collecting
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        collectTask.cancel()
        
        let observer1Count = collectedEvents.count
        print("📊 Found \(observer1Count) events")
        
        for event in collectedEvents.prefix(3) {
            print("\n📝 Event from \(String(event.pubkey.prefix(8)))...")
            print("   Content: \(String(event.content.prefix(50)))...")
            print("   Created: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
        }
        
        // Step 4: Method 2 - Subscribe to real-time events only
        print("\n2️⃣ Subscribing to real-time events (10 seconds):")
        let realtimeFilter = NDKFilter(
            kinds: [EventKind.textNote],
            since: Timestamp(Date().timeIntervalSince1970), // From now
            limit: 10
        )
        let realtimeSource = ndk.subscribe(filter: realtimeFilter, cachePolicy: .networkOnly)
        
        // Use a task to handle timeout
        var observer2Count = 0
        let subscriptionTask = Task {
            for await event in realtimeSource.events {
                observer2Count += 1
                print("\n🔔 New event #\(observer2Count) from \(String(event.pubkey.prefix(8)))...")
                print("   Content: \(String(event.content.prefix(50)))...")
                
                if observer2Count >= 5 {
                    print("\n✅ Received 5 events, stopping subscription")
                    break
                }
            }
        }
        
        // Wait for up to 10 seconds
        try await Task.sleep(nanoseconds: 10_000_000_000)
        subscriptionTask.cancel()
        
        // Step 5: Subscribe with specific authors
        print("\n3️⃣ Subscribe to specific authors:")
        
        // Using NDKSubscription for real-time event streaming (recommended approach)
        let authors = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"  // fiatjaf
        ]
        
        let authorFilter = NDKFilter(
            authors: authors,
            kinds: [EventKind.textNote],
            limit: 5
        )
        
        let authorSource = ndk.subscribe(filter: authorFilter, cachePolicy: .cacheWithNetwork)
        var authorEvents: [NDKEvent] = []
        
        let authorTask = Task {
            for await event in authorSource.events {
                authorEvents.append(event)
                if authorEvents.count >= 5 {
                    break
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        authorTask.cancel()
        
        let observer3Count = authorEvents.count
        print("📊 Found \(observer3Count) events from specified authors")
        
        // Step 6: Disconnect
        await ndk.disconnect()
        
        // Summary of all observers
        print("\n📊 SUMMARY - Event counts for each observer:")
        print("===========================================")
        print("1️⃣ Observer 1 (cache + network, recent 5min): \(observer1Count) events")
        print("2️⃣ Observer 2 (network only, real-time):      \(observer2Count) events")
        print("3️⃣ Observer 3 (specific authors):             \(observer3Count) events")
        print("===========================================")
        print("Total events observed: \(observer1Count + observer2Count + observer3Count) events")
        
        print("\n📚 Key Concepts:")
        print("- Filters define what events you want to receive")
        print("- observe() creates a data source for events")
        print("- Different cache policies control where events come from")
        print("- DataSources return AsyncSequence for easy iteration")
        print("- Always clean up subscriptions when done")
    }
}