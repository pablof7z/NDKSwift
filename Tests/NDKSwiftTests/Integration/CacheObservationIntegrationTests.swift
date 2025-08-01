import XCTest
import GRDB
@testable import NDKSwift

/// Integration tests for the new AsyncThrowingStream-based cache observation
/// Tests the GRDB reactive implementation and cross-fingerprint event delivery
final class CacheObservationIntegrationTests: XCTestCase {
    var sqliteCache: NDKSQLiteCache!
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create SQLite cache with debug mode - unique path for each test
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-obs-test-\(UUID().uuidString).db").path
        sqliteCache = try await NDKSQLiteCache(path: tempPath, debugMode: true)
        
        // Create NDK with real cache
        ndk = NDK(cache: sqliteCache)
    }
    
    override func tearDown() async throws {
        // Clear the cache
        if let sqliteCache = sqliteCache {
            try await sqliteCache.clear()
        }
        
        self.sqliteCache = nil
        self.ndk = nil
        try await super.tearDown()
    }
    
    // MARK: - AsyncThrowingStream Tests
    
    func testAsyncThrowingStream_BasicObservation() async throws {
        // Test basic event observation with AsyncThrowingStream
        let filter = NDKFilter(kinds: [1])
        
        // Create the event before starting observation
        let event = createEvent(kind: 1, content: "Test event")
        
        let eventStream = await sqliteCache.observeEvents(
            matching: filter,
            includeExisting: false
        )
        
        var receivedBatches: [[NDKEvent]] = []
        let expectation = XCTestExpectation(description: "Receive event batch")
        
        let observerTask = Task {
            do {
                for try await batch in eventStream {
                    receivedBatches.append(batch)
                    expectation.fulfill()
                    break // Exit after first batch
                }
            } catch {
                if !Task.isCancelled {
                    XCTFail("Stream error: \(error)")
                }
            }
        }
        
        // Use longer setup time and add verification that observation is active
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms for more reliable setup
        
        // Save the event after the stream is set up
        try await sqliteCache.saveEvent(event)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // Cleanup
        observerTask.cancel()
        
        // Verify results
        XCTAssertEqual(receivedBatches.count, 1, "Should receive exactly one batch")
        XCTAssertEqual(receivedBatches.first?.count, 1, "Batch should contain exactly one event")
        XCTAssertEqual(receivedBatches.first?.first?.id, event.id, "Should receive the correct event")
    }
    
    func testAsyncThrowingStream_IncludeExistingFlag() async throws {
        // Test includeExisting parameter behavior
        
        // Pre-save some events
        let existingEvents = [
            createEvent(kind: 1, content: "Existing 1"),
            createEvent(kind: 1, content: "Existing 2"),
            createEvent(kind: 1, content: "Existing 3")
        ]
        
        for event in existingEvents {
            try await sqliteCache.saveEvent(event)
        }
        
        // Test with includeExisting = true
        let streamWithExisting = await sqliteCache.observeEvents(
            matching: NDKFilter(kinds: [1]),
            includeExisting: true
        )
        
        var eventsWithExisting: [NDKEvent] = []
        let expectationWithExisting = XCTestExpectation(description: "Get existing events")
        
        Task {
            do {
                for try await batch in streamWithExisting {
                    eventsWithExisting.append(contentsOf: batch)
                    expectationWithExisting.fulfill()
                    break // Exit after first batch
                }
            } catch {
                XCTFail("Stream error: \(error)")
            }
        }
        
        await fulfillment(of: [expectationWithExisting], timeout: 1.0)
        
        // When includeExisting is true, we should get existing events immediately
        XCTAssertEqual(eventsWithExisting.count, 3)
        
        // Verify we got the existing events by checking their content
        let eventContents = eventsWithExisting.map { $0.content }.sorted()
        XCTAssertEqual(eventContents, ["Existing 1", "Existing 2", "Existing 3"])
        
        // Test with includeExisting = false
        let streamWithoutExisting = await sqliteCache.observeEvents(
            matching: NDKFilter(kinds: [1]),
            includeExisting: false
        )
        
        var eventsWithoutExisting: [NDKEvent] = []
        let expectationWithoutExisting = XCTestExpectation(description: "Only new events")
        
        // Create the new event before starting the observer task
        let newEvent = createEvent(kind: 1, content: "New event")
        
        let observerTaskWithoutExisting = Task {
            do {
                for try await batch in streamWithoutExisting {
                    eventsWithoutExisting.append(contentsOf: batch)
                    expectationWithoutExisting.fulfill()
                    break
                }
            } catch {
                if !Task.isCancelled {
                    XCTFail("Stream error: \(error)")
                }
            }
        }
        
        // Give the stream sufficient time to set up GRDB observation
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms for better reliability
        
        // Save the new event after the stream is set up
        try await sqliteCache.saveEvent(newEvent)
        
        await fulfillment(of: [expectationWithoutExisting], timeout: 2.0)
        
        // Cleanup
        observerTaskWithoutExisting.cancel()
        
        // Verify results
        XCTAssertEqual(eventsWithoutExisting.count, 1, "Should receive exactly one new event")
        XCTAssertEqual(eventsWithoutExisting.first?.id, newEvent.id, "Should receive the correct new event")
        XCTAssertEqual(eventsWithoutExisting.first?.content, "New event", "Event content should match")
    }
    
    // MARK: - GRDB Reactive Tests
    
    func testGRDBReactive_MultipleObservers() async throws {
        // Test multiple concurrent observers with different filters
        
        // Use unique authors per test to avoid cross-test contamination
        let testId = String(UUID().uuidString.prefix(8))
        let author1 = "test-author1-\(testId)"
        let author2 = "test-author2-\(testId)"
        
        let filter1 = NDKFilter(authors: [author1], kinds: [1])
        let filter2 = NDKFilter(authors: [author2], kinds: [1])
        let filterAll = NDKFilter(authors: [author1, author2], kinds: [1]) // Restrict to our test authors
        
        let stream1 = await sqliteCache.observeEvents(matching: filter1, includeExisting: false)
        let stream2 = await sqliteCache.observeEvents(matching: filter2, includeExisting: false)
        let streamAll = await sqliteCache.observeEvents(matching: filterAll, includeExisting: false)
        
        var events1: [NDKEvent] = []
        var events2: [NDKEvent] = []
        var eventsAll: [NDKEvent] = []
        
        let exp1 = XCTestExpectation(description: "Observer 1")
        let exp2 = XCTestExpectation(description: "Observer 2")
        let expAll = XCTestExpectation(description: "Observer All")
        expAll.expectedFulfillmentCount = 2
        
        // Start observers with proper task tracking
        let task1 = Task {
            do {
                for try await batch in stream1 {
                    events1.append(contentsOf: batch)
                    exp1.fulfill()
                    break // Exit after first batch
                }
            } catch {
                if !Task.isCancelled {
                    print("Observer 1 error: \(error)")
                }
            }
        }
        
        let task2 = Task {
            do {
                for try await batch in stream2 {
                    events2.append(contentsOf: batch)
                    exp2.fulfill()
                    break // Exit after first batch
                }
            } catch {
                if !Task.isCancelled {
                    print("Observer 2 error: \(error)")
                }
            }
        }
        
        let taskAll = Task {
            do {
                var batchCount = 0
                for try await batch in streamAll {
                    eventsAll.append(contentsOf: batch)
                    batchCount += 1
                    expAll.fulfill()
                    
                    // Give some extra time for any additional batches to arrive
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    
                    if batchCount >= 2 || eventsAll.count >= 2 {
                        break // Exit after receiving both events or two batches
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("Observer All error: \(error)")
                }
            }
        }
        
        // Give observers more time to set up properly
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Save events
        let event1 = createEvent(author: author1, kind: 1, content: "Author 1 event")
        let event2 = createEvent(author: author2, kind: 1, content: "Author 2 event")
        
        try await sqliteCache.saveEvent(event1)
        try await sqliteCache.saveEvent(event2)
        
        await fulfillment(of: [exp1, exp2, expAll], timeout: 3.0)
        
        // Cleanup all tasks
        task1.cancel()
        task2.cancel()
        taskAll.cancel()
        
        // Verify each observer received correct events
        XCTAssertEqual(events1.count, 1, "Observer 1 should receive one event")
        XCTAssertEqual(events1.first?.pubkey, author1, "Observer 1 should receive author1's event")
        
        XCTAssertEqual(events2.count, 1, "Observer 2 should receive one event")  
        XCTAssertEqual(events2.first?.pubkey, author2, "Observer 2 should receive author2's event")
        
        // Observer All should receive at least both events (may receive duplicates due to GRDB batching)
        XCTAssertGreaterThanOrEqual(eventsAll.count, 2, "Observer All should receive at least both events")
        
        // Verify we got events from both authors (deduplicate by ID to handle potential duplicates)
        let uniqueEvents = Array(Set(eventsAll.map { $0.id }))
        XCTAssertGreaterThanOrEqual(uniqueEvents.count, 2, "Should have at least 2 unique events")
        
        let allAuthors = Set(eventsAll.map { $0.pubkey })
        XCTAssertEqual(allAuthors.count, 2, "Should have events from both authors")
        XCTAssertTrue(allAuthors.contains(author1), "Should contain author1's event")
        XCTAssertTrue(allAuthors.contains(author2), "Should contain author2's event")
    }
    
    func testGRDBReactive_BatchedUpdates() async throws {
        // Test that GRDB batches updates efficiently
        let filter = NDKFilter(kinds: [1])
        let stream = await sqliteCache.observeEvents(matching: filter, includeExisting: false)
        
        var batches: [[NDKEvent]] = []
        let expectation = XCTestExpectation(description: "Receive batches")
        expectation.expectedFulfillmentCount = 2 // Expect 2 batches
        
        Task {
            do {
                for try await batch in stream {
                    batches.append(batch)
                    expectation.fulfill()
                    if batches.count >= 2 {
                        break
                    }
                }
            } catch {}
        }
        
        // Save multiple events in quick succession
        let events1 = (0..<5).map { i in
            createEvent(kind: 1, content: "Batch 1 Event \(i)")
        }
        
        // Save as a batch (should trigger one GRDB notification)
        for event in events1 {
            try await sqliteCache.saveEvent(event)
        }
        
        // Small delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Save another batch
        let events2 = (0..<3).map { i in
            createEvent(kind: 1, content: "Batch 2 Event \(i)")
        }
        
        for event in events2 {
            try await sqliteCache.saveEvent(event)
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // Should receive events in batches
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0].count, 5)
        XCTAssertEqual(batches[1].count, 3)
    }
    
    // MARK: - Cross-Fingerprint Delivery Tests
    
    func testCrossFingerprintDelivery_BroadVsSpecific() async throws {
        // Test that broad filters receive events from specific filters
        let specificAuthor = "specific-author"
        
        // Create broad cache-only subscription
        let broadFilter = NDKFilter(kinds: [1])
        let broadDataSource = ndk.subscribe(
            filter: broadFilter,
            cachePolicy: .cacheOnly
        )
        
        // Create specific network subscription
        let specificFilter = NDKFilter(
            authors: [specificAuthor],
            kinds: [1],
            limit: 10
        )
        _ = ndk.subscribe(
            filter: specificFilter,
            cachePolicy: .networkOnly
        )
        
        var broadEvents: [NDKEvent] = []
        let broadExpectation = XCTestExpectation(description: "Broad filter receives event")
        
        Task {
            for await event in broadDataSource.events {
                broadEvents.append(event)
                broadExpectation.fulfill()
                break
            }
        }
        
        // Simulate network event matching specific filter
        let networkEvent = createEvent(
            author: specificAuthor,
            kind: 1,
            content: "Network event"
        )
        
        // Save to cache (simulating network arrival)
        try await sqliteCache.saveEvent(networkEvent)
        
        await fulfillment(of: [broadExpectation], timeout: 1.0)
        
        // Broad filter should receive the event
        XCTAssertEqual(broadEvents.count, 1)
        XCTAssertEqual(broadEvents.first?.id, networkEvent.id)
    }
    
    func testCrossFingerprintDelivery_ComplexScenario() async throws {
        // Test complex scenario with multiple subscriptions
        let author1 = "author1"
        let author2 = "author2"
        
        // Multiple cache observers with different filters
        let filters = [
            NDKFilter(kinds: [1]), // All kind:1
            NDKFilter(authors: [author1], kinds: [1]), // Author1 kind:1
            NDKFilter(authors: [author2], kinds: [1]), // Author2 kind:1
            NDKFilter(authors: [author1, author2], kinds: [1]) // Both authors
        ]
        
        var receivedEvents: [[String: [NDKEvent]]] = Array(repeating: [:], count: filters.count)
        let expectations = filters.map { _ in
            XCTestExpectation(description: "Filter receives events")
        }
        
        // Start observers
        for (index, filter) in filters.enumerated() {
            let dataSource = ndk.subscribe(filter: filter, cachePolicy: .cacheOnly)
            
            Task {
                for await event in dataSource.events {
                    if receivedEvents[index][event.id] == nil {
                        receivedEvents[index][event.id] = []
                    }
                    receivedEvents[index][event.id]?.append(event)
                    
                    // Fulfill after receiving expected number of events
                    let totalEvents = receivedEvents[index].values.flatMap { $0 }.count
                    if (index == 0 || index == 3) && totalEvents >= 2 {
                        expectations[index].fulfill()
                    } else if totalEvents >= 1 {
                        expectations[index].fulfill()
                    }
                }
            }
        }
        
        // Give observers time to start
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Save events from different sources
        let event1 = createEvent(author: author1, kind: 1, content: "From author1")
        let event2 = createEvent(author: author2, kind: 1, content: "From author2")
        
        try await sqliteCache.saveEvent(event1)
        try await sqliteCache.saveEvent(event2)
        
        await fulfillment(of: expectations, timeout: 2.0)
        
        // Verify each filter received appropriate events
        // Filter 0 (all kind:1) should receive both
        XCTAssertEqual(receivedEvents[0].count, 2)
        
        // Filter 1 (author1 only) should receive event1
        XCTAssertEqual(receivedEvents[1].count, 1)
        XCTAssertNotNil(receivedEvents[1][event1.id])
        
        // Filter 2 (author2 only) should receive event2
        XCTAssertEqual(receivedEvents[2].count, 1)
        XCTAssertNotNil(receivedEvents[2][event2.id])
        
        // Filter 3 (both authors) should receive both
        XCTAssertEqual(receivedEvents[3].count, 2)
    }
    
    // MARK: - Performance Tests
    
    func testCacheObservation_HighVolume() async throws {
        // Test cache observation with high volume of events
        let eventCount = 1000
        let observerCount = 10
        
        // Create multiple observers
        var observers: [Task<Int, Error>] = []
        
        for i in 0..<observerCount {
            let filter = NDKFilter(
                authors: ["observer\(i)"],
                kinds: [1]
            )
            
            let task = Task<Int, Error> {
                let stream = await sqliteCache.observeEvents(
                    matching: filter,
                    includeExisting: false
                )
                
                var count = 0
                for try await batch in stream {
                    count += batch.count
                    if count >= eventCount / observerCount {
                        break
                    }
                }
                return count
            }
            
            observers.append(task)
        }
        
        // Save many events
        let startTime = Date()
        
        for i in 0..<eventCount {
            let observerIndex = i % observerCount
            let event = createEvent(
                author: "observer\(observerIndex)",
                kind: 1,
                content: "Event \(i)"
            )
            try await sqliteCache.saveEvent(event)
        }
        
        // Wait for all observers
        var totalReceived = 0
        for observer in observers {
            let count = try await observer.value
            totalReceived += count
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Verify performance
        XCTAssertEqual(totalReceived, eventCount)
        XCTAssertLessThan(duration, 5.0) // Should handle 1000 events in < 5 seconds
        
        print("Processed \(eventCount) events across \(observerCount) observers in \(duration) seconds")
    }
    
    // MARK: - Edge Case Tests
    
    func testCacheObservation_StreamCancellation() async throws {
        // Test proper cleanup when streams are cancelled
        let filter = NDKFilter(kinds: [1])
        
        // Start an observation
        let stream = await sqliteCache.observeEvents(matching: filter, includeExisting: false)
        
        let observationTask = Task {
            do {
                for try await _ in stream {
                    // Just consume events
                }
            } catch {
                // Expected cancellation
            }
        }
        
        // Cancel after a short delay
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        observationTask.cancel()
        
        // Verify no crash and proper cleanup
        // Save an event after cancellation
        let event = createEvent(kind: 1, content: "After cancel")
        try await sqliteCache.saveEvent(event)
        
        // Give time for any pending operations
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Test passed if no crash
        XCTAssertTrue(true)
    }
    
    func testCacheObservation_ConcurrentModification() async throws {
        // Test cache observation during concurrent modifications
        let filter = NDKFilter(kinds: [1])
        let stream = await sqliteCache.observeEvents(matching: filter, includeExisting: false)
        
        var receivedEvents: Set<String> = []
        let expectation = XCTestExpectation(description: "Receive all events")
        
        Task {
            do {
                for try await batch in stream {
                    for event in batch {
                        receivedEvents.insert(event.id)
                    }
                    if receivedEvents.count >= 50 {
                        expectation.fulfill()
                        break
                    }
                }
            } catch {}
        }
        
        // Concurrent saves from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    for j in 0..<5 {
                        let event = self.createEvent(
                            kind: 1,
                            content: "Task \(i) Event \(j)"
                        )
                        try? await self.sqliteCache.saveEvent(event)
                    }
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Should receive all events despite concurrent saves
        XCTAssertEqual(receivedEvents.count, 50)
    }
    
    // MARK: - Helper Methods
    
    private func createEvent(
        id: String? = nil,
        author: String = "test-author",
        kind: UInt32 = 1,
        content: String
    ) -> NDKEvent {
        return EventTestFactory.createEvent(
            kind: Int(kind),
            content: content,
            tags: [],
            pubkey: author,
            createdAt: Timestamp.now,
            id: id
        )
    }
}