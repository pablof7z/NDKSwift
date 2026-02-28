@testable import NDKSwiftCore
import XCTest

/// Tests for NDKPool's handling of unpublished events when connectivity changes
final class NDKPoolUnpublishedEventsTests: NDKTestCase {
    var ndk: NDK!
    var mockCache: NDKNostrDBCache!

    override func setUp() async throws {
        try await super.setUp()

        mockCache = try await createTestNostrDBCache()
        ndk = try await createTestNDK(cache: mockCache)
    }

    override func tearDown() async throws {
        ndk = nil
        mockCache = nil
        try await super.tearDown()
    }

    // MARK: - Unpublished Events Relay Connection Tests

    /// When connectivity is gained, unpublished events should trigger connection to their target relays
    func testConnectivityGainedConnectsToUnpublishedEventRelays() async throws {
        // Setup: Create a signer and sign an event
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer

        // User must have called connect() at some point (this sets hasConnected = true)
        // We call it with no relays so it completes quickly
        await ndk.connect()

        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test unpublished event")
            .build(signer: signer)

        // Target relays that are NOT in the pool initially
        let targetRelays: Set<String> = ["wss://nos.lol", "wss://nostr.land"]

        // Add unpublished event to cache with target relays (simulating offline publish)
        try await mockCache.addUnpublishedEvent(event, relays: targetRelays)

        // Verify the unpublished event is in the cache
        let unpublished = await mockCache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].targetRelays, targetRelays)

        // Verify target relays are NOT in the pool initially
        let initialRelays = await ndk.pool.relays
        let initialRelayUrls = Set(initialRelays.map { $0.url })
        XCTAssertFalse(initialRelayUrls.contains("wss://nos.lol/"), "nos.lol should not be in pool initially")
        XCTAssertFalse(initialRelayUrls.contains("wss://nostr.land/"), "nostr.land should not be in pool initially")

        // Directly call retryUnpublishedEvents (this is what networkMonitorDidGainConnectivity calls)
        // This tests that the retry logic adds relays to the pool
        _ = try await ndk.eventManager.retryUnpublishedEvents()

        // After retry, target relays should be added to the pool
        let poolRelays = await ndk.pool.relays
        let poolRelayUrls = Set(poolRelays.map { $0.url })

        // The target relays should now be in the pool
        for targetRelay in targetRelays {
            let normalizedTarget = targetRelay.normalizedRelayURL
            XCTAssertTrue(
                poolRelayUrls.contains(normalizedTarget),
                "Pool should contain relay \(normalizedTarget) from unpublished event. Pool has: \(poolRelayUrls)"
            )
        }
    }

    /// When connectivity is gained with no unpublished events, no new relays should be added
    func testConnectivityGainedWithNoUnpublishedEventsDoesNotAddRelays() async throws {
        // Verify no unpublished events
        let unpublished = await mockCache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertTrue(unpublished.isEmpty)

        // Simulate network connectivity gain
        ndk.pool.networkMonitorDidGainConnectivity()

        // Wait a bit
        try await Task.sleep(nanoseconds: 500_000_000)

        // Pool should still be empty (no relays added)
        let poolRelays = await ndk.pool.relays
        XCTAssertTrue(poolRelays.isEmpty, "Pool should remain empty when there are no unpublished events")
    }

    /// Multiple unpublished events targeting different relays should connect to all unique relays
    func testConnectivityGainedConnectsToAllUniqueRelaysFromMultipleEvents() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer

        // User must have called connect() at some point
        await ndk.connect()

        // Create two events targeting different relays
        let event1 = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Event 1")
            .build(signer: signer)

        let event2 = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Event 2")
            .build(signer: signer)

        // Add events with different target relays (simulating offline publish)
        try await mockCache.addUnpublishedEvent(event1, relays: ["wss://relay1.test", "wss://relay2.test"])
        try await mockCache.addUnpublishedEvent(event2, relays: ["wss://relay2.test", "wss://relay3.test"])

        // Verify unpublished events
        let unpublished = await mockCache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 2)

        // Directly call retryUnpublishedEvents
        _ = try await ndk.eventManager.retryUnpublishedEvents()

        // All 3 unique relays should be in the pool
        let poolRelays = await ndk.pool.relays
        let poolRelayUrls = Set(poolRelays.map { $0.url })

        XCTAssertTrue(poolRelayUrls.contains("wss://relay1.test/"), "Pool should contain relay1")
        XCTAssertTrue(poolRelayUrls.contains("wss://relay2.test/"), "Pool should contain relay2")
        XCTAssertTrue(poolRelayUrls.contains("wss://relay3.test/"), "Pool should contain relay3")
    }
}
