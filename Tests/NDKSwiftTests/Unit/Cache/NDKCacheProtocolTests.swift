import CashuSwift
import NDKSwiftCashu
@testable import NDKSwiftCore
import XCTest

/// Mock cache implementation for testing the protocol
actor MockNDKCacheProtocol: NDKCache {
    // Storage for testing
    private var events: [String: NDKEvent] = [:]
    private var unpublishedEvents: [String: (event: NDKEvent, targetRelays: Set<String>)] = [:]
    private var eventConfirmations: [String: EventConfirmationState] = [:]
    private var decryptedContent: [String: String] = [:] // Key: "eventId:viewerPubkey"
    private var mintInfos: [String: NDKMintInfo] = [:]
    private var keysets: [String: CashuSwift.Keyset] = [:]
    private var profileMetadata: [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] = [:]
    private var nip05Entries: [String: NIP05CacheEntry] = [:]
    private var relayPreferences: [String: (writeRelays: [String]?, readRelays: [String]?, fetchedAt: Date, expiresAt: Date, checkedRelays: Set<String>?)] = [:]
    private var fetchTimes: [String: Date] = [:]
    private var relaySources: [String: Set<String>] = [:]

    // Tracking for test verification
    var saveEventCalled = false
    var clearCalled = false

    // MARK: - Event Operations

    func saveEvent(_ event: NDKEvent) async throws {
        saveEventCalled = true
        events[event.id] = event
    }

    func getEvent(id: String) async -> NDKEvent? {
        return events[id]
    }

    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        var results = Array(events.values)

        // Apply filter criteria
        if let authors = filter.authors, !authors.isEmpty {
            results = results.filter { authors.contains($0.pubkey) }
        }

        if let kinds = filter.kinds, !kinds.isEmpty {
            results = results.filter { kinds.contains($0.kind) }
        }

        if let ids = filter.ids, !ids.isEmpty {
            results = results.filter { ids.contains($0.id) }
        }

        if let since = filter.since {
            results = results.filter { $0.createdAt >= since }
        }

        if let until = filter.until {
            results = results.filter { $0.createdAt <= until }
        }

        // Apply limit
        if let limit = filter.limit {
            results = Array(results.prefix(limit))
        }

        return results
    }

    func deleteEvent(id: String) async throws {
        events.removeValue(forKey: id)
    }

    // MARK: - Optimistic Publishing

    func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws {
        unpublishedEvents[event.id] = (event, relays)
        try await saveEvent(event)
    }

    func confirmEvent(eventId: String, onRelay relay: String) async throws {
        if var entry = unpublishedEvents[eventId] {
            entry.targetRelays.remove(relay)
            if entry.targetRelays.isEmpty {
                unpublishedEvents.removeValue(forKey: eventId)
                eventConfirmations[eventId] = .confirmed(fromRelay: relay)
            } else {
                unpublishedEvents[eventId] = entry
            }
        }
    }

    func getEventConfirmationState(eventId: String) async -> EventConfirmationState? {
        return eventConfirmations[eventId]
    }

    func getUnpublishedEvents(maxAge _: TimeInterval, limit: Int?) async -> [(event: NDKEvent, targetRelays: Set<String>)] {
        let results = Array(unpublishedEvents.values)
        if let limit = limit {
            return Array(results.prefix(limit))
        }
        return results
    }

    // MARK: - Decrypted Content

    func getDecryptedContent(for eventId: String, viewerPubkey: String) async -> String? {
        let key = "\(eventId):\(viewerPubkey)"
        return decryptedContent[key]
    }

    func storeDecryptedContent(_ content: String, for eventId: String, viewerPubkey: String) async {
        let key = "\(eventId):\(viewerPubkey)"
        decryptedContent[key] = content
    }

    func clearDecryptedContent() async {
        decryptedContent.removeAll()
    }

    func clearDecryptedContent(for viewerPubkey: String) async {
        decryptedContent = decryptedContent.filter { !$0.key.hasSuffix(":\(viewerPubkey)") }
    }

    // MARK: - Mint Cache

    func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        mintInfos[url] = info
    }

    func getMintInfo(url: String) async -> NDKMintInfo? {
        return mintInfos[url]
    }

    func isMintInfoStale(url _: String, maxAge _: TimeInterval) async -> Bool {
        // For testing, always return false
        return false
    }

    func invalidateMintCache(url: String) async throws {
        mintInfos.removeValue(forKey: url)
    }

    func saveKeyset(_ keyset: CashuSwift.Keyset, mintUrl _: String) async throws {
        keysets[keyset.keysetID] = keyset
    }

    func saveKeysets(_ keysets: [CashuSwift.Keyset], mintUrl _: String) async throws {
        for keyset in keysets {
            self.keysets[keyset.keysetID] = keyset
        }
    }

    func getKeyset(id: String) async -> CashuSwift.Keyset? {
        return keysets[id]
    }

    func getKeysets(mintUrl _: String) async -> [CashuSwift.Keyset] {
        // For testing, return all keysets
        return Array(keysets.values)
    }

    func getActiveKeysets(mintUrl _: String, unit: String) async -> [CashuSwift.Keyset] {
        return keysets.values.filter { $0.unit == unit && $0.active }
    }

    func areKeysetsStale(mintUrl _: String, maxAge _: TimeInterval) async -> Bool {
        // For testing, always return false
        return false
    }

    // MARK: - Negentropy Support

    func getEventsByTimeRange(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [NDKEvent] {
        var results = events.values.filter { $0.createdAt >= from && $0.createdAt < to }

        if let filter = filter {
            if let authors = filter.authors, !authors.isEmpty {
                results = results.filter { authors.contains($0.pubkey) }
            }
            if let kinds = filter.kinds, !kinds.isEmpty {
                results = results.filter { kinds.contains($0.kind) }
            }
        }

        return Array(results)
    }

    func getEventIdsWithTimestamps(from: Timestamp, to: Timestamp, filter: NDKFilter?) async throws -> [(id: String, timestamp: Timestamp)] {
        let events = try await getEventsByTimeRange(from: from, to: to, filter: filter)
        return events.map { (id: $0.id, timestamp: $0.createdAt) }
    }

    func hasEvents(ids: [String]) async -> [String: Bool] {
        var result: [String: Bool] = [:]
        for id in ids {
            result[id] = events[id] != nil
        }
        return result
    }

    // MARK: - Profile Observation

    func observeProfile(pubkey: String, includeExisting: Bool) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Send existing profile if requested
                if includeExisting {
                    if let (metadata, updatedAt, eventId) = await getProfileMetadata(pubkey: pubkey) {
                        let userMetadata = NDKUserMetadata(pubkey: pubkey, parsedMetadata: metadata, updatedAt: updatedAt, eventId: eventId)
                        continuation.yield(userMetadata)
                    }
                }

                // No new events stream for testing, so finish
                continuation.finish()
            }
        }
    }

    // MARK: - Profile Metadata

    func saveProfileMetadata(pubkey: String, metadata: [String: Any], updatedAt: Timestamp, eventId: String) async throws {
        profileMetadata[pubkey] = (metadata, updatedAt, eventId)
    }

    func getProfileMetadata(pubkey: String) async -> (metadata: [String: Any], updatedAt: Timestamp, eventId: String)? {
        return profileMetadata[pubkey]
    }

    func getMultipleProfileMetadata(pubkeys: [String]) async -> [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] {
        var result: [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] = [:]
        for pubkey in pubkeys {
            if let data = profileMetadata[pubkey] {
                result[pubkey] = data
            }
        }
        return result
    }

    // MARK: - Cache Management

    func clear() async throws {
        clearCalled = true
        events.removeAll()
        unpublishedEvents.removeAll()
        eventConfirmations.removeAll()
        decryptedContent.removeAll()
        mintInfos.removeAll()
        keysets.removeAll()
        profileMetadata.removeAll()
        nip05Entries.removeAll()
        relayPreferences.removeAll()
        fetchTimes.removeAll()
        relaySources.removeAll()
    }

    // MARK: - Reactive Observation

    func observeEvents(matching filter: NDKFilter, includeExisting: Bool) async -> AsyncThrowingStream<[NDKEvent], Error> {
        // Simple implementation for testing
        return AsyncThrowingStream { continuation in
            Task {
                if includeExisting {
                    let existing = try await queryEvents(filter)
                    continuation.yield(existing)
                }
                continuation.finish()
            }
        }
    }

    func processEvent(_ event: NDKEvent, from relay: String, subscriptionId _: String) async throws {
        try await saveEvent(event)

        // Track relay source
        if var sources = relaySources[event.id] {
            sources.insert(relay)
            relaySources[event.id] = sources
        } else {
            relaySources[event.id] = [relay]
        }
    }

    func getRelaySources(eventId: String) async -> Set<String> {
        return relaySources[eventId] ?? []
    }

    // MARK: - Cache Freshness

    func getLastFetchTime(for filter: NDKFilter) async -> Date? {
        let key = filter.fingerprint
        return fetchTimes[key]
    }

    func recordFetchTime(for filter: NDKFilter, timestamp: Date) async {
        let key = filter.fingerprint
        fetchTimes[key] = timestamp
    }

    // MARK: - NIP-05 Operations

    func saveNIP05Claim(_ identifier: String, pubkey: String, retrievedAt: Date) async throws {
        let entry = NIP05CacheEntry(
            identifier: identifier,
            pubkey: pubkey,
            status: .unverified,
            claimedAt: retrievedAt
        )
        nip05Entries[identifier] = entry
    }

    func getNIP05Entry(_ identifier: String) async -> NIP05CacheEntry? {
        return nip05Entries[identifier]
    }

    func getNIP05Entries(pubkey: String) async -> [NIP05CacheEntry] {
        return nip05Entries.values.filter { $0.pubkey == pubkey }
    }

    func searchNIP05(_ prefix: String, limit: Int) async -> [NIP05CacheEntry] {
        let results = nip05Entries.values.filter { $0.identifier.hasPrefix(prefix) }
        return Array(results.prefix(limit))
    }

    func saveNIP05Resolution(_ entry: NIP05CacheEntry) async throws {
        nip05Entries[entry.identifier] = entry
    }

    func invalidateNIP05(_ identifier: String, actualPubkey _: String?) async throws {
        if var entry = nip05Entries[identifier] {
            entry.status = .invalid
            nip05Entries[identifier] = entry
        }
    }

    func needsNIP05Verification(_ identifier: String, maxAge _: TimeInterval) async -> Bool {
        guard let entry = nip05Entries[identifier] else { return true }
        return entry.status == .unverified || entry.status == .expired
    }

    func getUnverifiedNIP05s(limit: Int) async -> [NIP05CacheEntry] {
        let results = nip05Entries.values.filter { $0.status == .unverified }
        return Array(results.prefix(limit))
    }

    func canVerifyDomain(_: String) async -> Bool {
        // For testing, always allow
        return true
    }

    func recordDomainVerificationAttempt(_: String) async {
        // For testing, do nothing
    }

    // MARK: - Relay Preferences

    func saveRelayPreferences(
        pubkey: String,
        writeRelays: [String]?,
        readRelays: [String]?,
        fetchedAt: Date,
        expiresAt: Date,
        checkedRelays: Set<String>?
    ) async throws {
        relayPreferences[pubkey] = (writeRelays, readRelays, fetchedAt, expiresAt, checkedRelays)
    }

    func getRelayPreferences(
        pubkey: String
    ) async -> (writeRelays: [String]?, readRelays: [String]?, fetchedAt: Date, expiresAt: Date, checkedRelays: Set<String>?)? {
        return relayPreferences[pubkey]
    }
}

