import XCTest
@testable import NDKSwift

/// Tests for NDKDataSource (modern subscription API)
final class NDKDataSourceTests: NDKTestCase {
    
    // MARK: - Basic DataSource Tests
    
    func testDataSourceCreation() async {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [1], limit: 10)
        
        let dataSource = ndk.observe(filter: filter)
        
        XCTAssertNotNil(dataSource)
        XCTAssertEqual(dataSource.data.count, 0) // Initially empty
        XCTAssertFalse(dataSource.isLoading) // Not loading until iteration starts
    }
    
    func testDataSourceWithCustomId() async {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [1])
        let customId = "my-custom-subscription-id"
        
        let dataSource = ndk.observe(
            filter: filter,
            subscriptionId: customId
        )
        
        // The subscription ID is used internally but not exposed on DataSource
        // We can verify it's used by checking logs if needed
        XCTAssertNotNil(dataSource)
    }
    
    func testDataSourceReceivesEvents() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let filter = NDKFilter(kinds: [1])
        let dataSource = ndk.observe(filter: filter)
        
        // Create test event
        let event = EventTestFactory.createTextNote()
        
        // Start consuming events
        let consumeTask = Task {
            for await event in dataSource.events {
                return event // Return first event
            }
            fatalError("Should not reach here")
        }
        
        // Give the data source time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Simulate receiving event through cache
        await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        
        // Wait for event
        let receivedEvent = await consumeTask.value
        XCTAssertNotNil(receivedEvent)
        XCTAssertEqual(receivedEvent?.id, event.id)
    }
    
    // MARK: - AsyncSequence Tests
    
    func testAsyncSequenceIteration() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let filter = NDKFilter(kinds: [1])
        let dataSource = ndk.observe(filter: filter)
        
        // Create test events
        let events = (0..<5).map { i in
            EventTestFactory.createTextNote(content: "Event \(i)")
        }
        
        // Start consuming events
        let consumeTask = Task {
            var received: [NDKEvent] = []
            for await event in dataSource.events {
                received.append(event)
                if received.count >= 5 {
                    break
                }
            }
            return received
        }
        
        // Give time to set up
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate receiving events
        for event in events {
            await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        }
        
        let receivedEvents = await consumeTask.value
        XCTAssertEqual(receivedEvents.count, 5)
    }
    
    func testDataSourceFiltering() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let targetAuthor = TestFixtures.Keys.alice.publicKey
        let filter = NDKFilter(authors: [targetAuthor], kinds: [1])
        let dataSource = ndk.observe(filter: filter)
        
        // Create mixed events
        let matchingEvent = EventTestFactory.createTextNote(pubkey: targetAuthor)
        let nonMatchingEvent = EventTestFactory.createTextNote(pubkey: TestFixtures.Keys.bob.publicKey)
        
        var receivedEvents: [NDKEvent] = []
        let consumeTask = Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
                if receivedEvents.count >= 1 {
                    break
                }
            }
        }
        
        // Give time to set up
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Send both events to cache
        await cache.processEvent(matchingEvent, from: "wss://test.relay", subscriptionId: "test")
        await cache.processEvent(nonMatchingEvent, from: "wss://test.relay", subscriptionId: "test")
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        consumeTask.cancel()
        
        // Only matching event should be received
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.pubkey, targetAuthor)
    }
    
    // MARK: - EOSE Tests
    
    func testEOSEHandling() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let dataSource = ndk.observe(filter: NDKFilter(kinds: [1]))
        
        var eoseReceived = false
        let eoseTask = Task {
            for await update in dataSource.relayUpdates {
                if case .eose = update {
                    eoseReceived = true
                    break
                }
            }
        }
        
        // Give time to set up
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Simulate EOSE
        await dataSource.handleRelayUpdate(.eose(relay: "wss://test.relay"))
        
        // Wait for EOSE to be processed
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertTrue(eoseReceived)
        
        eoseTask.cancel()
    }
    
    func testCloseOnEose() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Create with closeOnEose = true
        let dataSource = ndk.observe(
            filter: NDKFilter(kinds: [1]),
            closeOnEose: true
        )
        
        let event = EventTestFactory.createTextNote()
        
        // Use eventsUntilEOSE for automatic completion
        let events = await dataSource.eventsUntilEOSE.reduce(into: []) { result, event in
            result.append(event)
        }
        
        // Should be empty since we didn't send any events
        XCTAssertEqual(events.count, 0)
    }
    
    // MARK: - Data Collection Tests
    
    func testCollectWithTimeout() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let dataSource = ndk.observe(filter: NDKFilter(kinds: [1]))
        
        // Create events
        let events = (0..<3).map { i in
            EventTestFactory.createTextNote(content: "Event \(i)")
        }
        
        // Start collection
        let collectTask = Task {
            await dataSource.collect(timeout: 1.0)
        }
        
        // Give time to set up
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Send events
        for event in events {
            await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        }
        
        let collectedEvents = await collectTask.value
        XCTAssertEqual(collectedEvents.count, 3)
    }
    
    func testFirstWithTimeout() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let dataSource = ndk.observe(filter: NDKFilter(kinds: [1]))
        
        let event = EventTestFactory.createTextNote()
        
        // Start waiting for first
        let firstTask = Task {
            await dataSource.first(timeout: 2.0)
        }
        
        // Give time to set up
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Send event
        await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        
        let firstEvent = await firstTask.value
        XCTAssertNotNil(firstEvent)
        XCTAssertEqual(firstEvent?.id, event.id)
    }
    
    // MARK: - Multiple Observer Tests
    
    func testMultipleDataSources() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Create two data sources with different filters
        let dataSource1 = ndk.observe(filter: NDKFilter(kinds: [1]))
        let dataSource2 = ndk.observe(filter: NDKFilter(kinds: [2]))
        
        let kind1Event = EventTestFactory.createEvent(kind: 1, content: "Kind 1")
        let kind2Event = EventTestFactory.createEvent(kind: 2, content: "Kind 2")
        
        var events1: [NDKEvent] = []
        var events2: [NDKEvent] = []
        
        // Start consuming from both
        let task1 = Task {
            for await event in dataSource1.events {
                events1.append(event)
                if events1.count >= 1 { break }
            }
        }
        
        let task2 = Task {
            for await event in dataSource2.events {
                events2.append(event)
                if events2.count >= 1 { break }
            }
        }
        
        // Give time to set up
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Send events
        await cache.processEvent(kind1Event, from: "wss://test.relay", subscriptionId: "test")
        await cache.processEvent(kind2Event, from: "wss://test.relay", subscriptionId: "test")
        
        // Wait for processing
        try await Task.sleep(nanoseconds: 200_000_000)
        
        task1.cancel()
        task2.cancel()
        
        // Each should only receive its filtered events
        XCTAssertEqual(events1.count, 1)
        XCTAssertEqual(events1.first?.kind, 1)
        
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2.first?.kind, 2)
    }
    
    // MARK: - Cache Policy Tests
    
    func testCacheOnlyPolicy() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Pre-populate cache
        let event = EventTestFactory.createTextNote()
        try await cache.saveEvent(event)
        
        // Create data source with cache-only policy
        let dataSource = ndk.observe(
            filter: NDKFilter(kinds: [1]),
            cachePolicy: .cacheOnly
        )
        
        // Should get event from cache
        let firstEvent = await dataSource.first(timeout: 1.0)
        XCTAssertNotNil(firstEvent)
        XCTAssertEqual(firstEvent?.id, event.id)
    }
    
    // MARK: - Transform Tests
    
    func testDataSourceWithTransform() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Create data source that transforms events to just their content
        let dataSource = ndk.observe(
            filter: NDKFilter(kinds: [1]),
            transform: { event in event.content }
        )
        
        let event = EventTestFactory.createTextNote(content: "Hello, world!")
        
        let consumeTask = Task {
            for await content in dataSource.events {
                return content
            }
            fatalError("Should not reach here")
        }
        
        // Give time to set up
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Send event
        await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        
        let content = await consumeTask.value
        XCTAssertEqual(content, "Hello, world!")
    }
    
    // MARK: - Error Handling Tests
    
    func testDataSourceErrorHandling() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let dataSource = ndk.observe(filter: NDKFilter(kinds: [1]))
        
        // Error should be nil initially
        XCTAssertNil(dataSource.error)
        
        // DataSource should handle network errors gracefully
        // In the current implementation, errors are logged but don't propagate to the error property
        // This test documents the current behavior
        XCTAssertNil(dataSource.error)
    }
}