import XCTest
@testable import NDKSwift

final class NDKFileCacheTests: XCTestCase {
    var cache: NDKFileCache!
    
    override func setUp() async throws {
        try await super.setUp()
        // Use a unique cache directory for each test
        let cachePath = "test-\(UUID().uuidString)"
        cache = try NDKFileCache(path: cachePath)
    }
    
    override func tearDown() async throws {
        // Clear the cache after each test
        await cache.clear()
        try await super.tearDown()
    }
    
    func testEventCaching() async throws {
        // Create a test event
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Test event content"
        )
        event.id = "test_event_id"
        
        // Cache the event
        await cache.setEvent(event, filters: [], relay: nil)
        
        // Query the event
        let filter = NDKFilter(ids: ["test_event_id"])
        let subscription = NDKSubscription(filters: [filter])
        
        let results = await cache.query(subscription: subscription)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, event.id)
        XCTAssertEqual(results.first?.content, event.content)
    }
    
    func testProfileCaching() async throws {
        let pubkey = "test_profile_pubkey"
        let profile = NDKUserProfile(
            name: "testuser",
            displayName: "Test User",
            about: "Test profile",
            picture: "https://example.com/pic.jpg"
        )
        
        // Save profile
        await cache.saveProfile(pubkey: pubkey, profile: profile)
        
        // Fetch profile
        let fetchedProfile = await cache.fetchProfile(pubkey: pubkey)
        
        XCTAssertNotNil(fetchedProfile)
        XCTAssertEqual(fetchedProfile?.name, profile.name)
        XCTAssertEqual(fetchedProfile?.displayName, profile.displayName)
        XCTAssertEqual(fetchedProfile?.about, profile.about)
        XCTAssertEqual(fetchedProfile?.picture, profile.picture)
    }
    
    func testQueryByAuthor() async throws {
        let author = "author_pubkey"
        
        // Create multiple events from the same author
        for i in 0..<5 {
            let event = NDKEvent(
                pubkey: author,
                createdAt: Timestamp(Date().timeIntervalSince1970 - Double(i)),
                kind: EventKind.textNote,
                content: "Event #\(i)"
            )
            event.id = "event_\(i)"
            await cache.setEvent(event, filters: [], relay: nil)
        }
        
        // Create events from different author
        let otherEvent = NDKEvent(
            pubkey: "other_author",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Other author event"
        )
        otherEvent.id = "other_event"
        await cache.setEvent(otherEvent, filters: [], relay: nil)
        
        // Query by author
        let filter = NDKFilter(authors: [author])
        let subscription = NDKSubscription(filters: [filter])
        
        let results = await cache.query(subscription: subscription)
        
        XCTAssertEqual(results.count, 5)
        XCTAssertTrue(results.allSatisfy { $0.pubkey == author })
    }
    
    func testQueryByKind() async throws {
        // Create events of different kinds
        let textNote = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Text note"
        )
        textNote.id = "text_note"
        
        let reaction = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.reaction,
            content: "+"
        )
        reaction.id = "reaction"
        
        let metadata = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: "{\"name\":\"test\"}"
        )
        metadata.id = "metadata"
        
        await cache.setEvent(textNote, filters: [], relay: nil)
        await cache.setEvent(reaction, filters: [], relay: nil)
        await cache.setEvent(metadata, filters: [], relay: nil)
        
        // Query text notes only
        let filter = NDKFilter(kinds: [EventKind.textNote])
        let subscription = NDKSubscription(filters: [filter])
        
        let results = await cache.query(subscription: subscription)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, EventKind.textNote)
    }
    
    func testQueryByTimeRange() async throws {
        let now = Date().timeIntervalSince1970
        
        // Create events at different times
        let oldEvent = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(now - 7200), // 2 hours ago
            kind: EventKind.textNote,
            content: "Old event"
        )
        oldEvent.id = "old_event"
        
        let recentEvent = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(now - 1800), // 30 minutes ago
            kind: EventKind.textNote,
            content: "Recent event"
        )
        recentEvent.id = "recent_event"
        
        await cache.setEvent(oldEvent, filters: [], relay: nil)
        await cache.setEvent(recentEvent, filters: [], relay: nil)
        
        // Query events from last hour
        let oneHourAgo = Timestamp(now - 3600)
        let filter = NDKFilter(since: oneHourAgo)
        let subscription = NDKSubscription(filters: [filter])
        
        let results = await cache.query(subscription: subscription)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "recent_event")
    }
    
    func testQueryByTags() async throws {
        // Create events with tags
        let event1 = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Event with tag"
        )
        event1.id = "event1"
        event1.addTag(["t", "nostr"])
        event1.addTag(["t", "test"])
        
        let event2 = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Another event"
        )
        event2.id = "event2"
        event2.addTag(["t", "bitcoin"])
        
        await cache.setEvent(event1, filters: [], relay: nil)
        await cache.setEvent(event2, filters: [], relay: nil)
        
        // Query by tag
        let filter = NDKFilter(tags: ["t": Set(["nostr"])])
        let subscription = NDKSubscription(filters: [filter])
        
        let results = await cache.query(subscription: subscription)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "event1")
    }
    
    func testReplaceableEvents() async throws {
        let pubkey = "replaceable_test_pubkey"
        
        // Create first metadata event
        let metadata1 = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970 - 1000),
            kind: EventKind.metadata,
            content: "{\"name\":\"oldname\"}"
        )
        metadata1.id = "metadata1"
        
        await cache.setEvent(metadata1, filters: [], relay: nil)
        
        // Create newer metadata event
        let metadata2 = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.metadata,
            content: "{\"name\":\"newname\"}"
        )
        metadata2.id = "metadata2"
        
        await cache.setEvent(metadata2, filters: [], relay: nil)
        
        // Query metadata events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.metadata]
        )
        let subscription = NDKSubscription(filters: [filter])
        
        let results = await cache.query(subscription: subscription)
        
        // Should only have the newer event
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "metadata2")
        XCTAssertEqual(results.first?.content, "{\"name\":\"newname\"}")
    }
    
    func testUnpublishedEvents() async throws {
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Unpublished event"
        )
        event.id = "unpublished_event"
        
        let relays = ["wss://relay1.com", "wss://relay2.com"]
        
        // Add unpublished event
        await cache.addUnpublishedEvent(event, relayUrls: relays)
        
        // Get unpublished events
        let unpublished = await cache.getUnpublishedEvents()
        
        XCTAssertEqual(unpublished.count, 1)
        XCTAssertEqual(unpublished.first?.event.id, event.id)
        XCTAssertEqual(unpublished.first?.relays.sorted(), relays.sorted())
        
        // Discard unpublished event
        if let eventId = event.id {
            await cache.discardUnpublishedEvent(eventId)
        }
        
        let remainingUnpublished = await cache.getUnpublishedEvents()
        XCTAssertEqual(remainingUnpublished.count, 0)
    }
    
    func testDecryptedEvents() async throws {
        let encryptedEvent = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.encryptedDirectMessage,
            content: "encrypted_content"
        )
        encryptedEvent.id = "encrypted_event"
        
        // Store encrypted event
        await cache.setEvent(encryptedEvent, filters: [], relay: nil)
        
        // Store decrypted version
        let decryptedEvent = NDKEvent(
            pubkey: encryptedEvent.pubkey,
            createdAt: encryptedEvent.createdAt,
            kind: encryptedEvent.kind,
            content: "Decrypted message content"
        )
        decryptedEvent.id = encryptedEvent.id
        
        await cache.addDecryptedEvent(decryptedEvent)
        
        // Retrieve decrypted event
        if let eventId = encryptedEvent.id {
            let retrieved = await cache.getDecryptedEvent(eventId: eventId)
            
            XCTAssertNotNil(retrieved)
            XCTAssertEqual(retrieved?.content, "Decrypted message content")
        } else {
            XCTFail("Encrypted event should have an ID")
        }
    }
    
    func testClearCache() async throws {
        // Add some data
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            content: "Test event"
        )
        event.id = "test_event"
        
        await cache.setEvent(event, filters: [], relay: nil)
        
        let profile = NDKUserProfile(name: "test")
        await cache.saveProfile(pubkey: "test_pubkey", profile: profile)
        
        // Clear cache
        await cache.clear()
        
        // Verify data is gone
        let filter = NDKFilter()
        let subscription = NDKSubscription(filters: [filter])
        let events = await cache.query(subscription: subscription)
        
        XCTAssertEqual(events.count, 0)
        
        let fetchedProfile = await cache.fetchProfile(pubkey: "test_pubkey")
        XCTAssertNil(fetchedProfile)
    }
    
    func testPerformance() async throws {
        // Create many events
        let eventCount = 100
        
        let startTime = Date()
        
        for i in 0..<eventCount {
            let event = NDKEvent(
                pubkey: "perf_test_pubkey",
                createdAt: Timestamp(Date().timeIntervalSince1970 - Double(i)),
                kind: EventKind.textNote,
                content: "Performance test event #\(i)"
            )
            event.id = "perf_\(i)"
            event.addTag(["t", "performance"])
            
            await cache.setEvent(event, filters: [], relay: nil)
        }
        
        let insertTime = Date().timeIntervalSince(startTime)
        print("Inserted \(eventCount) events in \(insertTime) seconds")
        
        // Query performance
        let queryStart = Date()
        
        let filter = NDKFilter(
            authors: ["perf_test_pubkey"],
            kinds: [EventKind.textNote]
        )
        let subscription = NDKSubscription(filters: [filter])
        
        let results = await cache.query(subscription: subscription)
        
        let queryTime = Date().timeIntervalSince(queryStart)
        print("Queried \(results.count) events in \(queryTime) seconds")
        
        XCTAssertEqual(results.count, eventCount)
        XCTAssertLessThan(insertTime, 2.0) // Should insert 100 events in less than 2 seconds
        XCTAssertLessThan(queryTime, 0.2) // Should query in less than 0.2 seconds
    }
}