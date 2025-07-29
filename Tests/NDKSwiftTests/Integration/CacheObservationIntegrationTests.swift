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
        
        // Create SQLite cache with debug mode
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).db").path
        sqliteCache = try await NDKSQLiteCache(path: tempPath, debugMode: true)
        
        // Create NDK with real cache
        ndk = NDK(cache: sqliteCache)
    }
    
    override func tearDown() async throws {
        try await sqliteCache.clear()
        ndk = nil
        try await super.tearDown()
    }
    
    // MARK: - AsyncThrowingStream Tests
    
    func testAsyncThrowingStream_BasicObservation() async throws {
        // Test basic event observation with AsyncThrowingStream
        let filter = NDKFilter(kinds: [1])
        let eventStream = await sqliteCache.observeEvents(
            matching: filter,
            includeExisting: true
        )
        
        var receivedBatches: [[NDKEvent]] = []
        let expectation = XCTestExpectation(description: "Receive event batch")
        
        Task {
            do {
                for try await batch in eventStream {
                    receivedBatches.append(batch)
                    expectation.fulfill()
                    break // Exit after first batch
                }
            } catch {
                XCTFail("Stream error: \(error)")
            }
        }
        
        // Save an event
        let event = createEvent(kind: 1, content: "Test event")
        try await sqliteCache.saveEvent(event)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedBatches.count, 1)
        XCTAssertEqual(receivedBatches.first?.count, 1)
        XCTAssertEqual(receivedBatches.first?.first?.id, event.id)
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
                    if eventsWithExisting.count >= 3 {
                        expectationWithExisting.fulfill()
                        break
                    }
                }
            } catch {
                XCTFail("Stream error: \(error)")
            }
        }
        
        await fulfillment(of: [expectationWithExisting], timeout: 1.0)
        XCTAssertEqual(eventsWithExisting.count, 3)
        
        // Test with includeExisting = false
        let streamWithoutExisting = await sqliteCache.observeEvents(
            matching: NDKFilter(kinds: [1]),
            includeExisting: false
        )
        
        var eventsWithoutExisting: [NDKEvent] = []
        let expectationWithoutExisting = XCTestExpectation(description: "Only new events")
        
        Task {
            do {
                for try await batch in streamWithoutExisting {
                    eventsWithoutExisting.append(contentsOf: batch)
                    expectationWithoutExisting.fulfill()
                    break
                }
            } catch {
                XCTFail("Stream error: \(error)")
            }
        }
        
        // Save a new event
        let newEvent = createEvent(kind: 1, content: "New event")
        try await sqliteCache.saveEvent(newEvent)
        
        await fulfillment(of: [expectationWithoutExisting], timeout: 1.0)
        
        // Should only receive the new event
        XCTAssertEqual(eventsWithoutExisting.count, 1)
        XCTAssertEqual(eventsWithoutExisting.first?.id, newEvent.id)
    }
    
    // MARK: - GRDB Reactive Tests
    
    func testGRDBReactive_MultipleObservers() async throws {
        // Test multiple concurrent observers with different filters
        let author1 = "author1"
        let author2 = "author2"
        
        let filter1 = NDKFilter(authors: [author1], kinds: [1])
        let filter2 = NDKFilter(authors: [author2], kinds: [1])
        let filterAll = NDKFilter(kinds: [1])
        
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
        
        // Start observers
        Task {
            do {
                for try await batch in stream1 {
                    events1.append(contentsOf: batch)
                    exp1.fulfill()
                }
            } catch {}
        }
        
        Task {
            do {
                for try await batch in stream2 {
                    events2.append(contentsOf: batch)
                    exp2.fulfill()
                }
            } catch {}
        }
        
        Task {
            do {
                for try await batch in streamAll {
                    eventsAll.append(contentsOf: batch)
                    expAll.fulfill()
                }
            } catch {}
        }
        
        // Save events
        let event1 = createEvent(author: author1, kind: 1, content: "Author 1 event")
        let event2 = createEvent(author: author2, kind: 1, content: "Author 2 event")
        
        try await sqliteCache.saveEvent(event1)
        try await sqliteCache.saveEvent(event2)
        
        await fulfillment(of: [exp1, exp2, expAll], timeout: 2.0)
        
        // Verify each observer received correct events
        XCTAssertEqual(events1.count, 1)
        XCTAssertEqual(events1.first?.pubkey, author1)
        
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2.first?.pubkey, author2)
        
        XCTAssertEqual(eventsAll.count, 2)
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
        let broadDataSource = ndk.observe(
            filter: broadFilter,
            cachePolicy: .cacheOnly
        )
        
        // Create specific network subscription
        let specificFilter = NDKFilter(
            authors: [specificAuthor],
            kinds: [1],
            limit: 10
        )
        _ = ndk.observe(
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
            let dataSource = ndk.observe(filter: filter, cachePolicy: .cacheOnly)
            
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
        var event = NDKEvent(
            id: id ?? "",
            pubkey: author,
            createdAt: Timestamp.now,
            kind: Int(kind),
            tags: [],
            content: content,
            sig: "mock-signature"
        )
        if id == nil {
            event.id = event.calculateId()
        }
        return event
    }
}