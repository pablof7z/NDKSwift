import Foundation
import NDKSwift

/// E2E Test: Basic Event Publishing and Retrieval
/// Tests the fundamental flow of creating, signing, publishing, and retrieving events
@main
struct TestBasicEventFlow {
    static func main() async {
        let startTime = Date()
        print("🧪 E2E Test: Basic Event Publishing and Retrieval")
        print("=================================================")
        print("Started at: \(formatTimestamp(startTime))\n")
        
        // Configure logging
        NDKLogger.logLevel = .debug
        NDKLogger.logNetworkTraffic = true
        
        do {
            // Step 1: Initialize NDK with in-memory cache
            print("📦 Step 1: Initializing NDK...")
            let ndk = NDK(cache: MemoryCache())
            print("✅ NDK initialized at \(elapsedTime(from: startTime))")
            
            // Step 2: Create signer and set up NDK
            print("\n🔑 Step 2: Creating signer...")
            let signer = try NDKPrivateKeySigner.generate()
            let pubkey = try await signer.pubkey
            ndk.signer = signer
            print("✅ Generated keypair at \(elapsedTime(from: startTime))")
            print("   Public key: \(String(pubkey.prefix(16)))...")
            
            // Step 3: Connect to relays
            print("\n🌐 Step 3: Connecting to relays...")
            let relays = [
                "wss://relay.damus.io",
                "wss://relay.nostr.band",
                "wss://nos.lol"
            ]
            
            for relayURL in relays {
                await ndk.addRelay(relayURL)
            }
            
            await ndk.connect()
            
            // Wait for at least one relay to connect
            let connectionStart = Date()
            let connectedCount = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
            let connectionTime = Date().timeIntervalSince(connectionStart)
            
            if connectedCount == 0 {
                print("❌ No relays connected after 10 seconds")
                return
            }
            
            print("✅ Connected to \(connectedCount) relay(s) in \(String(format: "%.2f", connectionTime))s at \(elapsedTime(from: startTime))")
            
            // Print connection details
            let relayDetails = await ndk.relays
            for relay in relayDetails {
                let status = await relay.connectionState
                print("   - \(relay.url): \(status)")
            }
            
            // Step 4: Create and publish a test event
            print("\n📝 Step 4: Creating and publishing test event...")
            let testContent = "E2E Test Event - \(ISO8601DateFormatter().string(from: Date()))"
            let publishStart = Date()
            
            let event = try await ndk.event()
                .content(testContent)
                .kind(1) // Text note
                .tags([
                    ["client", "NDKSwift-E2E-Test"],
                    ["test-id", UUID().uuidString]
                ])
                .build()
            
            print("✅ Event created and signed at \(elapsedTime(from: startTime))")
            print("   Event ID: \(event.id)")
            
            // Publish the event
            let publishedRelays = try await ndk.publish(event)
            let publishTime = Date().timeIntervalSince(publishStart)
            
            print("✅ Event published to \(publishedRelays.count) relay(s) in \(String(format: "%.2f", publishTime))s")
            for relay in publishedRelays {
                print("   - Published to: \(relay)")
            }
            
            // Step 5: Retrieve the event using observe() API
            print("\n🔍 Step 5: Retrieving published event...")
            let fetchStart = Date()
            
            let filter = NDKFilter(
                authors: [pubkey],
                kinds: [1],
                limit: 10
            )
            
            let dataSource = ndk.observe(
                filter: filter,
                maxAge: 0, // Force fresh data
                cachePolicy: .networkOnly
            )
            
            // Wait for the event to arrive
            var foundEvent: NDKEvent? = nil
            let timeout = Date().addingTimeInterval(5.0)
            
            for await retrievedEvent in dataSource.events {
                print("   Received event: \(retrievedEvent.id)")
                if retrievedEvent.id == event.id {
                    foundEvent = retrievedEvent
                    break
                }
                
                if Date() > timeout {
                    print("   ⏱️ Timeout reached")
                    break
                }
            }
            
            let fetchTime = Date().timeIntervalSince(fetchStart)
            
            if let foundEvent = foundEvent {
                print("✅ Successfully retrieved event in \(String(format: "%.2f", fetchTime))s")
                print("   Content matches: \(foundEvent.content == testContent)")
                print("   Signature valid: \(foundEvent.verifySignature())")
            } else {
                print("❌ Failed to retrieve published event within timeout")
            }
            
            // Step 6: Test cache functionality
            print("\n💾 Step 6: Testing cache functionality...")
            let cacheStart = Date()
            
            // The event should now be in cache
            let cachedEvents = dataSource.data
            let cacheTime = Date().timeIntervalSince(cacheStart)
            
            if let cachedEvent = cachedEvents.first(where: { $0.id == event.id }) {
                print("✅ Event found in cache in \(String(format: "%.3f", cacheTime * 1000))ms")
                print("   Cache contains \(cachedEvents.count) total events")
            } else {
                print("⚠️  Event not found in cache")
            }
            
            // Disconnect
            print("\n🔌 Disconnecting...")
            await ndk.disconnect()
            
            let totalTime = Date().timeIntervalSince(startTime)
            print("\n✅ Test completed in \(String(format: "%.2f", totalTime))s")
            
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