import Foundation
import NDKSwift

// Test against a real relay that supports NIP-77

@main
struct TestRealRelay {
    static func main() async {
        print("🔬 Testing Negentropy Against Real Relay")
        print("======================================\n")
        
        // Enable comprehensive logging
        NDKLogger.logLevel = .trace
        NDKLogger.logNetworkTraffic = true
        NDKLogger.prettyPrintNetworkMessages = true
        
        print("📊 Logging enabled:")
        print("  - Log Level: TRACE")
        print("  - Network Traffic: ON")
        print("  - Pretty Print: ON\n")
        
        do {
            let ndk = NDK()
            
            // Connect to strfry relay which supports NIP-77
            let relayURL = RelayConstants.nostrBand
            print("Connecting to \(relayURL)...")
            
            // Add relay and connect
            print("Adding relay to pool...")
            guard let relay = await ndk.addRelayAndConnect(relayURL) else {
                print("❌ Failed to add relay")
                exit(1)
            }
            
            print("Waiting for connection...")
            
            // Wait for connection with timeout
            let startTime = Date()
            let timeout: TimeInterval = 10.0
            
            while await !relay.isConnected {
                if Date().timeIntervalSince(startTime) > timeout {
                    print("❌ Connection timeout after \(timeout) seconds")
                    print("Connection state: \(await relay.connectionState)")
                    await ndk.disconnect()
                    exit(1)
                }
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            
            print("✅ Connected to \(relayURL)!")
            print("Connection stats: \(await relay.stats)")
            
            // First test: Basic event fetching
            print("\n📋 Test 1: Basic Event Fetching")
            print("================================")
            
            let basicFilter = NDKFilter(
                kinds: [1],
                limit: 5
            )
            
            print("Fetching 5 recent text notes...")
            
            // Use the declarative API with a one-shot fetch
            let dataSource = await ndk.observe(
                filter: basicFilter,
                maxAge: 0, // Force fresh data
                cachePolicy: .networkOnly
            )
            
            // Wait a moment for data to arrive
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let events = await dataSource.data
            print("✅ Fetched \(events.count) events!")
            
            if !events.isEmpty {
                print("\nSample event:")
                let event = events.first!
                print("  ID: \(event.id)")
                print("  Author: \(String(event.pubkey.prefix(16)))...")
                print("  Content: \(String(event.content.prefix(50)))...")
            } else {
                print("⚠️  No events received - relay might be empty or slow")
            }
            
            // Second test: NIP-77 sync (if basic fetch worked)
            print("\n🔄 Test 2: NIP-77 Negentropy Sync")
            print("==================================")
            
            let syncFilter = NDKFilter(
                kinds: [1],
                since: Timestamp.now - 3600, // Last hour
                limit: 10
            )
            
            print("Starting sync with filter:")
            print("  kinds: [1]")
            print("  since: last hour")
            print("  limit: 10\n")
            
            // Try the sync
            do {
                let result = try await ndk.syncEvents(
                    filter: syncFilter,
                    relay: relayURL
                )
                
                print("✅ Sync successful!")
                print("  Downloaded: \(result.downloadedEvents.count) events")
                print("  Uploaded: \(result.uploadedEvents.count) events")
                print("  Message rounds: \(result.messageRounds)")
                
            } catch {
                print("❌ Sync error: \(error)")
                
                // If it's a protocol error, let's see what the exact issue is
                if let ndkError = error as? NDKError {
                    print("\nNDKError details: \(ndkError)")
                }
                
                // Check if the relay supports NIP-77
                if error.localizedDescription.contains("NEG-OPEN") || 
                   error.localizedDescription.contains("unsupported") {
                    print("\n⚠️  This relay might not support NIP-77 Negentropy sync")
                    print("Consider trying one of these relays that support NIP-77:")
                    print("  - wss://relay.nostr.band")
                    print("  - wss://nostr.oxtr.dev")
                    print("  - wss://relay.damus.io")
                }
            }
            
            await ndk.disconnect()
            
        } catch {
            print("Error: \(error)")
        }
    }
}