@testable import NDKSwiftCore
@testable import NDKSwiftNostrDB
import XCTest

/// Integration tests for optimistic publishing with NDKNostrDBCache
final class NDKNostrDBCacheOptimisticIntegrationTests: NDKTestCase {
    var cache: NDKNostrDBCache!
    var tempDir: URL!

    /// Set to true to enable NostrDB tests (requires working C library)
    static let testsEnabled = true

    override func setUp() async throws {
        try await super.setUp()

        // Skip all tests if NostrDB tests are disabled
        guard Self.testsEnabled else {
            throw XCTSkip("NDKNostrDBCache tests are disabled - nostrdb C library crashes in test environment")
        }

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        cache = try await NDKNostrDBCache(path: tempDir.path)
    }

    override func tearDown() async throws {
        cache = nil
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Basic Integration Tests

    func testAddUnpublishedEventSavesToNostrDB() async throws {
        let event = EventTestFactory.createEvent(kind: EventKind.text, content: "Test event")

        // Add as unpublished
        try await cache.addUnpublishedEvent(
            event,
            publishedRelays: ["wss://relay1.com"],
            pendingRelays: ["wss://relay2.com": "timeout"]
        )

        // Event should be saved in nostrdb cache
        let retrieved = await cache.getEvent(id: event.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, event.id)
        XCTAssertEqual(retrieved?.content, "Test event")

        // Event should also be in unpublished store
        let unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].event.id, event.id)
    }

    func testConfirmEventUpdatesState() async throws {
        let event = EventTestFactory.createEvent(kind: EventKind.text, content: "Test event")

        // Add as unpublished (optimistic)
        try await cache.addUnpublishedEvent(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        // Initially optimistic
        var state = await cache.getEventConfirmationState(eventId: event.id)
        XCTAssertEqual(state, .optimistic)

        // Confirm on relay
        try await cache.confirmEvent(eventId: event.id, onRelay: "wss://relay1.com")

        // Now confirmed
        state = await cache.getEventConfirmationState(eventId: event.id)
        if case .confirmed(let relay) = state {
            XCTAssertEqual(relay, "wss://relay1.com")
        } else {
            XCTFail("Expected confirmed state")
        }
    }

    func testRecordPublishFailureTracksReason() async throws {
        let event = EventTestFactory.createEvent(kind: EventKind.text, content: "Test event")

        // Add as unpublished
        try await cache.addUnpublishedEvent(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "initial timeout"]
        )

        // Update failure reason
        try await cache.recordPublishFailure(
            eventId: event.id,
            relay: "wss://relay1.com",
            reason: "connection refused"
        )

        // Event should still be unpublished
        let unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
    }

    func testRemoveUnpublishedEventCleansUp() async throws {
        let event = EventTestFactory.createEvent(kind: EventKind.text, content: "Test event")

        // Add as unpublished
        try await cache.addUnpublishedEvent(
            event,
            publishedRelays: ["wss://relay1.com"],
            pendingRelays: ["wss://relay2.com": "timeout"]
        )

        // Verify it's there
        var unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)

        // Remove it (e.g., when threshold is met)
        try await cache.removeUnpublishedEvent(eventId: event.id)

        // Should be gone from unpublished
        unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)

        // But still in nostrdb cache
        let retrieved = await cache.getEvent(id: event.id)
        XCTAssertNotNil(retrieved)
    }

    // MARK: - Persistence Tests

    func testUnpublishedEventsPersistAcrossCacheRestart() async throws {
        let event = EventTestFactory.createEvent(kind: EventKind.text, content: "Persistent event")

        // Add as unpublished
        try await cache.addUnpublishedEvent(
            event,
            publishedRelays: ["wss://relay1.com"],
            pendingRelays: ["wss://relay2.com": "timeout"]
        )

        // Drop the cache
        cache = nil

        // Recreate cache with same path
        cache = try await NDKNostrDBCache(path: tempDir.path)

        // Event should still be in unpublished store
        let unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].event.id, event.id)

        // Confirmation state should be preserved
        let state = await cache.getEventConfirmationState(eventId: event.id)
        if case .confirmed(let relay) = state {
            XCTAssertEqual(relay, "wss://relay1.com")
        } else {
            XCTFail("Expected confirmed state to persist")
        }
    }

    func testClearRemovesUnpublishedEvents() async throws {
        let event = EventTestFactory.createEvent(kind: EventKind.text, content: "Test event")

        // Add as unpublished
        try await cache.addUnpublishedEvent(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        // Verify it's there
        var unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)

        // Clear cache
        try await cache.clear()

        // Unpublished events should be cleared
        unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testClearPersistedRemovesUnpublishedEvents() async throws {
        let event = EventTestFactory.createEvent(kind: EventKind.text, content: "Test event")

        // Add as unpublished
        try await cache.addUnpublishedEvent(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        // Verify it's there
        var unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)

        // Clear persisted data
        try await cache.clearPersisted()

        // Unpublished events should be cleared
        unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)

        // Event should also be cleared from nostrdb
        let retrieved = await cache.getEvent(id: event.id)
        XCTAssertNil(retrieved)
    }

    // MARK: - Real-World Scenario Tests

    func testMultipleEventsWithMixedStates() async throws {
        // Event 1: Fully published (2 relays)
        let event1 = EventTestFactory.createEvent(content: "Event 1")
        try await cache.addUnpublishedEvent(
            event1,
            publishedRelays: ["wss://relay1.com", "wss://relay2.com"],
            pendingRelays: [:]
        )

        // Event 2: Partially published (1/2 relays)
        let event2 = EventTestFactory.createEvent(content: "Event 2")
        try await cache.addUnpublishedEvent(
            event2,
            publishedRelays: ["wss://relay1.com"],
            pendingRelays: ["wss://relay2.com": "timeout"]
        )

        // Event 3: Completely failed (0/2 relays)
        let event3 = EventTestFactory.createEvent(content: "Event 3")
        try await cache.addUnpublishedEvent(
            event3,
            publishedRelays: [],
            pendingRelays: [
                "wss://relay1.com": "connection refused",
                "wss://relay2.com": "timeout"
            ]
        )

        // All should be tracked
        let unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 3)

        // Check states
        let state1 = await cache.getEventConfirmationState(eventId: event1.id)
        if case .confirmed = state1 {
            // Expected
        } else {
            XCTFail("Event 1 should be confirmed")
        }

        let state2 = await cache.getEventConfirmationState(eventId: event2.id)
        if case .confirmed = state2 {
            // Expected
        } else {
            XCTFail("Event 2 should be confirmed")
        }

        let state3 = await cache.getEventConfirmationState(eventId: event3.id)
        XCTAssertEqual(state3, .optimistic)
    }

    func testRetryScenario() async throws {
        let event = EventTestFactory.createEvent(content: "Retry event")

        // Initial publish: 2 succeed, 1 fails
        try await cache.addUnpublishedEvent(
            event,
            publishedRelays: ["wss://relay1.com", "wss://relay2.com"],
            pendingRelays: ["wss://relay3.com": "timeout"]
        )

        // Should be in unpublished (for retry on relay3)
        var unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].targetRelays.count, 3)

        // Simulate successful retry on relay3
        try await cache.confirmEvent(eventId: event.id, onRelay: "wss://relay3.com")

        // Still in unpublished (has target relays)
        unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)

        // NDK-core would decide to remove it when threshold is met
        try await cache.removeUnpublishedEvent(eventId: event.id)

        // Now it should be gone from unpublished
        unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testAgeFilteringInRealWorld() async throws {
        // Create an old event (3 hours ago)
        let oldEvent = EventTestFactory.createEvent(content: "Old event", createdAt: Timestamp.now - 10800)

        // Create a recent event
        let recentEvent = EventTestFactory.createEvent(content: "Recent event")

        try await cache.addUnpublishedEvent(
            oldEvent,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        try await cache.addUnpublishedEvent(
            recentEvent,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        // Get events with 1-hour max age (should only return recent)
        let recent = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].event.id, recentEvent.id)

        // Get events with 24-hour max age (should return both)
        let all = await cache.getUnpublishedEvents(maxAge: 86400, limit: nil)
        XCTAssertEqual(all.count, 2)
    }

    func testBulkOperations() async throws {
        // Add 20 unpublished events
        var events: [NDKEvent] = []
        for i in 0..<20 {
            let event = EventTestFactory.createEvent(content: "Event \(i)")
            events.append(event)

            try await cache.addUnpublishedEvent(
                event,
                publishedRelays: [],
                pendingRelays: ["wss://relay1.com": "timeout"]
            )
        }

        // All should be tracked
        var unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 20)

        // Confirm first 10
        for i in 0..<10 {
            try await cache.confirmEvent(eventId: events[i].id, onRelay: "wss://relay1.com")
        }

        // All still tracked (not removed yet)
        unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 20)

        // Remove first 10 (threshold met)
        for i in 0..<10 {
            try await cache.removeUnpublishedEvent(eventId: events[i].id)
        }

        // Should have 10 remaining
        unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 10)
    }
}
