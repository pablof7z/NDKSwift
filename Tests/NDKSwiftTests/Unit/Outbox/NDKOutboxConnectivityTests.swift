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
        
        // Add some connected relays
        await ndk.pool.addRelay("wss://relay.damus.io")
        await ndk.pool.addRelay("wss://nos.lol")
        
        // Wait a bit for relay connections
        try await Task.sleep(nanoseconds: TimeConstants.nanosecondsPerSecond / 2)
        
        // Track some authors for discovery
        let testAuthors: Set<String> = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
            "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m" // Convert to hex
        ]
        
        // Start relay discovery - should fall back to connected relays
        await ndk.outbox.discoverRelaysInBackground(for: testAuthors)
        
        // Give it some time to process
        try await Task.sleep(nanoseconds: 2 * TimeConstants.nanosecondsPerSecond)
        
        // Verify we got some relay info (might not if test environment doesn't have real connections)
        let connectedRelays = await ndk.pool.connectedRelayURLs
        XCTAssertFalse(connectedRelays.isEmpty, "Should have connected relays")
        
        // The outbox relay should not be connected
        XCTAssertFalse(connectedRelays.contains("wss://unreachable.relay.test"))
    }
    
    func testOutboxStrategyWithDisconnectedOutboxRelays() async throws {
        // Configure NDK with an unreachable outbox relay
        ndk.outboxConfig = NDKOutboxConfig(
            outboxRelays: ["wss://unreachable.relay.test"]
        )
        
        // Add connected relays
        await ndk.pool.addRelay("wss://relay.damus.io")
        await ndk.pool.addRelay("wss://nos.lol")
        
        // Create a filter with authors
        let filter = NDKFilter(
            authors: ["test_author_1", "test_author_2"],
            kinds: [EventKind.textNote]
        )
        
        // Get outbox strategy - should use connected relays for unknown authors
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)
        
        // Unknown authors should be added to connected relays
        XCTAssertEqual(strategy.unknownAuthors.count, 2)
        XCTAssertFalse(strategy.filtersByRelay.isEmpty)
        
        // Check that filters were created for connected relays, not the unreachable outbox relay
        for (relay, _) in strategy.filtersByRelay {
            XCTAssertNotEqual(relay, "wss://unreachable.relay.test")
        }
    }
    
    func testRelayListFetchWithoutOutboxRelays() async throws {
        // Configure NDK with empty outbox relays
        ndk.outboxConfig = NDKOutboxConfig(
            outboxRelays: []
        )
        
        // Add connected relays
        await ndk.pool.addRelay("wss://relay.damus.io")
        
        // Try to track a user - should use connected relays
        let testPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        await ndk.outbox.trackUser(testPubkey)
        
        // Give it time to fetch
        try await Task.sleep(nanoseconds: TimeConstants.nanosecondsPerSecond)
        
        // The fetch should complete without errors even without outbox relays
        let relayScore = await ndk.outbox.getRelayScore(
            relay: "wss://relay.damus.io",
            for: testPubkey
        )
        
        // Score should be a valid number (0.0 - 1.0)
        XCTAssertGreaterThanOrEqual(relayScore, 0.0)
        XCTAssertLessThanOrEqual(relayScore, 1.0)
    }
}