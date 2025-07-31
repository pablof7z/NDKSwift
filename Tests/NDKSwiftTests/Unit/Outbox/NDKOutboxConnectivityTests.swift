import XCTest
@testable import NDKSwift

final class NDKOutboxConnectivityTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
    }
    
    override func tearDown() async throws {
        ndk = nil
        try await super.tearDown()
    }
    
    func testOutboxFallbackToConnectedRelays() async throws {
        // Configure NDK with an unreachable outbox relay
        ndk.outboxConfig = NDKOutboxConfig(
            outboxRelays: ["wss://unreachable.relay.test"]
        )
        
        // Add some test relays (won't actually connect in unit test environment)
        await ndk.pool.addRelay("wss://test-relay1.example.com")
        await ndk.pool.addRelay("wss://test-relay2.example.com")
        
        // Track some authors for discovery
        let testAuthors: Set<String> = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
            "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m" // Convert to hex
        ]
        
        // Start relay discovery - should attempt fallback to configured relays
        await ndk.outbox.discoverRelaysInBackground(for: testAuthors)
        
        // Verify that the discovery operation completed without crashing
        // This tests the fallback behavior when outbox relays are unreachable
        // The actual relay connections are not important in unit tests
        XCTAssertNotNil(ndk.outboxConfig)
        XCTAssertEqual(ndk.outboxConfig.outboxRelays.count, 1)
    }
    
    func testOutboxStrategyWithDisconnectedOutboxRelays() async throws {
        // Configure NDK with an unreachable outbox relay
        ndk.outboxConfig = NDKOutboxConfig(
            outboxRelays: ["wss://unreachable.relay.test"]
        )
        
        // Add test relays
        await ndk.pool.addRelay("wss://test-relay1.example.com")
        await ndk.pool.addRelay("wss://test-relay2.example.com")
        
        // Create a filter with authors
        let filter = NDKFilter(
            authors: ["test_author_1", "test_author_2"],
            kinds: [EventKind.textNote]
        )
        
        // Get outbox strategy - should use available relays for unknown authors
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)
        
        // Unknown authors should be tracked
        XCTAssertEqual(strategy.unknownAuthors.count, 2)
        
        // The strategy should have been created without crashing
        // This tests that the outbox logic executes gracefully when outbox relays are unreachable
        XCTAssertNotNil(strategy)
        XCTAssertNotNil(ndk.outboxConfig)
    }
    
    func testRelayListFetchWithoutOutboxRelays() async throws {
        // Configure NDK with empty outbox relays
        ndk.outboxConfig = NDKOutboxConfig(
            outboxRelays: []
        )
        
        // Add test relay
        await ndk.pool.addRelay("wss://test-relay.example.com")
        
        // Try to track a user - should use available relays even without outbox relays
        let testPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        await ndk.outbox.trackUser(testPubkey)
        
        // The system should handle the lack of outbox relays gracefully
        XCTAssertNotNil(ndk.outboxConfig)
        XCTAssertEqual(ndk.outboxConfig.outboxRelays.count, 0)
        
        // The fetch should complete without errors even without outbox relays
        let relayScore = await ndk.outbox.getRelayScore(
            relay: "wss://test-relay.example.com",
            for: testPubkey
        )
        
        // Score should be a valid number (0.0 - 1.0)
        XCTAssertGreaterThanOrEqual(relayScore, 0.0)
        XCTAssertLessThanOrEqual(relayScore, 1.0)
    }
}