@testable import NDKSwift
import XCTest

final class NDKRelaySubscriptionManagerTests: XCTestCase {
    var relay: NDKRelay!
    var subscriptionManager: NDKRelaySubscriptionManager!

    override func setUp() async throws {
        relay = NDKRelay(url: "wss://relay.example.com")
        subscriptionManager = NDKRelaySubscriptionManager(relay: relay)
    }

    // MARK: - Filter Merging Tests

    func testFilterMergingWithSameKinds() async {
        // Create two subscriptions with same kinds but different authors
        let sub1 = NDKSubscription(
            filters: [NDKFilter(authors: ["author1"], kinds: [0, 1])],
            options: NDKSubscriptionOptions()
        )

        let sub2 = NDKSubscription(
            filters: [NDKFilter(authors: ["author2"], kinds: [0, 1])],
            options: NDKSubscriptionOptions()
        )

        // Add both subscriptions
        let relaySubId1 = await subscriptionManager.addSubscription(sub1, filters: sub1.filters)
        let relaySubId2 = await subscriptionManager.addSubscription(sub2, filters: sub2.filters)

        // They should be grouped into the same relay subscription
        XCTAssertEqual(relaySubId1, relaySubId2, "Subscriptions with same kinds should be grouped")
    }

    func testFilterMergingPreservesAllAuthors() async {
        // Create subscriptions with different authors
        let filters1 = [NDKFilter(authors: ["alice", "bob"], kinds: [1])]
        let filters2 = [NDKFilter(authors: ["charlie", "david"], kinds: [1])]

        let sub1 = NDKSubscription(filters: filters1)
        let sub2 = NDKSubscription(filters: filters2)

        // Test the static merge function
        let merged = NDKRelaySubscriptionManager.mergeAllFilters(
            from: [(sub1, filters1), (sub2, filters2)]
        )

        XCTAssertEqual(merged.count, 1, "Should merge into single filter")

        let mergedFilter = merged[0]
        XCTAssertEqual(mergedFilter.kinds, [1])
        XCTAssertEqual(Set(mergedFilter.authors ?? []), Set(["alice", "bob", "charlie", "david"]))
    }

    func testFiltersWithLimitsNotMerged() async {
        // Filters with limits should not be merged
        let sub1 = NDKSubscription(
            filters: [NDKFilter(kinds: [1], limit: 10)],
            options: NDKSubscriptionOptions()
        )

        let sub2 = NDKSubscription(
            filters: [NDKFilter(kinds: [1], limit: 20)],
            options: NDKSubscriptionOptions()
        )

        let relaySubId1 = await subscriptionManager.addSubscription(sub1, filters: sub1.filters)
        let relaySubId2 = await subscriptionManager.addSubscription(sub2, filters: sub2.filters)

        // They should NOT be grouped
        XCTAssertNotEqual(relaySubId1, relaySubId2, "Subscriptions with limits should not be grouped")
    }

    func testCloseOnEoseNotMixedWithPersistent() async {
        // Create one persistent and one closeOnEose subscription
        var options1 = NDKSubscriptionOptions()
        options1.closeOnEose = false
        let sub1 = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options1
        )

