import Foundation
import NDKSwift

/// E2E Test: Relay Connection and Subscription Management
/// Tests relay management, connection handling, and subscription lifecycle
@main
struct E2ETestRelaySubscription {
    static func main() async {
        let startTime = Date()
        print("🧪 E2E Test: Relay Connection and Subscription Management")
        print("=======================================================")
        print("Started at: \(formatTimestamp(startTime))\n")
        
        // Configure logging
        NDKLogger.logLevel = .debug
        NDKLogger.logNetworkTraffic = false // Don't log all traffic for this test
        
        do {
            // Step 1: Initialize NDK with SQLite cache
            print("📦 Step 1: Initializing NDK with SQLite cache...")
            let cacheURL = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ndkswift-e2e-test-relay.db")
            
            // Clean up any previous test cache
            try? FileManager.default.removeItem(at: cacheURL)
            
            let cache = try NDKSQLiteCache(databasePath: cacheURL.path)
            let ndk = NDK(cache: cache)
            print("✅ NDK initialized with SQLite cache at \(elapsedTime(from: startTime))")
            
            // Step 2: Test relay addition and connection
            print("\n🌐 Step 2: Testing relay addition and connection...")
            let relayStart = Date()
            
            // Test multiple relays
            let testRelays = [
                "wss://relay.damus.io",
                "wss://relay.nostr.band",
                "wss://nos.lol"
            ]
            
            // Add relays one by one
            for relayURL in testRelays {
                let relay = await ndk.addRelay(relayURL)
                print("   Added relay: \(relay.url)")
            }
            
            // Connect to all
            await ndk.connect()
            
            // Wait for connections
            let connectedCount = await ndk.waitForRelayConnections(minimumRelays: 2, timeout: 10.0)
            let connectionTime = Date().timeIntervalSince(relayStart)
            
            print("✅ Connected to \(connectedCount)/\(testRelays.count) relays in \(String(format: "%.2f", connectionTime))s")
            
            // Step 3: Test relay state monitoring
            print("\n📊 Step 3: Testing relay state monitoring...")
            let relays = await ndk.relays
            
            for relay in relays {
                let state = await relay.connectionState
                let stats = await relay.stats
                print("   \(relay.url):")
                print("     State: \(state)")
                print("     Stats: Sent=\(stats.messagesSent), Received=\(stats.messagesReceived)")
            }
            
            // Step 4: Test relay pool changes monitoring
            print("\n🔄 Step 4: Testing relay pool change events...")
            
            // Start monitoring changes
            let monitorTask = Task {
                var changeCount = 0
                for await change in await ndk.relayChanges {
                    changeCount += 1
                    print("   Pool change #\(changeCount): \(change)")
                    
                    if changeCount >= 2 {
                        break // Exit after seeing 2 changes
                    }
                }
            }
            
            // Trigger changes
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            let newRelay = await ndk.addRelay("wss://relay.primal.net")
            print("   Added new relay: \(newRelay.url)")
            
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            await ndk.removeRelay("wss://relay.primal.net")
            print("   Removed relay: wss://relay.primal.net")
            
            // Wait for monitor task to complete
            await monitorTask.value
            
            // Step 5: Test subscription management
            print("\n📡 Step 5: Testing subscription lifecycle...")
            
            // Create a test filter
            let filter = NDKFilter(
                kinds: [1],
                limit: 5,
                since: Timestamp.now - 3600
            )
            
            // Start subscription
            let dataSource = ndk.observe(
                filter: filter,
                maxAge: 0, // Real-time
                cachePolicy: .networkOnly
            )
            
            print("   Started subscription with filter:")
            print("     Kinds: \(filter.kinds ?? [])")
            print("     Limit: \(filter.limit ?? 0)")
            print("     Since: last hour")
            
            // Collect some events
            var receivedCount = 0
            let timeout = Date().addingTimeInterval(3.0)
            
            for await event in dataSource.events {
                receivedCount += 1
                print("   Received event #\(receivedCount): \(String(event.id.prefix(8)))... from \(event.receivedFrom.first ?? "unknown")")
                
                if receivedCount >= 3 || Date() > timeout {
                    break
                }
            }
            
            print("   Received \(receivedCount) events total")
            
            // Step 6: Test connection recovery
            print("\n🔧 Step 6: Testing connection recovery...")
            
            // Force disconnect a relay
            if let firstRelay = relays.first {
                print("   Disconnecting \(firstRelay.url)...")
                await firstRelay.disconnect()
                
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                
                let stateAfterDisconnect = await firstRelay.connectionState
                print("   State after disconnect: \(stateAfterDisconnect)")
                
                // Trigger reconnect by trying to use it
                print("   Triggering reconnection...")
                let testFilter = NDKFilter(kinds: [0], limit: 1)
                let reconnectDataSource = ndk.observe(
                    filter: testFilter,
                    maxAge: 0,
                    cachePolicy: .networkOnly,
                    relays: [firstRelay.url]
                )
                
                // Wait a bit
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                
                let stateAfterReconnect = await firstRelay.connectionState
                print("   State after reconnect attempt: \(stateAfterReconnect)")
            }
            
            // Step 7: Test relay-specific subscriptions
            print("\n🎯 Step 7: Testing relay-specific subscriptions...")
            
            let specificRelay = "wss://relay.damus.io"
            let specificFilter = NDKFilter(
                kinds: [0], // User metadata
                limit: 3
            )
            
            let specificDataSource = ndk.observe(
                filter: specificFilter,
                maxAge: 0,
                cachePolicy: .networkOnly,
                relays: [specificRelay]
            )
            
            print("   Subscribing only to \(specificRelay)...")
            
            var specificCount = 0
            let specificTimeout = Date().addingTimeInterval(3.0)
            
            for await event in specificDataSource.events {
                specificCount += 1
                print("   Received profile #\(specificCount) from \(event.receivedFrom.first ?? "unknown")")
                
                if specificCount >= 2 || Date() > specificTimeout {
                    break
                }
            }
            
            // Step 8: Clean shutdown
            print("\n🔌 Step 8: Testing clean shutdown...")
            
            let shutdownStart = Date()
            await ndk.disconnect()
            let shutdownTime = Date().timeIntervalSince(shutdownStart)
            
            print("✅ All relays disconnected in \(String(format: "%.2f", shutdownTime))s")
            
            // Verify all disconnected
            let finalRelays = await ndk.relays
            for relay in finalRelays {
                let state = await relay.connectionState
                print("   \(relay.url): \(state)")
            }
            
            let totalTime = Date().timeIntervalSince(startTime)
            print("\n✅ Test completed successfully in \(String(format: "%.2f", totalTime))s")
            
        } catch {
            print("\n❌ Test failed with error: \(error)")
            print("   Error type: \(type(of: error))")
            if let ndkError = error as? NDKError {
                print("   NDK Error: \(ndkError)")
            }
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