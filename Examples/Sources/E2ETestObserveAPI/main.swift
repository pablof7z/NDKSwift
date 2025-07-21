import Foundation
import NDKSwift

/// E2E Test: DataSource observe() API
/// Tests the declarative data access pattern with caching and real-time updates
@main
struct E2ETestObserveAPI {
    static func main() async {
        let startTime = Date()
        print("🧪 E2E Test: DataSource observe() API")
        print("=====================================")
        print("Started at: \(formatTimestamp(startTime))\n")
        
        // Configure logging
        NDKLogger.logLevel = .info
        
        do {
            // Step 1: Initialize with memory cache
            print("📦 Step 1: Initializing NDK with memory cache...")
            let ndk = NDK(cache: MemoryCache())
            let signer = try NDKPrivateKeySigner.generate()
            let pubkey = try await signer.pubkey
            ndk.signer = signer
            print("✅ NDK initialized")
            print("   Pubkey: \(String(pubkey.prefix(8)))...")
            
            // Step 2: Connect to relay
            print("\n🌐 Step 2: Connecting to relay...")
            await ndk.addRelay("wss://relay.damus.io")
            await ndk.connect()
            
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            print("✅ Connected")
            
            // Step 3: Test real-time observe (maxAge = 0)
            print("\n📡 Step 3: Testing real-time observe (maxAge = 0)...")
            
            let realtimeFilter = NDKFilter(
                kinds: [1],
                limit: 3
            )
            
            let realtimeDataSource = ndk.observe(
                filter: realtimeFilter,
                maxAge: 0, // Real-time only
                cachePolicy: .cacheWithNetwork
            )
            
            print("   Created real-time data source")
            print("   Waiting for events...")
            
            var realtimeCount = 0
            let realtimeTimeout = Date().addingTimeInterval(3.0)
            
            for await event in realtimeDataSource.events {
                realtimeCount += 1
                print("   Event #\(realtimeCount): \(String(event.id.prefix(8)))...")
                
                if realtimeCount >= 2 || Date() > realtimeTimeout {
                    break
                }
            }
            
            print("   Received \(realtimeCount) real-time events")
            
            // Step 4: Test cached observe (maxAge > 0)
            print("\n💾 Step 4: Testing cached observe (maxAge = 3600)...")
            
            // First, populate cache with our own event
            let testEvent = try await ndk.event()
                .content("Test event for cache - \(Date())")
                .kind(1)
                .build()
            
            _ = try await ndk.publish(testEvent)
            print("   Published test event: \(String(testEvent.id.prefix(8)))...")
            
            // Give it time to propagate
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            
            // Now create cached data source
            let cachedFilter = NDKFilter(
                authors: [pubkey],
                kinds: [1]
            )
            
            let cachedDataSource = ndk.observe(
                filter: cachedFilter,
                maxAge: 3600, // 1 hour cache
                cachePolicy: .cacheWithNetwork
            )
            
            // Check @Published property
            print("   Checking @Published data property...")
            let publishedData = cachedDataSource.data
            print("   Initial data count: \(publishedData.count)")
            
            // Also check events stream
            var cachedCount = 0
            let cacheTimeout = Date().addingTimeInterval(2.0)
            
            for await event in cachedDataSource.events {
                cachedCount += 1
                print("   Cached event: \(String(event.id.prefix(8)))...")
                
                if event.id == testEvent.id {
                    print("   ✅ Found our test event in cache!")
                }
                
                if cachedCount >= 5 || Date() > cacheTimeout {
                    break
                }
            }
            
            // Step 5: Test cache-only mode
            print("\n🔒 Step 5: Testing cache-only mode...")
            
            let cacheOnlyDataSource = ndk.observe(
                filter: cachedFilter,
                maxAge: 3600,
                cachePolicy: .cacheOnly
            )
            
            // Should get data immediately from cache
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            let cacheOnlyData = cacheOnlyDataSource.data
            print("   Cache-only data count: \(cacheOnlyData.count)")
            
            if cacheOnlyData.contains(where: { $0.id == testEvent.id }) {
                print("   ✅ Test event found in cache-only mode")
            }
            
            // Step 6: Test network-only mode
            print("\n🌐 Step 6: Testing network-only mode...")
            
            let networkOnlyDataSource = ndk.observe(
                filter: NDKFilter(kinds: [0], limit: 2), // User profiles
                maxAge: 0,
                cachePolicy: .networkOnly
            )
            
            var networkCount = 0
            let networkTimeout = Date().addingTimeInterval(3.0)
            
            for await event in networkOnlyDataSource.events {
                networkCount += 1
                print("   Network-only profile: \(String(event.pubkey.prefix(8)))...")
                
                if networkCount >= 2 || Date() > networkTimeout {
                    break
                }
            }
            
            print("   Received \(networkCount) network-only events")
            
            // Step 7: Test transform functionality
            print("\n🔄 Step 7: Testing transform functionality...")
            
            struct ProfileSummary {
                let pubkey: String
                let name: String?
            }
            
            let transformDataSource = ndk.observe(
                filter: NDKFilter(kinds: [0], limit: 3),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            ) { event -> ProfileSummary? in
                guard let profileData = event.content.data(using: .utf8),
                      let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) else {
                    return nil
                }
                return ProfileSummary(pubkey: event.pubkey, name: profile.name)
            }
            
            var transformCount = 0
            let transformTimeout = Date().addingTimeInterval(3.0)
            
            for await summary in transformDataSource.events {
                transformCount += 1
                print("   Profile: \(String(summary.pubkey.prefix(8)))... name: \(summary.name ?? "unknown")")
                
                if transformCount >= 2 || Date() > transformTimeout {
                    break
                }
            }
            
            // Cleanup
            print("\n🔌 Disconnecting...")
            await ndk.disconnect()
            
            let totalTime = Date().timeIntervalSince(startTime)
            print("\n✅ Test completed successfully in \(String(format: "%.2f", totalTime))s")
            
        } catch {
            print("\n❌ Test failed with error: \(error)")
        }
    }
    
    // Helper functions
    static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    static func elapsedTime(from start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        return String(format: "+%.3fs", elapsed)
    }
}