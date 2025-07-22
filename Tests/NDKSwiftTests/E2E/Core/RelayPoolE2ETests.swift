import XCTest
@testable import NDKSwift

final class RelayPoolE2ETests: XCTestCase {
    let testRelays = RelayConstants.extendedRelays
    
    override func setUp() async throws {
        try await super.setUp()
        NDKLogger.logLevel = .debug
        NDKLogger.logNetworkTraffic = false
    }
    
    func testRelayConnectionManagement() async throws {
        let startTime = Date()
        print("[\(timestamp())] Starting relay connection management E2E test")
        
        let ndk = NDK(cache: MemoryCache())
        
        // Test 1: Add relays before connecting
        print("\n[\(timestamp())] Test 1: Adding relays before connection...")
        for relay in testRelays {
            await ndk.addRelay(relay)
            print("[\(timestamp())] Added relay: \(relay)")
        }
        
        let relaysBeforeConnect = await ndk.relays
        XCTAssertEqual(relaysBeforeConnect.count, testRelays.count)
        
        // Test 2: Connect to all relays
        print("\n[\(timestamp())] Test 2: Connecting to all relays...")
        let connectStart = Date()
        await ndk.connect()
        
        // Wait for connections with different minimum relay counts
        let connected1 = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 5.0)
        print("[\(timestamp())] Connected to at least 1 relay: \(connected1)")
        XCTAssertGreaterThanOrEqual(connected1, 1)
        
        let connected3 = await ndk.waitForRelayConnections(minimumRelays: 3, timeout: 10.0)
        print("[\(timestamp())] Connected to at least 3 relays: \(connected3)")
        
        let connectTime = Date().timeIntervalSince(connectStart)
        print("[\(timestamp())] Connection phase took \(String(format: "%.2f", connectTime))s")
        
        // Test 3: Check individual relay states
        print("\n[\(timestamp())] Test 3: Checking individual relay states...")
        var connectedRelays = 0
        var failedRelays = 0
        
        for relay in await ndk.relays {
            let state = await relay.connectionState
            print("[\(timestamp())] \(relay.url): \(state)")
            
            switch state {
            case NDKRelayConnectionState.connected:
                connectedRelays += 1
            case NDKRelayConnectionState.failed:
                failedRelays += 1
            default:
                break
            }
        }
        
        print("[\(timestamp())] Summary: \(connectedRelays) connected, \(failedRelays) failed")
        XCTAssertGreaterThan(connectedRelays, 0, "Should have at least one connected relay")
        
        // Test 4: Disconnect and reconnect specific relay
        var firstConnectedRelay: NDKRelay?
        for relay in await ndk.relays {
            if await relay.connectionState == NDKRelayConnectionState.connected {
                firstConnectedRelay = relay
                break
            }
        }
        
        if let firstConnectedRelay = firstConnectedRelay {
            print("\n[\(timestamp())] Test 4: Disconnect/reconnect relay \(firstConnectedRelay.url)")
            
            await firstConnectedRelay.disconnect()
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            let stateAfterDisconnect = await firstConnectedRelay.connectionState
            print("[\(timestamp())] State after disconnect: \(stateAfterDisconnect)")
            XCTAssertNotEqual(stateAfterDisconnect, .connected)
            
            try await firstConnectedRelay.connect()
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            
            let stateAfterReconnect = await firstConnectedRelay.connectionState
            print("[\(timestamp())] State after reconnect: \(stateAfterReconnect)")
        }
        
        // Test 5: Add relay after connection
        print("\n[\(timestamp())] Test 5: Adding relay after connection...")
        let newRelay = RelayConstants.currentFyi
        await ndk.addRelay(newRelay)
        
        // New relay should auto-connect
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s
        
        if let addedRelay = await ndk.relays.first(where: { $0.url == newRelay }) {
            let state = await addedRelay.connectionState
            print("[\(timestamp())] New relay \(newRelay) state: \(state)")
        }
        
        // Test 6: Remove relay
        print("\n[\(timestamp())] Test 6: Removing relay...")
        let relayCountBefore = await ndk.relays.count
        await ndk.removeRelay(newRelay)
        let relayCountAfter = await ndk.relays.count
        
