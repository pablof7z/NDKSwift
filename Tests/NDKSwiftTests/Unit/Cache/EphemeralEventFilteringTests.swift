@testable import NDKSwiftCore
import XCTest

final class EphemeralEventFilteringTests: XCTestCase {
    var ndk: NDK!

    override func setUp() async throws {
        try await super.setUp()
        let signer = try NDKPrivateKeySigner.generate()
        let cache = try await NDKTestFactory.createTestCache()
        ndk = NDK(signer: signer, cache: cache)
    }

    // MARK: - NostrDB Cache Tests

    func testCacheDoesNotSaveEphemeralEvents() async throws {
        let cache = try await NDKTestFactory.createTestCache()

        // Create ephemeral events (kinds 20000-29999)
        let ephemeralEvent1 = try await createSignedEvent(kind: 20000, content: "ephemeral auth")
        let ephemeralEvent2 = try await createSignedEvent(kind: 25000, content: "ephemeral middle")
        let ephemeralEvent3 = try await createSignedEvent(kind: 29999, content: "ephemeral max")

        // Create non-ephemeral events
        let regularEvent = try await createSignedEvent(kind: 1, content: "regular note")
        let replaceableEvent = try await createSignedEvent(kind: 10000, content: "replaceable")
        let parameterizedEvent = try await createSignedEvent(kind: 30000, content: "parameterized")

        // Save all events
        try await cache.saveEvent(ephemeralEvent1)
        try await cache.saveEvent(ephemeralEvent2)
        try await cache.saveEvent(ephemeralEvent3)
        try await cache.saveEvent(regularEvent)
        try await cache.saveEvent(replaceableEvent)
        try await cache.saveEvent(parameterizedEvent)

        // Verify ephemeral events are not saved
        let retrieved1 = await cache.getEvent(id: ephemeralEvent1.id)
        let retrieved2 = await cache.getEvent(id: ephemeralEvent2.id)
        let retrieved3 = await cache.getEvent(id: ephemeralEvent3.id)

        XCTAssertNil(retrieved1, "Ephemeral event kind 20000 should not be cached")
        XCTAssertNil(retrieved2, "Ephemeral event kind 25000 should not be cached")
        XCTAssertNil(retrieved3, "Ephemeral event kind 29999 should not be cached")

        // Verify non-ephemeral events are saved
        let retrievedRegular = await cache.getEvent(id: regularEvent.id)
        let retrievedReplaceable = await cache.getEvent(id: replaceableEvent.id)
        let retrievedParameterized = await cache.getEvent(id: parameterizedEvent.id)

        XCTAssertNotNil(retrievedRegular, "Regular event should be cached")
        XCTAssertNotNil(retrievedReplaceable, "Replaceable event should be cached")
        XCTAssertNotNil(retrievedParameterized, "Parameterized event should be cached")
    }

    func testCacheQueryEventsExcludesEphemeral() async throws {
        let cache = try await NDKTestFactory.createTestCache()

        // Create and save mixed events
        let events = try [
            await createSignedEvent(kind: 1, content: "note 1"),
            await createSignedEvent(kind: 20001, content: "ephemeral 1"),
            await createSignedEvent(kind: 1, content: "note 2"),
            await createSignedEvent(kind: 25555, content: "ephemeral 2"),
            await createSignedEvent(kind: 30000, content: "parameterized"),
            await createSignedEvent(kind: 29999, content: "ephemeral max"),
        ]

        for event in events {
            try await cache.saveEvent(event)
        }

        // Query all events
        let filter = NDKFilter()
        let results = try await cache.queryEvents(filter)

        // Should only get non-ephemeral events
        XCTAssertEqual(results.count, 3, "Should only return 3 non-ephemeral events")

        // Verify all returned events are non-ephemeral
        for event in results {
            XCTAssertFalse(EventKind.isEphemeral(event.kind),
                           "Query should not return ephemeral events (kind: \(event.kind))")
        }

        // Verify we have the expected kinds
        let kinds = results.map { $0.kind }.sorted()
        XCTAssertEqual(kinds, [1, 1, 30000], "Should have correct non-ephemeral kinds")
    }

    func testCacheProcessEventSkipsEphemeral() async throws {
        let cache = try await NDKTestFactory.createTestCache()

        // Create ephemeral event
        let ephemeralEvent = try await createSignedEvent(kind: 22222, content: "ephemeral")

        // Process the event
        try await cache.processEvent(ephemeralEvent, from: "wss://relay.test", subscriptionId: "sub1")

        // Verify it wasn't saved
        let retrieved = await cache.getEvent(id: ephemeralEvent.id)
        XCTAssertNil(retrieved, "Ephemeral event should not be saved via processEvent")
    }

    // MARK: - Edge Case Tests

    func testBoundaryKinds() async throws {
        let cache = try await NDKTestFactory.createTestCache()

        // Test boundary values
        let justBelowEphemeral = try await createSignedEvent(kind: 19999, content: "not ephemeral")
        let firstEphemeral = try await createSignedEvent(kind: 20000, content: "first ephemeral")
        let lastEphemeral = try await createSignedEvent(kind: 29999, content: "last ephemeral")
        let justAboveEphemeral = try await createSignedEvent(kind: 30000, content: "not ephemeral")

        // Save all
        try await cache.saveEvent(justBelowEphemeral)
        try await cache.saveEvent(firstEphemeral)
        try await cache.saveEvent(lastEphemeral)
        try await cache.saveEvent(justAboveEphemeral)

        // Verify boundaries
        let retrievedBelow = await cache.getEvent(id: justBelowEphemeral.id)
        let retrievedFirst = await cache.getEvent(id: firstEphemeral.id)
        let retrievedLast = await cache.getEvent(id: lastEphemeral.id)
        let retrievedAbove = await cache.getEvent(id: justAboveEphemeral.id)

        XCTAssertNotNil(retrievedBelow, "Kind 19999 should be cached")
        XCTAssertNil(retrievedFirst, "Kind 20000 should not be cached")
        XCTAssertNil(retrievedLast, "Kind 29999 should not be cached")
        XCTAssertNotNil(retrievedAbove, "Kind 30000 should be cached")
    }

    func testQueryWithSpecificEphemeralKind() async throws {
        let cache = try await NDKTestFactory.createTestCache()

        // Create events
        let regularEvent = try await createSignedEvent(kind: 1, content: "note")
        let ephemeralEvent = try await createSignedEvent(kind: 22222, content: "ephemeral")

        try await cache.saveEvent(regularEvent)
        try await cache.saveEvent(ephemeralEvent)

        // Query specifically for the ephemeral kind
        let filter = NDKFilter(kinds: [22222])
        let results = try await cache.queryEvents(filter)

        // Should return empty even when specifically requested
        XCTAssertEqual(results.count, 0, "Should not return ephemeral events even when specifically filtered")
    }

    // MARK: - Helper Methods

    private func createSignedEvent(kind: Int, content: String) async throws -> NDKEvent {
        return try await NDKEventBuilder(ndk: ndk)
            .kind(kind)
            .content(content)
            .build()
    }
}
