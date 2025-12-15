@testable import NDKSwiftCore
import XCTest

@MainActor
final class NDKRelaySubscriptionTests: XCTestCase {
    // MARK: - Test Helpers

    private func createMockRelay(url: String = "wss://relay.example.com") -> NDKRelay {
        let relay = NDKRelay(url: url)
        return relay
    }

    private func createMockSubscription(
        id: String,
        filters: [NDKFilter],
        closeOnEose: Bool = false,
        isGroupable: Bool = true,
        groupableDelay: TimeInterval? = nil,
        groupableDelayType: NDKSubscriptionDelayType? = nil
    ) -> NDKSubscriptionCoordinator {
        let ndk = NDK()
        return NDKSubscriptionCoordinator(
            id: id,
            filters: filters,
            relays: nil,
            ndk: ndk,
            closeOnEose: closeOnEose,
            fingerprint: nil,
            isGroupable: isGroupable,
            groupableDelay: groupableDelay,
            groupableDelayType: groupableDelayType
        )
    }

    private func createFilter(kinds: [Int]? = nil, authors: [String]? = nil, limit: Int? = nil, tags: [String: [String]]? = nil) -> NDKFilter {
        var filter = NDKFilter()
        filter.kinds = kinds
        filter.authors = authors
        filter.limit = limit
        if let tags = tags {
            for (key, values) in tags {
                filter.addTagFilter(key, values: values)
            }
        }
        return filter
    }

    // MARK: - Initialization Tests

    func testInitialization() async {
        let relay = createMockRelay()
        let fingerprint = "test-fingerprint"
        let group = NDKRelaySubscription(relay: relay, fingerprint: fingerprint, isGroupable: true)

        let actualFingerprint = await group.fingerprint
        let actualRelay = await group.relay
        let actualIsGroupable = await group.isGroupable
        let isEmpty = await group.isEmpty()

        XCTAssertEqual(actualFingerprint, fingerprint)
        XCTAssertEqual(actualRelay.url, relay.url)
        XCTAssertTrue(actualIsGroupable)
        XCTAssertTrue(isEmpty)
    }

    // MARK: - Item Management Tests

