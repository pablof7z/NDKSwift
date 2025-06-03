import XCTest
@testable import NDKSwift

final class NDKRelayTests: XCTestCase {
    
    func testRelayInitialization() {
        let relay = NDKRelay(url: "wss://relay.example.com")
        
        XCTAssertEqual(relay.url, "wss://relay.example.com")
        XCTAssertEqual(relay.connectionState, .disconnected)
        XCTAssertNil(relay.info)
        XCTAssertTrue(relay.activeSubscriptions.isEmpty)
        XCTAssertFalse(relay.isConnected)
    }
    
    func testRelayURLNormalization() {
        // Test various URL formats - now with trailing slashes
        let relay1 = NDKRelay(url: "relay.example.com")
        XCTAssertEqual(relay1.normalizedURL, "wss://relay.example.com/")
        
        let relay2 = NDKRelay(url: "wss://relay.example.com/")
        XCTAssertEqual(relay2.normalizedURL, "wss://relay.example.com/")
        
        let relay3 = NDKRelay(url: "ws://relay.example.com")
        XCTAssertEqual(relay3.normalizedURL, "ws://relay.example.com/")
        
        let relay4 = NDKRelay(url: "WSS://RELAY.EXAMPLE.COM/")
        XCTAssertEqual(relay4.normalizedURL, "wss://relay.example.com/")
        
        // Test www removal
        let relay5 = NDKRelay(url: "wss://www.relay.example.com")
        XCTAssertEqual(relay5.normalizedURL, "wss://relay.example.com/")
    }
    
    func testRelayConnectionStates() async throws {
        let relay = NDKRelay(url: "wss://relay.example.com")
        
        var stateChanges: [NDKRelayConnectionState] = []
        relay.observeConnectionState { state in
            stateChanges.append(state)
        }
        
        // Initial state should be disconnected
        XCTAssertEqual(stateChanges.count, 1)
        if case .disconnected = stateChanges[0] {
            // Success
        } else {
            XCTFail("Initial state should be disconnected")
        }
        
        // Connect
        try await relay.connect()
        
        // Should have transitioned through connecting to connected
        XCTAssertGreaterThanOrEqual(stateChanges.count, 3)
        if case .connecting = stateChanges[1] {
            // Success
        } else {
            XCTFail("Should transition to connecting")
        }
        if case .connected = stateChanges.last {
            // Success
        } else {
            XCTFail("Should end in connected state")
        }
        
        XCTAssertTrue(relay.isConnected)
        
        // Disconnect
        await relay.disconnect()
        
        if case .disconnected = stateChanges.last {
            // Success
        } else {
            XCTFail("Should end in disconnected state")
        }
        
        XCTAssertFalse(relay.isConnected)
    }
    
    func testRelayStats() async throws {
        let relay = NDKRelay(url: "wss://relay.example.com")
        
        // Initial stats
        XCTAssertNil(relay.stats.connectedAt)
        XCTAssertEqual(relay.stats.connectionAttempts, 0)
        XCTAssertEqual(relay.stats.successfulConnections, 0)
        
        // Connect
        try await relay.connect()
        
        // Stats should be updated
        XCTAssertNotNil(relay.stats.connectedAt)
        XCTAssertEqual(relay.stats.connectionAttempts, 1)
        XCTAssertEqual(relay.stats.successfulConnections, 1)
        
        // Disconnect and reconnect
        await relay.disconnect()
        try await relay.connect()
        
        XCTAssertEqual(relay.stats.connectionAttempts, 2)
        XCTAssertEqual(relay.stats.successfulConnections, 2)
    }
    
    func testRelaySubscriptionManagement() {
        let relay = NDKRelay(url: "wss://relay.example.com")
        let ndk = NDK()
        
        let sub1 = NDKSubscription(
            id: "sub1",
            filters: [NDKFilter(kinds: [1])],
            ndk: ndk
        )
        
        let sub2 = NDKSubscription(
            id: "sub2",
            filters: [NDKFilter(kinds: [2])],
            ndk: ndk
        )
        
        // Add subscriptions
        relay.addSubscription(sub1)
        relay.addSubscription(sub2)
        
        XCTAssertEqual(relay.activeSubscriptions.count, 2)
        XCTAssertTrue(relay.activeSubscriptions.contains { $0.id == "sub1" })
        XCTAssertTrue(relay.activeSubscriptions.contains { $0.id == "sub2" })
        
        // Remove subscription
        relay.removeSubscription(sub1)
        
        XCTAssertEqual(relay.activeSubscriptions.count, 1)
        XCTAssertFalse(relay.activeSubscriptions.contains { $0.id == "sub1" })
        XCTAssertTrue(relay.activeSubscriptions.contains { $0.id == "sub2" })
    }
    
