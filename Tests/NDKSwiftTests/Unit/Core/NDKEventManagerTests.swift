import XCTest
@testable import NDKSwift

final class NDKEventManagerTests: NDKTestCase {
    
    var eventManager: NDKEventManager!
    var mockCache: MemoryCache!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockCache = MemoryCache()
        eventManager = NDKEventManager(cache: mockCache)
    }
    
    override func tearDown() async throws {
        eventManager = nil
        mockCache = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Event Processing Tests
    
    func testProcessNewEvent() async throws {
        let event = EventTestFactory.createEvent()
        
        let processed = await eventManager.processEvent(event)
        
        XCTAssertTrue(processed)
        
        // Event should be in cache
        let cachedEvent = await mockCache.getEvent(event.id)
        XCTAssertNotNil(cachedEvent)
        XCTAssertEventEqual(event, cachedEvent!)
    }
    
    func testProcessDuplicateEvent() async throws {
        let event = EventTestFactory.createEvent()
        
        // Process once
        let firstProcess = await eventManager.processEvent(event)
        XCTAssertTrue(firstProcess)
        
        // Process again
        let secondProcess = await eventManager.processEvent(event)
        XCTAssertFalse(secondProcess) // Should not process duplicate
    }
    
    func testProcessEventWithNewerTimestamp() async throws {
        let oldEvent = EventTestFactory.createEvent(
            id: "event1",
            createdAt: 1000
        )
        
        let newEvent = EventTestFactory.createEvent(
            id: "event1", // Same ID
            createdAt: 2000 // Newer timestamp
        )
        
        // Process old event first
        _ = await eventManager.processEvent(oldEvent)
        
        // Try to process newer event with same ID
        let processed = await eventManager.processEvent(newEvent)
        XCTAssertFalse(processed) // Should reject based on ID, not timestamp
        
        // Old event should still be in cache
        let cachedEvent = await mockCache.getEvent("event1")
        XCTAssertEqual(cachedEvent?.createdAt, 1000)
    }
    
    // MARK: - Deletion Event Processing Tests
    
    func testProcessDeletionEvent() async throws {
        let author = TestFixtures.Keys.alice.publicKey
        
        // Create events to be deleted
        let event1 = EventTestFactory.createEvent(id: "event1", pubkey: author)
        let event2 = EventTestFactory.createEvent(id: "event2", pubkey: author)
        let event3 = EventTestFactory.createEvent(id: "event3", pubkey: TestFixtures.Keys.bob.publicKey)
        
        // Save events to cache
        try await mockCache.saveEvent(event1)
        try await mockCache.saveEvent(event2)
        try await mockCache.saveEvent(event3)
        
        // Create deletion event
        let deletionEvent = EventTestFactory.createDeletionEvent(
            eventIds: ["event1", "event2", "event3"],
            pubkey: author
        )
        
        // Process deletion
        let processed = await eventManager.processEvent(deletionEvent)
        XCTAssertTrue(processed)
        
        // Check that only author's events were deleted
        await XCTAssertEventNotInCache(eventId: "event1", cache: mockCache)
        await XCTAssertEventNotInCache(eventId: "event2", cache: mockCache)
        await XCTAssertEventInCache(event3, cache: mockCache) // Should not be deleted (different author)
    }
    
    func testProcessDeletionEventWithoutPermission() async throws {
        let originalAuthor = TestFixtures.Keys.alice.publicKey
        let deletionAuthor = TestFixtures.Keys.bob.publicKey
        
        // Create event by Alice
        let event = EventTestFactory.createEvent(
            id: "event1",
            pubkey: originalAuthor
        )
        try await mockCache.saveEvent(event)
        
        // Bob tries to delete Alice's event
        let deletionEvent = EventTestFactory.createDeletionEvent(
            eventIds: ["event1"],
            pubkey: deletionAuthor
        )
        
        // Process deletion
        let processed = await eventManager.processEvent(deletionEvent)
        XCTAssertTrue(processed) // Deletion event itself is processed
        
        // But original event should NOT be deleted
        await XCTAssertEventInCache(event, cache: mockCache)
    }
    
    // MARK: - Replaceable Event Tests
    
    func testProcessReplaceableEvent() async throws {
        let author = TestFixtures.Keys.alice.publicKey
        
        // Create old replaceable event (kind 0 - metadata)
        let oldEvent = EventTestFactory.createMetadataEvent(
            name: "Old Name",
            pubkey: author
        )
        oldEvent.createdAt = 1000
        
        _ = await eventManager.processEvent(oldEvent)
        
        // Create newer replaceable event
        let newEvent = EventTestFactory.createMetadataEvent(
            name: "New Name",
            pubkey: author
        )
        newEvent.createdAt = 2000
        
        _ = await eventManager.processEvent(newEvent)
        
        // Only newer event should be in cache
        let events = await mockCache.getEvents(
            filter: NDKFilter(authors: [author], kinds: [0])
        )
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.content.contains("New Name"), true)
    }
    
    func testProcessOlderReplaceableEvent() async throws {
        let author = TestFixtures.Keys.alice.publicKey
        
        // Create newer event first
        let newEvent = EventTestFactory.createMetadataEvent(
            name: "New Name",
            pubkey: author
        )
        newEvent.createdAt = 2000
        
        _ = await eventManager.processEvent(newEvent)
        
        // Try to process older event
        let oldEvent = EventTestFactory.createMetadataEvent(
            name: "Old Name",
            pubkey: author
        )
        oldEvent.createdAt = 1000
        
        let processed = await eventManager.processEvent(oldEvent)
        XCTAssertTrue(processed) // Should still be processed
        
        // But newer event should remain in cache
        let events = await mockCache.getEvents(
            filter: NDKFilter(authors: [author], kinds: [0])
        )
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.createdAt, 2000)
    }
    
    // MARK: - Parameterized Replaceable Event Tests
    
    func testProcessParameterizedReplaceableEvent() async throws {
        let author = TestFixtures.Keys.alice.publicKey
        let dTag = "test-article"
        
        // Create old article
        let oldArticle = EventTestFactory.createEvent(
            kind: 30023, // Long-form content
            content: "Old article content",
            tags: [Tag(name: NostrConstants.TagName.d, value: dTag)],
            pubkey: author,
            createdAt: 1000
        )
        
        _ = await eventManager.processEvent(oldArticle)
        
        // Create newer version
        let newArticle = EventTestFactory.createEvent(
            kind: 30023,
            content: "New article content",
            tags: [Tag(name: NostrConstants.TagName.d, value: dTag)],
            pubkey: author,
            createdAt: 2000
        )
        
        _ = await eventManager.processEvent(newArticle)
        
        // Only newer version should exist
        let events = await mockCache.getEvents(
            filter: NDKFilter(
                authors: [author],
                kinds: [30023],
                tags: [NostrConstants.TagName.d: [dTag]]
            )
        )
        
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.content, "New article content")
    }
    
    // MARK: - Ephemeral Event Tests
    
    func testProcessEphemeralEvent() async throws {
        // Create ephemeral event (kind 20000-29999)
        let ephemeralEvent = EventTestFactory.createEvent(
            kind: 20001, // Ephemeral
            content: "Ephemeral content"
        )
        
        let processed = await eventManager.processEvent(ephemeralEvent)
        XCTAssertTrue(processed)
        
        // Should NOT be in cache
        await XCTAssertEventNotInCache(eventId: ephemeralEvent.id, cache: mockCache)
    }
    
    // MARK: - Batch Processing Tests
    
    func testBatchProcessEvents() async throws {
        let events = (0..<100).map { index in
            EventTestFactory.createEvent(
                content: "Batch event \(index)",
                createdAt: Timestamp(1000 + index)
            )
        }
        
        // Process all events
        var processedCount = 0
        for event in events {
            if await eventManager.processEvent(event) {
                processedCount += 1
            }
        }
        
        XCTAssertEqual(processedCount, 100)
        
        // All should be in cache
        let cachedEvents = await mockCache.getEvents(filter: NDKFilter())
        XCTAssertEqual(cachedEvents.count, 100)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentEventProcessing() async throws {
        let eventCount = 100
        let events = (0..<eventCount).map { index in
            EventTestFactory.createEvent(
                id: "concurrent_\(index)",
                content: "Concurrent event \(index)"
            )
        }
        
        // Process events concurrently
        await withTaskGroup(of: Bool.self) { group in
            for event in events {
                group.addTask {
                    await self.eventManager.processEvent(event)
                }
            }
        }
        
        // All unique events should be in cache
        let cachedEvents = await mockCache.getEvents(filter: NDKFilter())
        XCTAssertEqual(cachedEvents.count, eventCount)
    }
    
    func testConcurrentDuplicateProcessing() async throws {
        let event = EventTestFactory.createEvent()
        let concurrentAttempts = 10
        
        // Try to process the same event multiple times concurrently
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<concurrentAttempts {
                group.addTask {
                    await self.eventManager.processEvent(event)
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // Only one should succeed
        let successCount = results.filter { $0 }.count
        XCTAssertEqual(successCount, 1)
        
        // Event should be in cache once
        let cachedEvents = await mockCache.getEvents(filter: NDKFilter(ids: [event.id]))
        XCTAssertEqual(cachedEvents.count, 1)
    }
    
    // MARK: - Performance Tests
    
    func testEventProcessingPerformance() {
        let events = createLargeEventSet(count: 1000)
        
        measureAsyncPerformance {
            for event in events {
                _ = await self.eventManager.processEvent(event)
            }
        }
    }
}