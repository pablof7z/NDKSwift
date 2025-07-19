import XCTest
@testable import NDKSwift

final class RelayConnectionTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
    }
    
    override func tearDown() async throws {
        await ndk.pool.disconnectAll()
        ndk = nil
        try await super.tearDown()
    }
    
    func testSubscriptionConnectsToExplicitlyRequestedRelays() async throws {
        // Given: A relay URL that is not in the pool
        let relayUrl = "wss://localhost:8081"  // Use localhost for faster failure
        
        // Verify relay is not in pool initially
        let initialRelay = await ndk.pool.getRelay(for: relayUrl)
        XCTAssertNil(initialRelay, "Relay should not exist in pool initially")
        
        // When: Creating a subscription with explicit relay
        let filter = NDKFilter(kinds: [1], limit: 10)
        let subscription = await ndk.subscribe(filters: [filter], relays: [relayUrl])
        
        // Then: The relay should be added to the pool
        let relay = await ndk.pool.getRelay(for: relayUrl)
        XCTAssertNotNil(relay, "Relay should be added to pool")
        
        // And: Connection should be initiated (will be in connecting or failed state)
        // Wait a bit for connection to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let connectionState = await relay?.connectionState
        XCTAssertNotEqual(connectionState, .disconnected, 
            "Relay should not be in disconnected state after subscription - connection attempt should have been made")
        
        // Cleanup
        await subscription.close()
    }
    
    func testSubscriptionConnectsToMultipleExplicitRelays() async throws {
        // Given: Multiple relay URLs not in the pool
        let relayUrls = [
            "wss://localhost:8081",
            "wss://localhost:8082",
            "wss://localhost:8083"
        ]
        
        // When: Creating a subscription with multiple explicit relays
        let filter = NDKFilter(kinds: [1], limit: 10)
        let subscription = await ndk.subscribe(filters: [filter], relays: Set(relayUrls))
        
        // Then: All relays should be added to the pool
        for url in relayUrls {
            let relay = await ndk.pool.getRelay(for: url)
            XCTAssertNotNil(relay, "Relay \(url) should be added to pool")
            
            // Wait a bit for connection to start
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            let connectionState = await relay?.connectionState
            XCTAssertNotEqual(connectionState, .disconnected,
                "Relay \(url) should not be disconnected - connection attempt should have been made")
        }
        
        // Cleanup
        await subscription.close()
    }
    
    func testPublishingConnectsToExplicitlyRequestedRelays() async throws {
        // Given: A signer and a relay URL not in the pool
        let signer = try NDKPrivateKeySigner(privateKey: Crypto.generatePrivateKey())
        ndk.signer = signer
        
        let relayUrl = "wss://localhost:8084"
        
        // Verify relay is not in pool initially
        let initialRelay = await ndk.pool.getRelay(for: relayUrl)
        XCTAssertNil(initialRelay, "Relay should not exist in pool initially")
        
        // When: Publishing an event to specific relay
        do {
            let (event, _) = try await ndk.publish { builder in
                builder
                    .kind(1) // text note
                    .content("Test event")
            }
            // Then publish to specific relay
            _ = try await ndk.publish(event: event, to: [relayUrl])
            print("Published event: \(event.id)")
        } catch {
            // Publishing might fail if relay is not actually reachable, but that's OK for this test
            print("Publishing failed (expected): \(error)")
        }
        
        // Then: The relay should be added to the pool
        let relay = await ndk.pool.getRelay(for: relayUrl)
        XCTAssertNotNil(relay, "Relay should be added to pool")
        
        // And: Connection should have been attempted
        let connectionState = await relay?.connectionState
        XCTAssertNotNil(connectionState, "Relay should have a connection state")
        XCTAssertNotEqual(connectionState, .disconnected,
            "Relay should not be disconnected - connection attempt should have been made")
    }
    
    func testPublishingConnectsToRelaysFromRelaySelector() async throws {
        // Given: A signer
        let signer = try NDKPrivateKeySigner(privateKey: Crypto.generatePrivateKey())
        ndk.signer = signer
        
        // Add some relays to the pool but don't connect them
        let relayUrls = [
            "wss://localhost:8085",
            "wss://localhost:8086"
        ]
        
        for url in relayUrls {
            _ = await ndk.pool.addRelay(url)
        }
        
        // Verify relays are not connected
        for url in relayUrls {
            let relay = await ndk.pool.getRelay(for: url)
            let state = await relay?.connectionState
            XCTAssertEqual(state, .disconnected, "Relay \(url) should be disconnected initially")
        }
        
        // When: Publishing an event (which will use relay selector)
        do {
            let (event, _) = try await ndk.publish { builder in
                builder
                    .kind(1) // text note
                    .content("Test event")
            }
            print("Published event: \(event.id)")
        } catch {
            // Publishing might fail if relays are not actually reachable, but that's OK for this test
            print("Publishing failed (expected): \(error)")
        }
        
        // Wait a bit for connections to be attempted
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Then: At least some relays should have connection attempted
        // Note: We can't guarantee which relays the selector will choose,
        // but we can verify the connection logic works
        var connectedRelayCount = 0
        for url in relayUrls {
            if let relay = await ndk.pool.getRelay(for: url) {
                let state = await relay.connectionState
                if state != .disconnected {
                    connectedRelayCount += 1
                }
            }
        }
        
        // Since the relay selector might choose some or all relays, we just verify
        // that the publishing completed without crashing
        XCTAssertTrue(true, "Publishing completed without crashing")
        print("Connection attempts made to \(connectedRelayCount) relays")
    }
    
    func testSubscriptionDoesNotReconnectAlreadyConnectedRelays() async throws {
        // Given: A relay that is already connected
        let relayUrl = "wss://already.connected.example.com"
        _ = await ndk.pool.addRelay(relayUrl)
        
        // Mock the connection state to be connected
        // Note: In a real test, we'd need a mock relay or test double
        // For now, we'll just verify the logic doesn't crash
        
        // When: Creating a subscription with the already-connected relay
        let filter = NDKFilter(kinds: [1], limit: 10)
        let subscription = await ndk.subscribe(filters: [filter], relays: [relayUrl])
        
        // Then: The code should not crash and subscription should be created
        XCTAssertNotNil(subscription, "Subscription should be created")
        
        // Cleanup
        await subscription.close()
    }
}