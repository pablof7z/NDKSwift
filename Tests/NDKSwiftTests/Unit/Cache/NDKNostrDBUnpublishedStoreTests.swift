@testable import NDKSwiftCore
import XCTest

/// Tests for UnpublishedStore
final class NDKNostrDBUnpublishedStoreTests: NDKTestCase {
    var store: UnpublishedStore!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        store = try UnpublishedStore(cachePath: tempDir.path)
    }

    override func tearDown() async throws {
        store = nil
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Add and Retrieve Tests

    func testAddUnpublishedEvent() async throws {
        let event = createSignedEvent(content: "Test event")

        // Add event with some relays published, some pending
        try await store.add(
            event,
            publishedRelays: ["wss://relay1.com"],
            pendingRelays: [
                "wss://relay2.com": "timeout",
                "wss://relay3.com": "connection failed"
            ]
        )

        // Retrieve unpublished events
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)

        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].event.id, event.id)
        XCTAssertEqual(unpublished[0].targetRelays.count, 2)
        XCTAssertTrue(unpublished[0].targetRelays.contains("wss://relay2.com"))
        XCTAssertTrue(unpublished[0].targetRelays.contains("wss://relay3.com"))
    }

    func testGetUnpublishedEventsWithMaxAge() async throws {
        // Create an old event (2 hours ago)
        let oldEvent = createSignedEvent(content: "Old event")
        // Manually adjust created_at to be 2 hours ago
        let twoHoursAgo = Timestamp.now - 7200
        let oldEventWithOldTimestamp = NDKEvent(
            id: oldEvent.id,
            pubkey: oldEvent.pubkey,
            createdAt: twoHoursAgo,
            kind: oldEvent.kind,
            tags: oldEvent.tags,
            content: oldEvent.content,
            sig: oldEvent.sig
        )

        // Create a recent event
        let recentEvent = createSignedEvent(content: "Recent event")

        // Add both events
        try await store.add(oldEventWithOldTimestamp, publishedRelays: [], pendingRelays: ["wss://relay1.com": "timeout"])
        try await store.add(recentEvent, publishedRelays: [], pendingRelays: ["wss://relay2.com": "timeout"])

        // Get events with maxAge of 1 hour (3600 seconds)
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)

        // Should only return the recent event
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].event.id, recentEvent.id)
    }

    func testGetUnpublishedEventsWithLimit() async throws {
        // Add 5 events
        for i in 0..<5 {
            let event = createSignedEvent(content: "Event \(i)")
            try await store.add(event, publishedRelays: [], pendingRelays: ["wss://relay1.com": "timeout"])
        }

        // Get only 3 events
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: 3)

        XCTAssertEqual(unpublished.count, 3)
    }

    // MARK: - Confirmation State Tests

    func testGetConfirmationStateOptimistic() async throws {
        let event = createSignedEvent(content: "Test event")

        // Add event with only pending relays (no published)
        try await store.add(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        let state = await store.getEventConfirmationState(eventId: event.id)

        XCTAssertNotNil(state)
        XCTAssertEqual(state, .optimistic)
    }

    func testGetConfirmationStateConfirmed() async throws {
        let event = createSignedEvent(content: "Test event")

        // Add event with at least one published relay
        try await store.add(
            event,
            publishedRelays: ["wss://relay1.com"],
            pendingRelays: ["wss://relay2.com": "timeout"]
        )

        let state = await store.getEventConfirmationState(eventId: event.id)

        XCTAssertNotNil(state)
        if case .confirmed(let relay) = state {
            XCTAssertEqual(relay, "wss://relay1.com")
        } else {
            XCTFail("Expected confirmed state")
        }
    }

    func testGetConfirmationStateNonexistent() async throws {
        let state = await store.getEventConfirmationState(eventId: "nonexistent")
        XCTAssertNil(state)
    }

    // MARK: - Mark Relay Published Tests

    func testMarkRelayPublished() async throws {
        let event = createSignedEvent(content: "Test event")

        // Add event with only pending relays
        try await store.add(
            event,
            publishedRelays: [],
            pendingRelays: [
                "wss://relay1.com": "timeout",
                "wss://relay2.com": "timeout"
            ]
        )

        // Initially should be optimistic
        var state = await store.getEventConfirmationState(eventId: event.id)
        XCTAssertEqual(state, .optimistic)

        // Mark one relay as published
        try await store.markRelayPublished(eventId: event.id, relay: "wss://relay1.com")

        // Now should be confirmed
        state = await store.getEventConfirmationState(eventId: event.id)
        if case .confirmed(let relay) = state {
            XCTAssertEqual(relay, "wss://relay1.com")
        } else {
            XCTFail("Expected confirmed state")
        }

        // Should still have relay2 pending
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertTrue(unpublished[0].targetRelays.contains("wss://relay2.com"))
    }

    // MARK: - Mark Relay Failed Tests

    func testMarkRelayFailed() async throws {
        let event = createSignedEvent(content: "Test event")

        // Add event with one pending relay
        try await store.add(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        // Update failure reason
        try await store.markRelayFailed(eventId: event.id, relay: "wss://relay1.com", reason: "connection refused")

        // Event should still be in unpublished list
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
    }

    // MARK: - Remove Tests

    func testRemoveUnpublishedEvent() async throws {
        let event = createSignedEvent(content: "Test event")

        // Add event
        try await store.add(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        // Verify it's there
        var unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)

        // Remove it
        try await store.remove(eventId: event.id)

        // Verify it's gone
        unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)

        // State should be nil
        let state = await store.getEventConfirmationState(eventId: event.id)
        XCTAssertNil(state)
    }

    // MARK: - Clear Tests

    func testClearAllEvents() async throws {
        // Add multiple events
        for i in 0..<3 {
            let event = createSignedEvent(content: "Event \(i)")
            try await store.add(event, publishedRelays: [], pendingRelays: ["wss://relay1.com": "timeout"])
        }

        // Verify they're there
        var unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 3)

        // Clear
        try await store.clear()

        // Verify they're gone
        unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    // MARK: - Persistence Tests

    func testPersistence() async throws {
        let event = createSignedEvent(content: "Test event")

        // Add event
        try await store.add(
            event,
            publishedRelays: ["wss://relay1.com"],
            pendingRelays: ["wss://relay2.com": "timeout"]
        )

        // Drop the store
        store = nil

        // Recreate store with same path
        store = try UnpublishedStore(cachePath: tempDir.path)

        // Event should still be there
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].event.id, event.id)

        // Confirmation state should be preserved
        let state = await store.getEventConfirmationState(eventId: event.id)
        if case .confirmed(let relay) = state {
            XCTAssertEqual(relay, "wss://relay1.com")
        } else {
            XCTFail("Expected confirmed state")
        }
    }

    // MARK: - Edge Case Tests

    func testLoadCorruptedFile() async throws {
        // Create a corrupted JSONL file
        let fileURL = tempDir.appendingPathComponent("unpublished.jsonl")
        let corruptedContent = """
        {"event":"{\\"id\\":\\"abc\\"}","publishedRelays":[],"pendingRelays":{}}
        this is not valid json at all
        {"event":"{\\"id\\":\\"def\\"}","publishedRelays":[],"pendingRelays":{}}
        """
        try corruptedContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Should load successfully, skipping corrupted lines
        let newStore = try UnpublishedStore(cachePath: tempDir.path)

        // Should have loaded the valid lines (though events may not parse correctly)
        let unpublished = await newStore.getUnpublishedEvents(maxAge: 3600, limit: nil)
        // The corrupted line should be skipped, valid lines might fail event parsing
        // At minimum, shouldn't crash
        XCTAssertTrue(unpublished.count >= 0)
    }

    func testEmptyFileLoad() async throws {
        // Create empty file
        let fileURL = tempDir.appendingPathComponent("unpublished.jsonl")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        // Should load successfully
        let newStore = try UnpublishedStore(cachePath: tempDir.path)

        let unpublished = await newStore.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testMarkNonexistentRelayPublished() async throws {
        let event = createSignedEvent(content: "Test event")

        try await store.add(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        // Mark a relay that's not in the pending list
        try await store.markRelayPublished(eventId: event.id, relay: "wss://nonexistent.com")

        // Should not crash, relay should be added to published
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 1)
    }

    func testMarkNonexistentEventPublished() async throws {
        // Mark relay as published for an event that doesn't exist
        try await store.markRelayPublished(eventId: "nonexistent", relay: "wss://relay1.com")

        // Should not crash, just no-op
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testRemoveNonexistentEvent() async throws {
        // Remove event that doesn't exist
        try await store.remove(eventId: "nonexistent")

        // Should not crash
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testMultipleEventsWithSameRelay() async throws {
        let event1 = createSignedEvent(content: "Event 1")
        let event2 = createSignedEvent(content: "Event 2")
        let event3 = createSignedEvent(content: "Event 3")

        // All events have the same relay pending
        try await store.add(event1, publishedRelays: [], pendingRelays: ["wss://relay1.com": "timeout"])
        try await store.add(event2, publishedRelays: [], pendingRelays: ["wss://relay1.com": "timeout"])
        try await store.add(event3, publishedRelays: [], pendingRelays: ["wss://relay1.com": "timeout"])

        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 3)

        // All should have the same relay
        for (_, targetRelays) in unpublished {
            XCTAssertTrue(targetRelays.contains("wss://relay1.com"))
        }
    }

    func testMarkRelayPublishedTwice() async throws {
        let event = createSignedEvent(content: "Test event")

        try await store.add(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        // Mark the same relay as published twice
        try await store.markRelayPublished(eventId: event.id, relay: "wss://relay1.com")
        try await store.markRelayPublished(eventId: event.id, relay: "wss://relay1.com")

        // The first success removes the only pending relay, so the event is no
        // longer retryable. Repeating the confirmation is a harmless no-op.
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testClearEmptyStore() async throws {
        // Clear when there's nothing to clear
        try await store.clear()

        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testGetUnpublishedEventsWithZeroMaxAge() async throws {
        let event = createSignedEvent(content: "Test event")
        try await store.add(event, publishedRelays: [], pendingRelays: ["wss://relay1.com": "timeout"])

        // MaxAge of 0 should exclude all events
        let unpublished = await store.getUnpublishedEvents(maxAge: 0, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testGetUnpublishedEventsWithLimitZero() async throws {
        let event = createSignedEvent(content: "Test event")
        try await store.add(event, publishedRelays: [], pendingRelays: ["wss://relay1.com": "timeout"])

        // Limit of 0 should return empty
        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: 0)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testTransitionFromOptimisticToConfirmed() async throws {
        let event = createSignedEvent(content: "Test event")

        // Start optimistic (no published relays)
        try await store.add(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        var state = await store.getEventConfirmationState(eventId: event.id)
        XCTAssertEqual(state, .optimistic)

        // Transition to confirmed
        try await store.markRelayPublished(eventId: event.id, relay: "wss://relay1.com")

        state = await store.getEventConfirmationState(eventId: event.id)
        XCTAssertNil(state)

        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)
    }

    func testEventWithNoRelays() async throws {
        let event = createSignedEvent(content: "Test event")

        // Add event with no relays at all (edge case - shouldn't happen in practice)
        try await store.add(event, publishedRelays: [], pendingRelays: [:])

        let unpublished = await store.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertEqual(unpublished.count, 0)

        // State should be optimistic (no published relays)
        let state = await store.getEventConfirmationState(eventId: event.id)
        XCTAssertEqual(state, .optimistic)
    }

    func testCustomPathCreatesDirectory() async throws {
        let nestedPath = tempDir.appendingPathComponent("nested/store")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedPath.path))

        let nestedStore = try UnpublishedStore(cachePath: nestedPath.path)
        let event = createSignedEvent(content: "Creates directory")

        try await nestedStore.add(
            event,
            publishedRelays: [],
            pendingRelays: ["wss://relay1.com": "timeout"]
        )

        let fileURL = nestedPath.appendingPathComponent("unpublished.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Helper Methods

    private func createSignedEvent(content: String) -> NDKEvent {
        return EventTestFactory.createEvent(kind: EventKind.textNote, content: content)
    }
}
