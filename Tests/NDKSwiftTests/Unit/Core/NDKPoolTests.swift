import XCTest
@testable import NDKSwift

final class NDKPoolTests: NDKTestCase {
    
    // MARK: - Helper Methods
    
    private func createMockNDK() -> NDK {
        return createTestNDK()
    }
    
    func testAddRelay() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        let relayURL = "wss://relay.example.com"
        let relay = await pool.addRelay(relayURL)
        
        XCTAssertEqual(relay.url, "wss://relay.example.com/")
        
        let relays = await pool.relays
        XCTAssertEqual(relays.count, 1)
        XCTAssertTrue(relays.contains { $0.url == "wss://relay.example.com/" })
    }
    
    func testAddDuplicateRelay() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        let relayURL = "wss://relay.example.com"
        let relay1 = await pool.addRelay(relayURL)
        let relay2 = await pool.addRelay(relayURL)
        
        // Should return the same relay instance
        XCTAssertTrue(relay1 === relay2)
        
        let relays = await pool.relays
        XCTAssertEqual(relays.count, 1)
    }
    
    func testRemoveRelay() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        let relayURL = "wss://relay.example.com"
        await pool.addRelay(relayURL)
        
        var relays = await pool.relays
        XCTAssertEqual(relays.count, 1)
        
        await pool.removeRelay(relayURL)
        
        relays = await pool.relays
        XCTAssertEqual(relays.count, 0)
    }
    
    func testGetRelayByURL() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        let relayURL = "wss://relay.example.com"
        let addedRelay = await pool.addRelay(relayURL)
        
        let fetchedRelay = await pool.getRelay(for: relayURL)
        XCTAssertNotNil(fetchedRelay)
        XCTAssertTrue(addedRelay === fetchedRelay)
        
        // Test with normalized URL
        let fetchedNormalized = await pool.getRelay(for: "wss://relay.example.com/")
        XCTAssertNotNil(fetchedNormalized)
        XCTAssertTrue(addedRelay === fetchedNormalized)
    }
    
    func testExplicitRelays() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        // Add explicit relay
        await pool.addRelay("wss://explicit.relay.com", origin: .explicit)
        
        // Add discovered relay (using outbox origin with a pubkey)
        await pool.addRelay("wss://discovered.relay.com", origin: .outbox(authorPubkey: TestFixtures.Keys.alice.publicKey))
        
        let allRelays = await pool.relays
        XCTAssertEqual(allRelays.count, 2)
        
        let explicitRelays = await pool.explicitRelays()
        XCTAssertEqual(explicitRelays.count, 1)
        XCTAssertEqual(explicitRelays.first?.url, "wss://explicit.relay.com/")
    }
    
    func testPrepareRelays() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        let urls = [
            "wss://relay1.example.com",
            "wss://relay2.example.com",
            "wss://relay3.example.com"
        ]
        
        let preparedRelays = await pool.prepareRelays(urls)
        
        XCTAssertEqual(preparedRelays.count, 3)
        
        let allRelays = await pool.relays
        XCTAssertEqual(allRelays.count, 3)
        
        // Verify URLs are normalized
        let relayURLs = allRelays.map { $0.url }.sorted()
        XCTAssertEqual(relayURLs, [
            "wss://relay1.example.com/",
            "wss://relay2.example.com/",
            "wss://relay3.example.com/"
        ])
    }
    
    func testRelayPoolChangeEvents() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        var receivedEvents: [NDKPoolChangeEvent] = []
        
        // Start observing changes
        let observerTask = Task {
            for await event in await pool.relayChanges {
                receivedEvents.append(event)
                
                // Stop after receiving expected events
                if receivedEvents.count >= 2 {
                    break
                }
            }
        }
        
        // Add a relay
        let relay = await pool.addRelay("wss://relay.example.com")
        
        // Remove the relay
        await pool.removeRelay("wss://relay.example.com")
        
        // Wait for events to be processed
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        observerTask.cancel()
        
        // Verify events
        XCTAssertGreaterThanOrEqual(receivedEvents.count, 2)
        
        // First event should be relayAdded
        if case .relayAdded(let addedRelay) = receivedEvents[0] {
            XCTAssertEqual(addedRelay.url, relay.url)
        } else {
            XCTFail("Expected relayAdded event")
        }
        
        // Second event should be relayRemoved
        if case .relayRemoved(let removedURL) = receivedEvents[1] {
            XCTAssertEqual(removedURL, "wss://relay.example.com/")
        } else {
            XCTFail("Expected relayRemoved event")
        }
    }
    
    func testConnectionSummary() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        // Add some relays
        await pool.addRelay("wss://relay1.example.com")
        await pool.addRelay("wss://relay2.example.com")
        await pool.addRelay("wss://relay3.example.com")
        
        let summary = await pool.getConnectionSummary()
        
        XCTAssertEqual(summary.total, 3)
        // All should be disconnected initially
        XCTAssertEqual(summary.connected, 0)
    }
    
    func testDisconnectAll() async throws {
        let ndk = createMockNDK()
        let pool = ndk.pool
        
        // Add relays
        await pool.addRelay("wss://relay1.example.com")
        await pool.addRelay("wss://relay2.example.com")
        
        // Disconnect all
        await pool.disconnectAll()
        
        let connectedRelays = await pool.connectedRelays()
        XCTAssertEqual(connectedRelays.count, 0)
    }
}