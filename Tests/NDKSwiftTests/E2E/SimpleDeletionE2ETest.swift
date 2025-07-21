import XCTest
@testable import NDKSwift

final class SimpleDeletionE2ETest: XCTestCase {
    
    func testBasicDeletion() async throws {
        print("\n🧪 Starting Basic Deletion E2E Test")
        let startTime = Date()
        
        // Configure logging
        NDKLogger.logLevel = .info
        NDKLogger.enabledCategories = [.event, .relay, .network]
        
        // Create NDK instances
        let publisher = NDK(cache: MemoryCache())
        let subscriber = NDK(cache: MemoryCache())
        
        // Create signer
        let signer = try NDKPrivateKeySigner.generate()
        publisher.signer = signer
        
        // Add relay
        let relayURL = "wss://relay.damus.io"
        await publisher.addRelay(relayURL)
        await subscriber.addRelay(relayURL)
        
        // Connect
        await publisher.connect()
        await subscriber.connect()
        
        print("⏱️ Connected after \(Date().timeIntervalSince(startTime))s")
        
        // Wait for connection
        let publisherConnected = await publisher.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let subscriberConnected = await subscriber.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        
        guard publisherConnected > 0 && subscriberConnected > 0 else {
            XCTFail("Failed to connect to relay")
            return
        }
        
        // Create and publish event
        print("📤 Publishing event...")
        let (event, _) = try await publisher.publish { builder in
            builder
                .content("Test event for deletion - \(UUID())")
                .kind(EventKind.textNote)
        }
        
        print("Published event: \(event.id)")
        
        // Wait for propagation
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Verify event exists
        print("🔍 Fetching event...")
        let filter = NDKFilter(ids: [event.id])
        let dataSource = subscriber.observe(filter: filter, maxAge: 3600)
        
        var found = false
        for await e in dataSource.events {
            if e.id == event.id {
                found = true
                break
            }
        }
        
        XCTAssertTrue(found, "Event should exist before deletion")
        print("✅ Event found")
        
        // Publish deletion
        print("🗑️ Publishing deletion...")
        let (_, delRelays) = try await publisher.publish { builder in
            builder
                .content("Deleting event")
                .kind(EventKind.deletion)
                .tag(["e", event.id])
                .tag(["k", String(event.kind)])
        }
        
        print("Published deletion to \(delRelays.count) relays")
        
        // Wait for deletion
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Verify deletion
        print("🔍 Checking if event was deleted...")
        let checkSource = subscriber.observe(filter: filter, maxAge: 3600)
        
        var stillExists = false
        let checkStart = Date()
        for await e in checkSource.events {
            if e.id == event.id {
                stillExists = true
            }
            if Date().timeIntervalSince(checkStart) > 2.0 {
                break
            }
        }
        
        XCTAssertFalse(stillExists, "Event should be deleted")
        print("✅ Event successfully deleted")
        
        // Cleanup
        await publisher.disconnect()
        await subscriber.disconnect()
        
        print("✅ Test completed in \(Date().timeIntervalSince(startTime))s\n")
    }
}