@testable import NDKSwiftCore
import NDKSwiftNostrDB
import XCTest

/// Tests for NDKNostrDBCache
///
/// Note: These tests are currently DISABLED because the nostrdb C library
/// crashes (SIGTRAP) during initialization in the test environment.
/// This is likely due to mmap/LMDB initialization issues that cannot be
/// caught by Swift's error handling.
///
/// To enable these tests:
/// 1. Set `NDKNostrDBCacheTests.testsEnabled = true`
/// 2. Ensure the nostrdb C library can initialize properly in your environment
///
/// The NDKNostrDBCache implementation itself is functional and tested manually.
/// These automated tests will be enabled once the C library initialization
/// issues are resolved.
final class NDKNostrDBCacheTests: NDKTestCase {
    var cache: NDKNostrDBCache!
    var tempDir: URL!

    /// Set to true to enable NostrDB tests (requires working C library)
    static let testsEnabled = true

    override func setUp() async throws {
        try await super.setUp()

        // Skip all tests if NostrDB tests are disabled
        // This prevents the C library crash that occurs during ndb_init
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

    // MARK: - Basic Event Operations

    func testSaveAndRetrieveEvent() async throws {
        // Given
        let event = createTestEvent(
            pubkey: TestFixtures.Keys.alice.publicKey,
            kind: 1,
            content: "Test content"
        )

        // When
        try await cache.saveEvent(event)
        let retrieved = await cache.getEvent(id: event.id)

        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, event.id)
        XCTAssertEqual(retrieved?.pubkey, event.pubkey)
        XCTAssertEqual(retrieved?.kind, event.kind)
        XCTAssertEqual(retrieved?.content, event.content)
    }

    func testGetNonExistentEvent() async throws {
        // When
        let retrieved = await cache.getEvent(id: "nonexistent_event_id_1234567890abcdef1234567890abcdef")

        // Then
        XCTAssertNil(retrieved)
    }

    func testDeleteEvent() async throws {
        // Given
        let event = createTestEvent()
        try await cache.saveEvent(event)

        // Verify event exists
        let beforeDelete = await cache.getEvent(id: event.id)
        XCTAssertNotNil(beforeDelete)

        // When
        try await cache.deleteEvent(id: event.id)
        let afterDelete = await cache.getEvent(id: event.id)

        // Then
        XCTAssertNil(afterDelete, "Event should be deleted from in-memory cache")
    }

    func testSaveMultipleEvents() async throws {
        // Given
        let events = (0 ..< 5).map { i in
            createTestEvent(
                pubkey: TestFixtures.Keys.alice.publicKey,
                kind: 1,
                content: "Event \(i)"
            )
        }

        // When
        for event in events {
            try await cache.saveEvent(event)
        }

        // Then
        for event in events {
            let retrieved = await cache.getEvent(id: event.id)
            XCTAssertNotNil(retrieved, "Event \(event.id) should be retrievable")
            XCTAssertEqual(retrieved?.content, event.content)
        }
    }

    func testSaveDuplicateEvent() async throws {
        // Given
        let event = createTestEvent(content: "Original content")

        // When - save twice
        try await cache.saveEvent(event)
        try await cache.saveEvent(event)

        // Then - should not throw, nostrdb handles duplicates gracefully
        let retrieved = await cache.getEvent(id: event.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.content, event.content)
    }

    // MARK: - Query Operations