    func testRelayInfoStructures() throws {
        // Test RelayInformation decoding
        let infoJSON = """
        {
            "name": "Test Relay",
            "description": "A test relay",
            "pubkey": "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            "contact": "admin@relay.com",
            "supported_nips": [1, 2, 9, 11, 12],
            "software": "test-relay",
            "version": "1.0.0",
            "limitation": {
                "max_message_length": 65536,
                "max_subscriptions": 10,
                "auth_required": false
            },
            "fees": {
                "admission": [
                    {"amount": 1000, "unit": "sats"}
                ],
                "publication": [
                    {"amount": 1, "unit": "sats", "kinds": [1]}
                ]
            }
        }
        """
        
        let data = infoJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        let info = try decoder.decode(NDKRelayInformation.self, from: data)
        
        XCTAssertEqual(info.name, "Test Relay")
        XCTAssertEqual(info.description, "A test relay")
        XCTAssertEqual(info.pubkey, "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e")
        XCTAssertEqual(info.contact, "admin@relay.com")
        XCTAssertEqual(info.supportedNips, [1, 2, 9, 11, 12])
        XCTAssertEqual(info.software, "test-relay")
        XCTAssertEqual(info.version, "1.0.0")
        
        // Test limitation
        XCTAssertNotNil(info.limitation)
        XCTAssertEqual(info.limitation?.maxMessageLength, 65536)
        XCTAssertEqual(info.limitation?.maxSubscriptions, 10)
        XCTAssertEqual(info.limitation?.authRequired, false)
        
        // Test fees
        XCTAssertNotNil(info.fees)
        XCTAssertEqual(info.fees?.admission?.count, 1)
        XCTAssertEqual(info.fees?.admission?[0].amount, 1000)
        XCTAssertEqual(info.fees?.admission?[0].unit, "sats")
        XCTAssertEqual(info.fees?.publication?.count, 1)
        XCTAssertEqual(info.fees?.publication?[0].amount, 1)
        XCTAssertEqual(info.fees?.publication?[0].kinds, [1])
    }
    
    func testNDKRelayInfo() {
        let relayInfo = NDKRelayInfo(
            url: "wss://relay.example.com",
            read: true,
            write: false
        )
        
        XCTAssertEqual(relayInfo.url, "wss://relay.example.com")
        XCTAssertTrue(relayInfo.read)
        XCTAssertFalse(relayInfo.write)
        
        // Test default values
        let defaultInfo = NDKRelayInfo(url: "wss://relay2.example.com")
        XCTAssertTrue(defaultInfo.read)
        XCTAssertTrue(defaultInfo.write)
    }
    
    func testRelayConnectionFailure() async {
        let relay = NDKRelay(url: "wss://relay.example.com")
        
        var lastState: NDKRelayConnectionState?
        relay.observeConnectionState { state in
            lastState = state
        }
        
        // Simulate connection then failure
        // In a real implementation, this would handle actual connection failures
        // For now, we can't easily simulate this without mocking
        
        // Test that trying to send while disconnected throws error
        do {
            try await relay.send("TEST")
            XCTFail("Should have thrown error")
        } catch {
            if let ndkError = error as? NDKError {
                XCTAssertEqual(ndkError.localizedDescription, "Relay connection failed: Not connected to relay")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testMultipleConnectionAttempts() async throws {
        let relay = NDKRelay(url: "wss://relay.example.com")
        
        // Multiple connect calls should be safe
        try await relay.connect()
        try await relay.connect() // Should not error
        
        XCTAssertEqual(relay.stats.connectionAttempts, 1) // Only counted once
        XCTAssertEqual(relay.stats.successfulConnections, 1)
        
        // Multiple disconnect calls should be safe
        await relay.disconnect()
        await relay.disconnect() // Should not error
        
        XCTAssertFalse(relay.isConnected)
    }
}