        XCTAssertEqual(relayCountAfter, relayCountBefore - 1)
        print("[\(timestamp())] Relay removed, count: \(relayCountBefore) -> \(relayCountAfter)")
        
        // Test 7: Disconnect all
        print("\n[\(timestamp())] Test 7: Disconnecting all relays...")
        await ndk.disconnect()
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        var disconnectedCount = 0
        for relay in await ndk.relays {
            let state = await relay.connectionState
            if state != NDKRelayConnectionState.connected {
                disconnectedCount += 1
            }
        }
        
        print("[\(timestamp())] \(disconnectedCount)/\(await ndk.relays.count) relays disconnected")
        
        let totalTime = Date().timeIntervalSince(startTime)
        print("\n[\(timestamp())] Test completed in \(String(format: "%.2f", totalTime))s")
    }
    
    func testRelayPoolLoadBalancing() async throws {
        print("[\(timestamp())] Starting relay pool load balancing E2E test")
        
        let ndk = NDK(cache: MemoryCache())
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Add multiple relays
        for relay in testRelays.prefix(3) {
            await ndk.addRelay(relay)
        }
        
        await ndk.connect()
        await ndk.waitForRelayConnections(minimumRelays: 2, timeout: 10.0)
        
        // Publish multiple events and track which relays receive them
        print("\n[\(timestamp())] Publishing events to test load distribution...")
        
        var relayDistribution: [String: Int] = [:]
        
        for i in 0..<10 {
            let event = try await ndk.event()
                .content("Load test event #\(i)")
                .kind(EventKind.textNote)
                .build()
            
            let publishedRelays = try await ndk.publish(event)
            
            for relay in publishedRelays {
                let relayURL = relay.url
                relayDistribution[relayURL, default: 0] += 1
            }
            
            print("[\(timestamp())] Event #\(i) published to \(publishedRelays.count) relays")
            
            // Small delay between publishes
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        print("\n[\(timestamp())] Relay distribution:")
        for (relay, count) in relayDistribution.sorted(by: { $0.key < $1.key }) {
            print("   \(relay): \(count) events")
        }
        
        // Verify events were distributed across multiple relays
        XCTAssertGreaterThan(relayDistribution.count, 1, "Events should be distributed across multiple relays")
        
        await ndk.disconnect()
        print("[\(timestamp())] Load balancing test completed")
    }
    
    func testRelayPoolReconnection() async throws {
        print("[\(timestamp())] Starting relay pool reconnection E2E test")
        
        let ndk = NDK(cache: MemoryCache())
        
        // Use a reliable relay for this test
        let testRelay = RelayConstants.damus
        await ndk.addRelay(testRelay)
        
        // Connect and verify
        await ndk.connect()
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        XCTAssertGreaterThan(connected, 0)
        
        guard let relay = await ndk.relays.first else {
            XCTFail("No relay found")
            return
        }
        
        print("[\(timestamp())] Initial connection state: \(await relay.connectionState)")
        
        // Force disconnect
        print("\n[\(timestamp())] Forcing relay disconnect...")
        await relay.disconnect()
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        let disconnectedState = await relay.connectionState
        print("[\(timestamp())] State after disconnect: \(disconnectedState)")
        XCTAssertNotEqual(disconnectedState, NDKRelayConnectionState.connected)
        
        // The relay pool should attempt reconnection
        print("\n[\(timestamp())] Waiting for automatic reconnection...")
        
        let reconnectTimeout = Date().addingTimeInterval(15.0)
        var reconnected = false
        
        while Date() < reconnectTimeout && !reconnected {
            let state = await relay.connectionState
            if state == NDKRelayConnectionState.connected {
                reconnected = true
                print("[\(timestamp())] Relay reconnected automatically!")
                break
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }
        
        // If not auto-reconnected, try manual reconnect
        if !reconnected {
            print("[\(timestamp())] No auto-reconnect, attempting manual reconnection...")
            try await relay.connect()
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            
            let finalState = await relay.connectionState
            print("[\(timestamp())] Final state: \(finalState)")
        }
        
        await ndk.disconnect()
        print("[\(timestamp())] Reconnection test completed")
    }
    
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}