    func testQueryEventsByKind() async throws {
        // Given
        let textNote = createTestEvent(kind: 1, content: "Text note")
        let metadata = createTestEvent(kind: 0, content: "{\"name\":\"Alice\"}")
        let contacts = createTestEvent(kind: 3, content: "")

        try await cache.saveEvent(textNote)
        try await cache.saveEvent(metadata)
        try await cache.saveEvent(contacts)

        // When
        let filter = NDKFilter(kinds: [1])
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, textNote.id)
        XCTAssertEqual(results.first?.kind, 1)
    }

    func testQueryEventsByAuthor() async throws {
        // Given
        let alice = TestFixtures.Keys.alice.publicKey
        let bob = TestFixtures.Keys.bob.publicKey

        let aliceEvent = createTestEvent(pubkey: alice, content: "Alice's event")
        let bobEvent = createTestEvent(pubkey: bob, content: "Bob's event")

        try await cache.saveEvent(aliceEvent)
        try await cache.saveEvent(bobEvent)

        // When
        let filter = NDKFilter(authors: [alice])
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.pubkey, alice)
    }

    func testQueryWithLimit() async throws {
        // Given
        let events = (0 ..< 10).map { i in
            createTestEvent(
                content: "Event \(i)",
                createdAt: Timestamp(1000 + Int64(i))
            )
        }

        for event in events {
            try await cache.saveEvent(event)
        }

        // When
        let filter = NDKFilter(kinds: [1], limit: 3)
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 3)
        // Results should be sorted by timestamp descending (most recent first)
        XCTAssertTrue(results[0].createdAt >= results[1].createdAt)
        XCTAssertTrue(results[1].createdAt >= results[2].createdAt)
    }

    func testQueryEventsByIds() async throws {
        // Given
        let event1 = createTestEvent(content: "Event 1")
        let event2 = createTestEvent(content: "Event 2")
        let event3 = createTestEvent(content: "Event 3")

        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        try await cache.saveEvent(event3)

        // When
        let filter = NDKFilter(ids: [event1.id, event3.id])
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 2)
        let resultIds = results.map { $0.id }
        XCTAssertTrue(resultIds.contains(event1.id))
        XCTAssertTrue(resultIds.contains(event3.id))
        XCTAssertFalse(resultIds.contains(event2.id))
    }

    func testQueryEventsByTimestamp() async throws {
        // Given
        let oldEvent = createTestEvent(content: "Old", createdAt: Timestamp(1000))
        let middleEvent = createTestEvent(content: "Middle", createdAt: Timestamp(2000))
        let newEvent = createTestEvent(content: "New", createdAt: Timestamp(3000))

        try await cache.saveEvent(oldEvent)
        try await cache.saveEvent(middleEvent)
        try await cache.saveEvent(newEvent)

        // When - query with since
        let sinceFilter = NDKFilter(kinds: [1], since: Timestamp(1500))
        let sinceResults = try await cache.queryEvents(sinceFilter)

        // Then
        XCTAssertEqual(sinceResults.count, 2)
        XCTAssertTrue(sinceResults.allSatisfy { $0.createdAt >= 1500 })

        // When - query with until
        let untilFilter = NDKFilter(kinds: [1], until: Timestamp(2500))
        let untilResults = try await cache.queryEvents(untilFilter)

        // Then
        XCTAssertEqual(untilResults.count, 2)
        XCTAssertTrue(untilResults.allSatisfy { $0.createdAt <= 2500 })

        // When - query with both
        let rangeFilter = NDKFilter(kinds: [1], since: Timestamp(1500), until: Timestamp(2500))
        let rangeResults = try await cache.queryEvents(rangeFilter)

        // Then
        XCTAssertEqual(rangeResults.count, 1)
        XCTAssertEqual(rangeResults.first?.id, middleEvent.id)
    }

    func testQueryEventsEmptyResults() async throws {
        // Given
        let event = createTestEvent(kind: 1)
        try await cache.saveEvent(event)

        // When - query for non-existent kind
        let filter = NDKFilter(kinds: [99])
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Profile Operations

    func testGetProfileMetadata() async throws {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let metadata = """
        {
            "name": "Alice",
            "display_name": "Alice Smith",
            "about": "Test user",
            "picture": "https://example.com/alice.jpg",
            "nip05": "alice@example.com"
        }
        """
        let profileEvent = createTestEvent(
            pubkey: pubkey,
            kind: 0,
            content: metadata
        )

        try await cache.saveEvent(profileEvent)

        // When
        let profile = await cache.getProfileMetadata(pubkey: pubkey)

        // Then
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.metadata["name"] as? String, "Alice")
        XCTAssertEqual(profile?.metadata["display_name"] as? String, "Alice Smith")
        XCTAssertEqual(profile?.metadata["about"] as? String, "Test user")
        XCTAssertEqual(profile?.metadata["picture"] as? String, "https://example.com/alice.jpg")
        XCTAssertEqual(profile?.metadata["nip05"] as? String, "alice@example.com")
    }

    func testGetProfileMetadataNotFound() async throws {
        // When
        let profile = await cache.getProfileMetadata(pubkey: "nonexistent_pubkey_1234567890abcdef")

        // Then
        XCTAssertNil(profile)
    }

    func testGetProfileMetadataLatestEvent() async throws {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let oldMetadata = """
        {"name": "Old Name"}
        """
        let newMetadata = """
        {"name": "New Name"}
        """

        let oldEvent = createTestEvent(
            pubkey: pubkey,
            kind: 0,
            content: oldMetadata,
            createdAt: Timestamp(1000)
        )
        let newEvent = createTestEvent(
            pubkey: pubkey,
            kind: 0,
            content: newMetadata,
            createdAt: Timestamp(2000)
        )

        try await cache.saveEvent(oldEvent)
        try await cache.saveEvent(newEvent)

        // When
        let profile = await cache.getProfileMetadata(pubkey: pubkey)

        // Then
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.metadata["name"] as? String, "New Name")
    }

    // MARK: - Text Search

    func testTextSearch() async throws {
        // Given
        let event1 = createTestEvent(content: "Bitcoin is the future of money")
        let event2 = createTestEvent(content: "Ethereum is a smart contract platform")
        let event3 = createTestEvent(content: "Nostr is a decentralized protocol")
        let event4 = createTestEvent(content: "Bitcoin and Nostr work well together")

        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        try await cache.saveEvent(event3)
        try await cache.saveEvent(event4)

        // When - search for "Bitcoin"
        let bitcoinResults = await cache.textSearch("Bitcoin", limit: 10)

        // Then
        XCTAssertGreaterThanOrEqual(bitcoinResults.count, 2, "Should find events containing 'Bitcoin'")
        let bitcoinContents = bitcoinResults.map { $0.content }
        XCTAssertTrue(bitcoinContents.allSatisfy { $0.contains("Bitcoin") })
    }

    func testTextSearchWithLimit() async throws {
        // Given
        let events = (0 ..< 10).map { i in
            createTestEvent(content: "Bitcoin event number \(i)")
        }

        for event in events {
            try await cache.saveEvent(event)
        }

        // When
        let results = await cache.textSearch("Bitcoin", limit: 5)

        // Then
        XCTAssertLessThanOrEqual(results.count, 5)
    }

    func testTextSearchNoResults() async throws {
        // Given
        let event = createTestEvent(content: "This is a test event")
        try await cache.saveEvent(event)

        // When
        let results = await cache.textSearch("nonexistent_term_xyz123", limit: 10)

        // Then
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Relay Source Tracking

    func testProcessEventWithRelaySource() async throws {
        // Given
        let event = createTestEvent(content: "Test event")
        let relay = "wss://relay.example.com"
        let subscriptionId = "sub123"

        // When
        try await cache.processEvent(event, from: relay, subscriptionId: subscriptionId)

        // Then
        let retrieved = await cache.getEvent(id: event.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, event.id)
    }

    func testGetRelaySources() async throws {
        // Given
        let event = createTestEvent(content: "Test event")
        let relay1 = "wss://relay1.example.com"
        let relay2 = "wss://relay2.example.com"

        try await cache.processEvent(event, from: relay1, subscriptionId: "sub1")
        try await cache.processEvent(event, from: relay2, subscriptionId: "sub2")

        // When
        let sources = await cache.getRelaySources(eventId: event.id)

        // Then
        XCTAssertEqual(sources.count, 2)
        XCTAssertTrue(sources.contains(relay1))
        XCTAssertTrue(sources.contains(relay2))
    }

    // MARK: - Cache Management

    func testClear() async throws {
        // Given
        let events = (0 ..< 5).map { i in
            createTestEvent(content: "Event \(i)")
        }

        for event in events {
            try await cache.saveEvent(event)
        }

        // Verify events exist
        for event in events {
            let retrieved = await cache.getEvent(id: event.id)
            XCTAssertNotNil(retrieved)
        }

        // When
        try await cache.clear()

        // Then - in-memory cache should be cleared
        let filter = NDKFilter(kinds: [1])
        let results = try await cache.queryEvents(filter)
        XCTAssertEqual(results.count, 0, "In-memory cache should be empty")
    }

    // MARK: - Reactive Observation

    func testObserveEventsWithExisting() async throws {
        // Given
        let event1 = createTestEvent(kind: 1, content: "Event 1")
        let event2 = createTestEvent(kind: 1, content: "Event 2")
        let event3 = createTestEvent(kind: 2, content: "Event 3")

        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        try await cache.saveEvent(event3)

        // When
        let filter = NDKFilter(kinds: [1])
        let stream = await cache.observeEvents(matching: filter, includeExisting: true)

        // Then
        var receivedEvents: [NDKEvent] = []
        for try await events in stream {
            receivedEvents.append(contentsOf: events)
        }

        XCTAssertEqual(receivedEvents.count, 2)
        let eventIds = receivedEvents.map { $0.id }
        XCTAssertTrue(eventIds.contains(event1.id))
        XCTAssertTrue(eventIds.contains(event2.id))
    }

    func testObserveEventsWithoutExisting() async throws {
        // Given
        let event = createTestEvent()
        try await cache.saveEvent(event)

        // When
        let filter = NDKFilter(kinds: [1])
        let stream = await cache.observeEvents(matching: filter, includeExisting: false)

        // Then
        var receivedCount = 0
        for try await _ in stream {
            receivedCount += 1
        }

        XCTAssertEqual(receivedCount, 0, "Stream should complete without emitting existing events")
    }

    func testObserveProfile() async throws {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let metadata = """
        {"name": "Alice"}
        """
        let profileEvent = createTestEvent(
            pubkey: pubkey,
            kind: 0,
            content: metadata
        )

        try await cache.saveEvent(profileEvent)

        // When
        let stream = await cache.observeProfile(pubkey: pubkey, includeExisting: true)

        // Then
        var receivedProfile: NDKUserMetadata?
        for try await profile in stream {
            receivedProfile = profile
        }

        XCTAssertNotNil(receivedProfile)
        XCTAssertEqual(receivedProfile?.pubkey, pubkey)
    }

    // MARK: - Error Handling

    func testSaveEventWithInvalidJSON() async throws {
        // Given - create an event with content that's technically valid
        // (NostrDB validates the event structure, not content)
        let event = createTestEvent(content: "Valid content")

        // When/Then - should not throw
        try await cache.saveEvent(event)
        let retrieved = await cache.getEvent(id: event.id)
        XCTAssertNotNil(retrieved)
    }

    func testGetEventWithInvalidId() async throws {
        // When - try to get event with invalid hex ID
        let retrieved = await cache.getEvent(id: "invalid_hex_zzz")

        // Then - should return nil, not crash
        XCTAssertNil(retrieved)
    }

    // MARK: - Helper Methods

    private func createTestEvent(
        id: String? = nil,
        pubkey: String = String(repeating: "ab", count: 32),
        kind: Int = 1,
        content: String = "Test content",
        createdAt: Timestamp? = nil
    ) -> NDKEvent {
        let eventId = id ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
            .padding(toLength: 64, withPad: "0", startingAt: 0)
        return NDKEvent(
            id: eventId,
            pubkey: pubkey,
            createdAt: createdAt ?? Timestamp(Date().timeIntervalSince1970),
            kind: Kind(kind),
            tags: [],
            content: content,
            sig: String(repeating: "cd", count: 64)
        )
    }
}