/// Test suite for NDKCache protocol implementations
final class NDKCacheProtocolTests: XCTestCase {
    var cache: MockNDKCacheProtocol!

    override func setUp() async throws {
        try await super.setUp()
        cache = MockNDKCacheProtocol()
    }

    override func tearDown() async throws {
        cache = nil
        try await super.tearDown()
    }

    // MARK: - Event Operations Tests

    func testSaveAndRetrieveEvent() async throws {
        // Given
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test event",
            tags: []
        )

        // When
        try await cache.saveEvent(event)
        let retrieved = await cache.getEvent(id: event.id)

        // Then
        let saveEventCalled = await cache.saveEventCalled
        XCTAssertTrue(saveEventCalled)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, event.id)
        XCTAssertEqual(retrieved?.content, event.content)
    }

    func testQueryEventsByAuthor() async throws {
        // Given
        let author = "test_author_pubkey"
        let event1 = EventTestFactory.createEvent(kind: 1, content: "Event 1", pubkey: author)
        let event2 = EventTestFactory.createEvent(kind: 1, content: "Event 2", pubkey: author)
        let event3 = EventTestFactory.createEvent(kind: 1, content: "Event 3", pubkey: "other_author")

        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        try await cache.saveEvent(event3)

        // When
        let filter = NDKFilter(authors: [author])
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.id == event1.id })
        XCTAssertTrue(results.contains { $0.id == event2.id })
        XCTAssertFalse(results.contains { $0.id == event3.id })
    }

    func testQueryEventsByKind() async throws {
        // Given
        let event1 = EventTestFactory.createEvent(kind: 1, content: "Text note")
        let event2 = EventTestFactory.createEvent(kind: 0, content: "Metadata")
        let event3 = EventTestFactory.createEvent(kind: 1, content: "Another text note")

        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        try await cache.saveEvent(event3)

        // When
        let filter = NDKFilter(kinds: [1])
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.kind == 1 })
    }

    func testQueryEventsWithTimeRange() async throws {
        // Given
        let now = Timestamp.now
        let event1 = EventTestFactory.createEvent(kind: 1, content: "Old", createdAt: now - 1000)
        let event2 = EventTestFactory.createEvent(kind: 1, content: "Middle", createdAt: now - 500)
        let event3 = EventTestFactory.createEvent(kind: 1, content: "Recent", createdAt: now - 100)

        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        try await cache.saveEvent(event3)

        // When
        let filter = NDKFilter(since: now - 600, until: now)
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.id == event2.id })
        XCTAssertTrue(results.contains { $0.id == event3.id })
    }

    func testQueryEventsWithLimit() async throws {
        // Given
        for i in 0 ..< 10 {
            let event = EventTestFactory.createEvent(kind: 1, content: "Event \(i)")
            try await cache.saveEvent(event)
        }

        // When
        let filter = NDKFilter(kinds: [1], limit: 5)
        let results = try await cache.queryEvents(filter)

        // Then
        XCTAssertEqual(results.count, 5)
    }

    func testDeleteEvent() async throws {
        // Given
        let event = EventTestFactory.createEvent(kind: 1, content: "To be deleted")
        try await cache.saveEvent(event)

        // When
        try await cache.deleteEvent(id: event.id)
        let retrieved = await cache.getEvent(id: event.id)

        // Then
        XCTAssertNil(retrieved)
    }

    // MARK: - Optimistic Publishing Tests

    func testAddUnpublishedEvent() async throws {
        // Given
        let event = EventTestFactory.createEvent(kind: 1, content: "Unpublished")
        let relays: Set<String> = ["wss://relay1.com", "wss://relay2.com"]

        // When
        try await cache.addUnpublishedEvent(event, relays: relays)
        let unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)

        // Then
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].event.id, event.id)
        XCTAssertEqual(unpublished[0].targetRelays, relays)
    }

    func testConfirmEventPublication() async throws {
        // Given
        let event = EventTestFactory.createEvent(kind: 1, content: "To confirm")
        let relays: Set<String> = ["wss://relay1.com", "wss://relay2.com"]
        try await cache.addUnpublishedEvent(event, relays: relays)

        // When
        try await cache.confirmEvent(eventId: event.id, onRelay: "wss://relay1.com")
        let unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)

        // Then
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished[0].targetRelays, ["wss://relay2.com"])

        // Confirm on second relay
        try await cache.confirmEvent(eventId: event.id, onRelay: "wss://relay2.com")
        let finalUnpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)

        XCTAssertEqual(finalUnpublished.count, 0)

        let state = await cache.getEventConfirmationState(eventId: event.id)
        XCTAssertNotNil(state)
        XCTAssertTrue(state?.isConfirmed ?? false)
    }

    // MARK: - Decrypted Content Tests

    func testStoreAndRetrieveDecryptedContent() async throws {
        // Given
        let eventId = "test_event_id"
        let viewerPubkey = "viewer_pubkey"
        let content = "Decrypted secret message"

        // When
        await cache.storeDecryptedContent(content, for: eventId, viewerPubkey: viewerPubkey)
        let retrieved = await cache.getDecryptedContent(for: eventId, viewerPubkey: viewerPubkey)

        // Then
        XCTAssertEqual(retrieved, content)
    }

    func testClearDecryptedContentForViewer() async throws {
        // Given
        let eventId1 = "event1"
        let eventId2 = "event2"
        let viewer1 = "viewer1"
        let viewer2 = "viewer2"

        await cache.storeDecryptedContent("Content 1-1", for: eventId1, viewerPubkey: viewer1)
        await cache.storeDecryptedContent("Content 1-2", for: eventId1, viewerPubkey: viewer2)
        await cache.storeDecryptedContent("Content 2-1", for: eventId2, viewerPubkey: viewer1)

        // When
        await cache.clearDecryptedContent(for: viewer1)

        // Then
        let content1 = await cache.getDecryptedContent(for: eventId1, viewerPubkey: viewer1)
        let content2 = await cache.getDecryptedContent(for: eventId2, viewerPubkey: viewer1)
        let content3 = await cache.getDecryptedContent(for: eventId1, viewerPubkey: viewer2)
        XCTAssertNil(content1)
        XCTAssertNil(content2)
        XCTAssertEqual(content3, "Content 1-2")
    }

    func testClearAllDecryptedContent() async throws {
        // Given
        await cache.storeDecryptedContent("Content 1", for: "event1", viewerPubkey: "viewer1")
        await cache.storeDecryptedContent("Content 2", for: "event2", viewerPubkey: "viewer2")

        // When
        await cache.clearDecryptedContent()

        // Then
        let content1 = await cache.getDecryptedContent(for: "event1", viewerPubkey: "viewer1")
        let content2 = await cache.getDecryptedContent(for: "event2", viewerPubkey: "viewer2")
        XCTAssertNil(content1)
        XCTAssertNil(content2)
    }

    // MARK: - Profile Metadata Tests

    func testSaveAndRetrieveProfileMetadata() async throws {
        // Given
        let pubkey = "test_pubkey"
        let metadata: [String: Any] = [
            "name": "Test User",
            "about": "Test description",
            "picture": "https://example.com/pic.jpg",
        ]
        let updatedAt = Timestamp.now
        let eventId = "metadata_event_id"

        // When
        try await cache.saveProfileMetadata(pubkey: pubkey, metadata: metadata, updatedAt: updatedAt, eventId: eventId)
        let retrieved = await cache.getProfileMetadata(pubkey: pubkey)

        // Then
        XCTAssertNotNil(retrieved)
        if let metadata = retrieved?.metadata {
            XCTAssertEqual(metadata["name"] as? String, "Test User")
        }
        XCTAssertEqual(retrieved?.updatedAt, updatedAt)
        XCTAssertEqual(retrieved?.eventId, eventId)
    }

    func testGetMultipleProfileMetadata() async throws {
        // Given
        let pubkey1 = "pubkey1"
        let pubkey2 = "pubkey2"
        let pubkey3 = "pubkey3"

        try await cache.saveProfileMetadata(
            pubkey: pubkey1,
            metadata: ["name": "User 1"],
            updatedAt: Timestamp.now,
            eventId: "event1"
        )

        try await cache.saveProfileMetadata(
            pubkey: pubkey2,
            metadata: ["name": "User 2"],
            updatedAt: Timestamp.now,
            eventId: "event2"
        )

        // When
        let results = await cache.getMultipleProfileMetadata(pubkeys: [pubkey1, pubkey2, pubkey3])

        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertNotNil(results[pubkey1])
        XCTAssertNotNil(results[pubkey2])
        XCTAssertNil(results[pubkey3])
        if let metadata1 = results[pubkey1]?.metadata {
            XCTAssertEqual(metadata1["name"] as? String, "User 1")
        }
        if let metadata2 = results[pubkey2]?.metadata {
            XCTAssertEqual(metadata2["name"] as? String, "User 2")
        }
    }

    // MARK: - Clear Cache Test

    func testClearCache() async throws {
        // Given
        let event = EventTestFactory.createEvent(kind: 1, content: "To be cleared")
        try await cache.saveEvent(event)
        await cache.storeDecryptedContent("Secret", for: event.id, viewerPubkey: "viewer")

        // When
        try await cache.clear()

        // Then
        let clearCalled = await cache.clearCalled
        XCTAssertTrue(clearCalled)
        let retrievedEvent = await cache.getEvent(id: event.id)
        XCTAssertNil(retrievedEvent)
        let retrievedContent = await cache.getDecryptedContent(for: event.id, viewerPubkey: "viewer")
        XCTAssertNil(retrievedContent)
    }

    // MARK: - Reactive Observation Tests

    func testObserveEventsWithExisting() async throws {
        // Given
        let event1 = EventTestFactory.createEvent(kind: 1, content: "Existing 1")
        let event2 = EventTestFactory.createEvent(kind: 1, content: "Existing 2")
        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)

        // When
        let filter = NDKFilter(kinds: [1])
        let stream = await cache.observeEvents(matching: filter, includeExisting: true)

        // Then
        var receivedEvents: [NDKEvent] = []
        for try await events in stream {
            receivedEvents.append(contentsOf: events)
        }

        XCTAssertEqual(receivedEvents.count, 2)
    }

    func testProcessEventWithRelayTracking() async throws {
        // Given
        let event = EventTestFactory.createEvent(kind: 1, content: "From relay")
        let relay1 = "wss://relay1.com"
        let relay2 = "wss://relay2.com"

        // When
        try await cache.processEvent(event, from: relay1, subscriptionId: "sub1")
        try await cache.processEvent(event, from: relay2, subscriptionId: "sub2")

        // Then
        let sources = await cache.getRelaySources(eventId: event.id)
        XCTAssertEqual(sources.count, 2)
        XCTAssertTrue(sources.contains(relay1))
        XCTAssertTrue(sources.contains(relay2))
    }

    // MARK: - Cache Freshness Tests

    func testRecordAndRetrieveFetchTime() async throws {
        // Given
        let filter = NDKFilter(authors: ["test_author"], kinds: [1])
        let timestamp = Date()

        // When
        await cache.recordFetchTime(for: filter, timestamp: timestamp)
        let retrieved = await cache.getLastFetchTime(for: filter)

        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.timeIntervalSince1970 ?? 0, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - NIP-05 Tests

    func testSaveAndRetrieveNIP05Claim() async throws {
        // Given
        let identifier = "alice@example.com"
        let pubkey = "alice_pubkey"
        let claimedAt = Date()

        // When
        try await cache.saveNIP05Claim(identifier, pubkey: pubkey, retrievedAt: claimedAt)
        let entry = await cache.getNIP05Entry(identifier)

        // Then
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.identifier, identifier)
        XCTAssertEqual(entry?.pubkey, pubkey)
        XCTAssertEqual(entry?.status, .unverified)
    }

    func testSaveNIP05Resolution() async throws {
        // Given
        let entry = NIP05CacheEntry(
            identifier: "bob@example.com",
            pubkey: "bob_pubkey",
            status: .verified,
            nip46Relays: ["wss://relay.example.com"],
            verifiedAt: Date()
        )

        // When
        try await cache.saveNIP05Resolution(entry)
        let retrieved = await cache.getNIP05Entry(entry.identifier)

        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.status, .verified)
        XCTAssertEqual(retrieved?.nip46Relays, ["wss://relay.example.com"])
    }

    func testSearchNIP05() async throws {
        // Given
        try await cache.saveNIP05Claim("alice@example.com", pubkey: "pubkey1", retrievedAt: Date())
        try await cache.saveNIP05Claim("alice@test.com", pubkey: "pubkey2", retrievedAt: Date())
        try await cache.saveNIP05Claim("bob@example.com", pubkey: "pubkey3", retrievedAt: Date())

        // When
        let results = await cache.searchNIP05("alice", limit: 10)

        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.identifier.hasPrefix("alice") })
    }

    func testGetUnverifiedNIP05s() async throws {
        // Given
        try await cache.saveNIP05Claim("unverified1@example.com", pubkey: "pubkey1", retrievedAt: Date())
        try await cache.saveNIP05Claim("unverified2@example.com", pubkey: "pubkey2", retrievedAt: Date())

        let verifiedEntry = NIP05CacheEntry(
            identifier: "verified@example.com",
            pubkey: "pubkey3",
            status: .verified
        )
        try await cache.saveNIP05Resolution(verifiedEntry)

        // When
        let unverified = await cache.getUnverifiedNIP05s(limit: 10)

        // Then
        XCTAssertEqual(unverified.count, 2)
        XCTAssertTrue(unverified.allSatisfy { $0.status == NIP05VerificationStatus.unverified })
    }

    // MARK: - Relay Preferences Tests

    func testSaveAndRetrieveRelayPreferences() async throws {
        // Given
        let pubkey = "test_pubkey"
        let writeRelays = ["wss://write1.com", "wss://write2.com"]
        let readRelays = ["wss://read1.com", "wss://read2.com"]
        let fetchedAt = Date()
        let expiresAt = Date().addingTimeInterval(3600)
        let checkedRelays: Set<String> = ["wss://checked.com"]

        // When
        try await cache.saveRelayPreferences(
            pubkey: pubkey,
            writeRelays: writeRelays,
            readRelays: readRelays,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            checkedRelays: checkedRelays
        )

        let retrieved = await cache.getRelayPreferences(pubkey: pubkey)

        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.writeRelays, writeRelays)
        XCTAssertEqual(retrieved?.readRelays, readRelays)
        XCTAssertEqual(retrieved?.checkedRelays, checkedRelays)
    }

    // MARK: - Negentropy Tests

    func testGetEventsByTimeRange() async throws {
        // Given
        let now = Timestamp.now
        let event1 = EventTestFactory.createEvent(kind: 1, content: "In range", createdAt: now - 500)
        let event2 = EventTestFactory.createEvent(kind: 1, content: "In range 2", createdAt: now - 300)
        let event3 = EventTestFactory.createEvent(kind: 1, content: "Out of range", createdAt: now - 1500)

        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        try await cache.saveEvent(event3)

        // When
        let results = try await cache.getEventsByTimeRange(from: now - 1000, to: now, filter: nil as NDKFilter?)

        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { $0.id == event1.id })
        XCTAssertTrue(results.contains { $0.id == event2.id })
    }

    func testHasEvents() async throws {
        // Given
        let event1 = EventTestFactory.createEvent(kind: 1, content: "Exists")
        let event2 = EventTestFactory.createEvent(kind: 1, content: "Also exists")
        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)

        // When
        let results = await cache.hasEvents(ids: [event1.id, event2.id, "nonexistent_id"])

        // Then
        XCTAssertTrue(results[event1.id] ?? false)
        XCTAssertTrue(results[event2.id] ?? false)
        XCTAssertFalse(results["nonexistent_id"] ?? true)
    }

    // MARK: - Default Implementation Tests

    func testDefaultImplementations() async throws {
        // Test that default implementations work correctly
        let cache = MockNDKCacheProtocol()

        // hasEvent should use getEvent
        let event = EventTestFactory.createEvent(kind: 1, content: "Test")
        try await cache.saveEvent(event)
        let hasEvent1 = await cache.hasEvent(id: event.id)
        XCTAssertTrue(hasEvent1)
        let hasEvent2 = await cache.hasEvent(id: "nonexistent")
        XCTAssertFalse(hasEvent2)

        // saveEvents should call saveEvent multiple times
        let events = [
            EventTestFactory.createEvent(kind: 1, content: "Event 1"),
            EventTestFactory.createEvent(kind: 1, content: "Event 2"),
        ]
        try await cache.saveEvents(events)

        for event in events {
            let retrieved = await cache.getEvent(id: event.id)
            XCTAssertNotNil(retrieved)
        }

        // queryEvents by author convenience method
        let authorEvents = try await cache.queryEvents(author: "test_author", kinds: [1], limit: 10)
        XCTAssertTrue(authorEvents.isEmpty) // No events with that author

        // queryEvents by kind convenience method
        let kindEvents = try await cache.queryEvents(kind: 1, limit: 10)
        XCTAssertGreaterThanOrEqual(kindEvents.count, 3) // At least the 3 events we saved
    }
}