    func testAddItem() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        let subscription = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])])
        let filters = [createFilter(kinds: [1])]

        await group.addItem(subscription, filters: filters)

        let isEmpty = await group.isEmpty()
        XCTAssertFalse(isEmpty)
    }

    func testRemoveItem() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        let subscription1 = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])])
        let subscription2 = createMockSubscription(id: "sub2", filters: [createFilter(kinds: [1])])
        let filters = [createFilter(kinds: [1])]

        await group.addItem(subscription1, filters: filters)
        await group.addItem(subscription2, filters: filters)

        let removed = await group.removeItem(subscription1)
        XCTAssertTrue(removed)

        let isEmpty = await group.isEmpty()
        XCTAssertFalse(isEmpty)

        let removedAgain = await group.removeItem(subscription1)
        XCTAssertFalse(removedAgain)
    }

    func testRemoveAllItems() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        let subscription = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])])
        let filters = [createFilter(kinds: [1])]

        await group.addItem(subscription, filters: filters)
        _ = await group.removeItem(subscription)

        let isEmpty = await group.isEmpty()
        XCTAssertTrue(isEmpty)
    }

    // MARK: - Status Management Tests

    func testCanAcceptNewItems() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        // Initial state should accept items
        let canAcceptInitial = await group.canAcceptNewItems()
        XCTAssertTrue(canAcceptInitial)

        // Schedule execution (pending state)
        await group.scheduleExecution(delay: 0.1, delayType: .atLeast)
        let canAcceptPending = await group.canAcceptNewItems()
        XCTAssertTrue(canAcceptPending)
    }

    func testIsActive() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        let isActiveInitial = await group.isActive()
        XCTAssertFalse(isActiveInitial)
    }

    // MARK: - Filter Compilation Tests

    func testCompileFiltersSimple() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        let sub1 = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])])
        let sub2 = createMockSubscription(id: "sub2", filters: [createFilter(kinds: [1])])

        await group.addItem(sub1, filters: [createFilter(kinds: [1])])
        await group.addItem(sub2, filters: [createFilter(kinds: [1])])

        let compiled = await group.compileFilters()
        XCTAssertEqual(compiled.count, 1)
        XCTAssertEqual(compiled[0].kinds, [1])
    }

    func testCompileFiltersWithLimits() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        // Filters with limits should be concatenated, not merged
        let filter1 = createFilter(kinds: [1], limit: 10)
        let filter2 = createFilter(kinds: [1], limit: 20)
        let filter3 = createFilter(kinds: [1]) // No limit

        let sub1 = createMockSubscription(id: "sub1", filters: [filter1])
        let sub2 = createMockSubscription(id: "sub2", filters: [filter2])
        let sub3 = createMockSubscription(id: "sub3", filters: [filter3])

        await group.addItem(sub1, filters: [filter1])
        await group.addItem(sub2, filters: [filter2])
        await group.addItem(sub3, filters: [filter3])

        let compiled = await group.compileFilters()

        // Should have 3 filters: 1 merged (no limit) + 2 with limits
        XCTAssertEqual(compiled.count, 3)

        // First filter should be the merged one (no limit)
        XCTAssertNil(compiled[0].limit)
        XCTAssertEqual(compiled[0].kinds, [1])

        // Next two should be the ones with limits
        let limitsInResult = compiled.compactMap { $0.limit }
        XCTAssertEqual(Set(limitsInResult), Set([10, 20]))
    }

    func testCompileFiltersMultipleFiltersPerSubscription() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        let filters1 = [
            createFilter(kinds: [1]),
            createFilter(kinds: [3]),
        ]
        let filters2 = [
            createFilter(kinds: [1]),
            createFilter(kinds: [4]),
        ]

        let sub1 = createMockSubscription(id: "sub1", filters: filters1)
        let sub2 = createMockSubscription(id: "sub2", filters: filters2)

        await group.addItem(sub1, filters: filters1)
        await group.addItem(sub2, filters: filters2)

        let compiled = await group.compileFilters()

        // Should merge filters at the same index
        XCTAssertEqual(compiled.count, 2)
        XCTAssertEqual(compiled[0].kinds, [1]) // Merged from both subscriptions
        XCTAssertTrue(compiled[1].kinds?.contains(3) ?? false || compiled[1].kinds?.contains(4) ?? false)
    }

    func testCompileFiltersComplexMerging() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        // Test tag merging
        let filter1 = createFilter(kinds: [1], tags: ["p": ["author1", "author2"]])
        let filter2 = createFilter(kinds: [1], tags: ["p": ["author2", "author3"]])

        let sub1 = createMockSubscription(id: "sub1", filters: [filter1])
        let sub2 = createMockSubscription(id: "sub2", filters: [filter2])

        await group.addItem(sub1, filters: [filter1])
        await group.addItem(sub2, filters: [filter2])

        let compiled = await group.compileFilters()
        XCTAssertEqual(compiled.count, 1)

        // Tags should be merged
        let mergedTags = compiled[0].tags?["p"] ?? []
        XCTAssertEqual(Set(mergedTags), Set(["author1", "author2", "author3"]))
    }

    // MARK: - Scheduling Tests

    func testScheduleExecutionFirstTime() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        await group.scheduleExecution(delay: 0.1, delayType: .atLeast)

        // Group should be in pending state
        let canAccept = await group.canAcceptNewItems()
        XCTAssertTrue(canAccept)
    }

    func testScheduleExecutionRescheduling() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        // Schedule with atLeast
        await group.scheduleExecution(delay: 0.2, delayType: .atLeast)

        // Schedule again with shorter atMost (should reschedule)
        await group.scheduleExecution(delay: 0.1, delayType: .atMost)

        // Wait to see if execution happens
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

        // Should have executed by now due to atMost constraint
        // (Can't easily test the actual execution without mocking more)
    }

    func testCancelPendingExecution() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        await group.scheduleExecution(delay: 0.5, delayType: .atLeast)
        await group.cancelPendingExecution()

        // Should still be able to accept items after cancellation
        let canAccept = await group.canAcceptNewItems()
        XCTAssertTrue(canAccept)
    }

    // MARK: - Event Handling Tests

    func testHandleEvent() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        var receivedEvents: [String: NDKEvent] = [:]

        let sub1 = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])])
        let sub2 = createMockSubscription(id: "sub2", filters: [createFilter(kinds: [1])])

        // Set up event handlers
        await sub1.setOnEvent { event, _ in
            receivedEvents["sub1"] = event
        }
        await sub2.setOnEvent { event, _ in
            receivedEvents["sub2"] = event
        }

        await group.addItem(sub1, filters: [createFilter(kinds: [1])])
        await group.addItem(sub2, filters: [createFilter(kinds: [1])])

        // Create and handle an event
        let event = NDKEvent(kind: 1, content: "test", tags: [], pubkey: "test-pubkey")
        await group.handleEvent(event, from: relay)

        // Both subscriptions should have received the event
        XCTAssertNotNil(receivedEvents["sub1"])
        XCTAssertNotNil(receivedEvents["sub2"])
        XCTAssertEqual(receivedEvents["sub1"]?.content, "test")
        XCTAssertEqual(receivedEvents["sub2"]?.content, "test")
    }

    func testHandleEOSE() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        var eoseReceived: [String: Bool] = [:]

        let sub1 = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])], closeOnEose: false)
        let sub2 = createMockSubscription(id: "sub2", filters: [createFilter(kinds: [1])], closeOnEose: false)

        // Set up EOSE handlers
        await sub1.setOnEOSE { _ in
            eoseReceived["sub1"] = true
        }
        await sub2.setOnEOSE { _ in
            eoseReceived["sub2"] = true
        }

        await group.addItem(sub1, filters: [createFilter(kinds: [1])])
        await group.addItem(sub2, filters: [createFilter(kinds: [1])])

        // Handle EOSE with non-matching ID (won't affect group)
        await group.handleEOSE(subscriptionId: "non-matching-id")

        // Verify EOSE handlers weren't called
        XCTAssertFalse(eoseReceived["sub1"] ?? false)
        XCTAssertFalse(eoseReceived["sub2"] ?? false)
    }

    func testHandleEOSEWithCloseOnEose() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        // Create relay with mock send capability
        await relay.setNDK(NDK())

        // All subscriptions have closeOnEose = true
        let sub1 = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])], closeOnEose: true)
        let sub2 = createMockSubscription(id: "sub2", filters: [createFilter(kinds: [1])], closeOnEose: true)

        await group.addItem(sub1, filters: [createFilter(kinds: [1])])
        await group.addItem(sub2, filters: [createFilter(kinds: [1])])

        // Note: In real usage, subId would be set during execute()
        // We can't directly test EOSE handling with matching subId due to actor isolation
        // but we've tested the non-matching case above
    }

    func testHandleEOSEForAbandonedSubscription() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        // Set up the relay to track close calls
        await relay.setNDK(NDK())

        // Handle EOSE for a subscription ID when group has no subId set
        await group.handleEOSE(subscriptionId: "abandoned-sub-id")

        // Group should still be in initial state (not closed)
        let canAccept = await group.canAcceptNewItems()
        XCTAssertTrue(canAccept)
    }

    func testHandleClosed() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        let sub = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])])

        // Mock the handleClosed behavior
        await relay.setNDK(NDK())

        await group.addItem(sub, filters: [createFilter(kinds: [1])])

        // Handle CLOSED message for a subscription ID when group has no subId
        await group.handleClosed(subscriptionId: "some-sub-id", message: "relay error")

        // Group should still be in initial state (not affected by non-matching ID)
        let canAccept = await group.canAcceptNewItems()
        XCTAssertTrue(canAccept)
    }

    // MARK: - Close Tests

    func testClose() async {
        let relay = createMockRelay()
        let group = NDKRelaySubscription(relay: relay, fingerprint: "test", isGroupable: true)

        await relay.setNDK(NDK())

        // Add a subscription
        let sub = createMockSubscription(id: "sub1", filters: [createFilter(kinds: [1])])
        await group.addItem(sub, filters: [createFilter(kinds: [1])])

        // Schedule execution
        await group.scheduleExecution(delay: 1.0, delayType: .atLeast)

        // Close the group
        await group.close()

        // Should not be active
        let isActive = await group.isActive()
        XCTAssertFalse(isActive)

        // Should not accept new items
        let canAccept = await group.canAcceptNewItems()
        XCTAssertFalse(canAccept)
    }
}