        var options2 = NDKSubscriptionOptions()
        options2.closeOnEose = true
        let sub2 = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options2
        )

        let relaySubId1 = await subscriptionManager.addSubscription(sub1, filters: sub1.filters)
        let relaySubId2 = await subscriptionManager.addSubscription(sub2, filters: sub2.filters)

        // They should NOT be grouped
        XCTAssertNotEqual(relaySubId1, relaySubId2, "CloseOnEose subscriptions should not mix with persistent")
    }

    func testTimeConstraintsMerging() async {
        // Test that time constraints use most restrictive values
        let since1: Timestamp = 1000
        let since2: Timestamp = 2000
        let until1: Timestamp = 5000
        let until2: Timestamp = 4000

        let filters1 = [NDKFilter(kinds: [1], since: since1, until: until1)]
        let filters2 = [NDKFilter(kinds: [1], since: since2, until: until2)]

        let sub1 = NDKSubscription(filters: filters1)
        let sub2 = NDKSubscription(filters: filters2)

        let merged = NDKRelaySubscriptionManager.mergeAllFilters(
            from: [(sub1, filters1), (sub2, filters2)]
        )

        XCTAssertEqual(merged.count, 1)
        let mergedFilter = merged[0]
        XCTAssertEqual(mergedFilter.since, since2, "Should use most recent since")
        XCTAssertEqual(mergedFilter.until, until2, "Should use earliest until")
    }

    // MARK: - Subscription State Tests

    func testSubscriptionWaitsForRelayConnection() async {
        // Create a subscription when relay is not connected
        let sub = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: NDKSubscriptionOptions()
        )

        _ = await subscriptionManager.addSubscription(sub, filters: sub.filters)

        // Get active subscriptions - should be empty since relay not connected
        let activeIds = await subscriptionManager.getActiveSubscriptionIds()
        XCTAssertEqual(activeIds.count, 0, "No subscriptions should be active when relay not connected")
    }

    func testSubscriptionReplayOnReconnect() async {
        // This test would require mocking the relay connection state
        // For now, we'll test the replay mechanism directly

        let sub = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: NDKSubscriptionOptions()
        )

        let _ = await subscriptionManager.addSubscription(sub, filters: sub.filters)

        // Simulate reconnection by calling executePendingSubscriptions
        await subscriptionManager.executePendingSubscriptions()

        // In a real test with mocked relay, we'd verify the subscription was sent
    }

    // MARK: - EOSE Handling Tests

    func testEOSEClosesSubscriptionWhenCloseOnEose() async {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true

        let sub = NDKSubscription(
            id: "test-sub",
            filters: [NDKFilter(kinds: [1])],
            options: options
        )

        let relaySubId = await subscriptionManager.addSubscription(sub, filters: sub.filters)

        // Simulate EOSE
        await subscriptionManager.handleEOSE(relaySubscriptionId: relaySubId)

        // Verify subscription is no longer active
        let activeIds = await subscriptionManager.getActiveSubscriptionIds()
        XCTAssertEqual(activeIds.count, 0, "CloseOnEose subscription should be removed after EOSE")
    }

    func testEOSEDoesNotClosePersistentSubscription() async {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = false

        let sub = NDKSubscription(
            id: "test-sub",
            filters: [NDKFilter(kinds: [1])],
            options: options
        )

        let relaySubId = await subscriptionManager.addSubscription(sub, filters: sub.filters)

        // Mark as running first (simulating connected relay)
        await subscriptionManager.executePendingSubscriptions()

        // Simulate EOSE
        await subscriptionManager.handleEOSE(relaySubscriptionId: relaySubId)

        // Verify subscription is still active
        let activeIds = await subscriptionManager.getActiveSubscriptionIds()
        XCTAssertGreaterThan(activeIds.count, 0, "Persistent subscription should remain after EOSE")
    }

    // MARK: - Event Routing Tests

    func testEventRoutedToCorrectSubscription() async {
        let expectation = XCTestExpectation(description: "Event received")

        let sub1 = NDKSubscription(
            filters: [NDKFilter(authors: ["alice"], kinds: [1])],
            options: NDKSubscriptionOptions()
        )

        let sub2 = NDKSubscription(
            filters: [NDKFilter(authors: ["bob"], kinds: [1])],
            options: NDKSubscriptionOptions()
        )

        // Set up event callback
        sub1.onEvent { event in
            XCTAssertEqual(event.pubkey, "alice")
            expectation.fulfill()
        }

        let relaySubId = await subscriptionManager.addSubscription(sub1, filters: sub1.filters)
        let _ = await subscriptionManager.addSubscription(sub2, filters: sub2.filters)

        // Create event from alice
        let event = NDKEvent(
            kind: 1,
            content: "Hello",
            pubkey: "alice"
        )

        await subscriptionManager.handleEvent(event, relaySubscriptionId: relaySubId)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Subscription Removal Tests

    func testRemoveSubscriptionUpdatesFilters() async {
        let sub1 = NDKSubscription(
            id: "sub1",
            filters: [NDKFilter(authors: ["alice"], kinds: [1])],
            options: NDKSubscriptionOptions()
        )

        let sub2 = NDKSubscription(
            id: "sub2",
            filters: [NDKFilter(authors: ["bob"], kinds: [1])],
            options: NDKSubscriptionOptions()
        )

        let relaySubId = await subscriptionManager.addSubscription(sub1, filters: sub1.filters)
        let _ = await subscriptionManager.addSubscription(sub2, filters: sub2.filters)

        // Remove first subscription
        await subscriptionManager.removeSubscription("sub1")

        // Create event from alice - should not be received
        let aliceEvent = NDKEvent(pubkey: "alice", createdAt: Timestamp(Date().timeIntervalSince1970), kind: 1, tags: [], content: "Hello")

        var aliceEventReceived = false
        sub1.onEvent { _ in
            aliceEventReceived = true
        }

        await subscriptionManager.handleEvent(aliceEvent, relaySubscriptionId: relaySubId)

        // Give time for event to be processed
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertFalse(aliceEventReceived, "Removed subscription should not receive events")

        // Create event from bob - should be received
        let bobEvent = NDKEvent(pubkey: "bob", createdAt: Timestamp(Date().timeIntervalSince1970), kind: 1, tags: [], content: "Hello")

        let bobExpectation = XCTestExpectation(description: "Bob event received")
        sub2.onEvent { _ in
            bobExpectation.fulfill()
        }

        await subscriptionManager.handleEvent(bobEvent, relaySubscriptionId: relaySubId)

        await fulfillment(of: [bobExpectation], timeout: 1.0)
    }

    // MARK: - Fingerprint Tests

    func testFingerprintGeneration() {
        let filter1 = NDKFilter(authors: ["alice"], kinds: [1, 3, 0])
        let fingerprint1 = NDKRelaySubscriptionManager.FilterFingerprint(
            filters: [filter1],
            closeOnEose: false
        )

        let filter2 = NDKFilter(authors: ["bob"], kinds: [0, 1, 3]) // Different order
        let fingerprint2 = NDKRelaySubscriptionManager.FilterFingerprint(
            filters: [filter2],
            closeOnEose: false
        )

        // Should have same kinds fingerprint despite order
        XCTAssertEqual(fingerprint1.kinds, fingerprint2.kinds, "Kind order should not affect fingerprint")

        // Different closeOnEose should create different fingerprints
        let fingerprint3 = NDKRelaySubscriptionManager.FilterFingerprint(
            filters: [filter1],
            closeOnEose: true
        )

        XCTAssertNotEqual(fingerprint1.closeOnEose, fingerprint3.closeOnEose)
    }
}
