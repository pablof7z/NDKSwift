@testable import NDKSwiftCore
import XCTest

final class NDKPoolTests: NDKTestCase {
    // MARK: - Helper Methods

    private func createMockNDK() -> NDK {
        return createTestNDK()
    }

    func testAddRelay() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        let relayURL = "wss://relay.example.com"
        let relay = await pool.addRelay(relayURL)

        XCTAssertEqual(relay.url, "wss://relay.example.com/")

        let relays = await pool.relays
        XCTAssertEqual(relays.count, 1)
        XCTAssertTrue(relays.contains { $0.url == "wss://relay.example.com/" })
    }

    func testAddDuplicateRelay() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

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
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

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
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

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
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

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
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        let urls = [
            "wss://relay1.example.com",
            "wss://relay2.example.com",
            "wss://relay3.example.com",
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
            "wss://relay3.example.com/",
        ])
    }

    func testRelayPoolChangeEvents() async throws {
        // Use timeout protection to prevent hanging
        try await performAsyncTest(timeout: 5.0) { [weak self] in
            guard let self = self else { return }
            let ndk = self.createMockNDK()
            guard let pool = ndk.pool else {
                XCTFail("Pool should not be nil")
                return
            }

            var receivedEvents: [NDKPoolChangeEvent] = []
            let addEventReceived = XCTestExpectation(description: "Relay added event received")
            let removeEventReceived = XCTestExpectation(description: "Relay removed event received")

            // Use an actor to ensure thread-safe access to receivedEvents
            actor EventCollector {
                private var events: [NDKPoolChangeEvent] = []

                func append(_ event: NDKPoolChangeEvent) {
                    events.append(event)
                }

                func getEvents() -> [NDKPoolChangeEvent] {
                    return events
                }
            }

            let eventCollector = EventCollector()

            // Define the test URL and its normalized version
            let testURL = "wss://relay.example.com"
            let normalizedURL = testURL.normalizedRelayURL // This will add trailing slash

            // Start observing changes before performing actions
            let observerTask = Task {
                for await event in await pool.relayChanges {
                    await eventCollector.append(event)

                    // Check for specific events
                    switch event {
                    case let .relayAdded(relay):
                        if relay.url == normalizedURL {
                            addEventReceived.fulfill()
                        }
                    case let .relayRemoved(url):
                        if url == normalizedURL {
                            removeEventReceived.fulfill()
                        }
                    default:
                        break
                    }
                }
            }

            // Give the observer task more time to start listening
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Add a relay
            _ = await pool.addRelay(testURL)

            // Wait for add event with longer timeout
            await self.fulfillment(of: [addEventReceived], timeout: 3.0)

            // Give some time between operations to avoid race conditions
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Remove the relay (can use either normalized or non-normalized URL)
            await pool.removeRelay(testURL)

            // Wait for remove event with longer timeout
            await self.fulfillment(of: [removeEventReceived], timeout: 3.0)

            // Give a bit more time to ensure all events are collected
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Cancel observer task
            observerTask.cancel()

            // Get the collected events
            receivedEvents = await eventCollector.getEvents()

            // Verify we received the expected events
            let hasAddEvent = receivedEvents.contains { event in
                if case let .relayAdded(addedRelay) = event {
                    return addedRelay.url == normalizedURL
                }
                return false
            }

            let hasRemoveEvent = receivedEvents.contains { event in
                if case let .relayRemoved(removedURL) = event {
                    return removedURL == normalizedURL
                }
                return false
            }

            XCTAssertTrue(hasAddEvent, "Should have received relayAdded event. Received events: \(receivedEvents)")
            XCTAssertTrue(hasRemoveEvent, "Should have received relayRemoved event. Received events: \(receivedEvents)")
        }
    }

    func testConnectionSummary() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

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
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        // Add relays
        await pool.addRelay("wss://relay1.example.com")
        await pool.addRelay("wss://relay2.example.com")

        // Disconnect all
        await pool.disconnectAll()

        let connectedRelays = await pool.connectedRelays()
        XCTAssertEqual(connectedRelays.count, 0)
    }

    // MARK: - Blocked Relay Tests

    func testBlockedRelayNotAdded() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        // Setup mock signer with test user
        let signer = try NDKPrivateKeySigner(privateKey: TestFixtures.Keys.alice.privateKey)
        ndk.signer = signer

        // Create and cache a blocked relay list event
        let blockedRelayList = try await NDKEventBuilder(ndk: ndk)
            .kind(EventKind.blockedRelays)
            .content("")
            .tags([
                ["r", "wss://blocked.relay.com/", "spam"],
                ["r", "wss://another.blocked.relay.com/", "malicious"],
            ])
            .build(signer: signer)

        // Add to cache
        try await ndk.cache.saveEvent(blockedRelayList)

        // Refresh blocked relays to load from cache
        await pool.refreshBlockedRelays()

        // Try to add a blocked relay
        _ = await pool.addRelay("wss://blocked.relay.com", origin: .outbox(authorPubkey: "somepubkey"))

        // Relay should not be added to the pool
        let relays = await pool.relays
        XCTAssertFalse(relays.contains { $0.url == "wss://blocked.relay.com/" }, "Blocked relay should not be added to pool")
    }

    func testRefreshBlockedRelaysRemovesExistingRelays() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        // Setup mock signer with test user
        let signer = try NDKPrivateKeySigner(privateKey: TestFixtures.Keys.alice.privateKey)
        ndk.signer = signer

        // Add some relays first (before they're blocked)
        await pool.addRelay("wss://relay1.example.com")
        await pool.addRelay("wss://relay2.example.com")
        await pool.addRelay("wss://relay3.example.com")

        var relays = await pool.relays
        XCTAssertEqual(relays.count, 3)

        // Create and cache a blocked relay list event that blocks relay2
        let blockedRelayList = try await NDKEventBuilder(ndk: ndk)
            .kind(EventKind.blockedRelays)
            .content("")
            .tags([
                ["r", "wss://relay2.example.com/", "spam"],
            ])
            .build(signer: signer)

        // Add to cache
        try await ndk.cache.saveEvent(blockedRelayList)

        // Refresh blocked relays
        await pool.refreshBlockedRelays()

        // Check that relay2 was removed
        relays = await pool.relays
        XCTAssertEqual(relays.count, 2)
        XCTAssertTrue(relays.contains { $0.url == "wss://relay1.example.com/" })
        XCTAssertFalse(relays.contains { $0.url == "wss://relay2.example.com/" })
        XCTAssertTrue(relays.contains { $0.url == "wss://relay3.example.com/" })
    }

    // MARK: - Connection State Tests

    func testGetRelayStateSnapshot() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        // Add multiple relays
        await pool.addRelay("wss://relay1.example.com")
        await pool.addRelay("wss://relay2.example.com")
        await pool.addRelay("wss://relay3.example.com")

        let snapshot = await pool.getRelayStateSnapshot()

        // All relays should be in the snapshot
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertNotNil(snapshot["wss://relay1.example.com/"])
        XCTAssertNotNil(snapshot["wss://relay2.example.com/"])
        XCTAssertNotNil(snapshot["wss://relay3.example.com/"])

        // All should be disconnected initially
        for (_, state) in snapshot {
            XCTAssertEqual(state, .disconnected)
        }
    }

    func testConnectedRelayURLs() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        // Add relays
        await pool.addRelay("wss://relay1.example.com")
        await pool.addRelay("wss://relay2.example.com")

        // Initially no relays should be connected
        let connectedURLs = await pool.connectedRelayURLs
        XCTAssertEqual(connectedURLs.count, 0)
    }

    func testConnectAll() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        // Add multiple relays
        await pool.addRelay("wss://relay1.example.com")
        await pool.addRelay("wss://relay2.example.com")
        await pool.addRelay("wss://relay3.example.com")

        // Initial state
        var summary = await pool.getConnectionSummary()
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.connected, 0)

        // Connect all (this will fail in tests but should not crash)
        await pool.connectAll()

        // Verify the method completed without errors
        summary = await pool.getConnectionSummary()
        XCTAssertEqual(summary.total, 3)
    }

    func testPrepareRelaysWithAutoConnect() async throws {
        let ndk = createMockNDK()
        guard let pool = ndk.pool else {
            XCTFail("Pool should not be nil")
            return
        }

        let urls = [
            "wss://relay1.example.com",
            "wss://relay2.example.com",
        ]

        // Prepare with autoConnect false (default)
        let preparedRelays = await pool.prepareRelays(urls, autoConnect: false)
        XCTAssertEqual(preparedRelays.count, 2)

        // Prepare again with autoConnect true
        let preparedRelays2 = await pool.prepareRelays(urls, autoConnect: true)
        XCTAssertEqual(preparedRelays2.count, 2)

        // Should return same relay instances
        XCTAssertTrue(preparedRelays[0] === preparedRelays2[0])
        XCTAssertTrue(preparedRelays[1] === preparedRelays2[1])
    }
}
