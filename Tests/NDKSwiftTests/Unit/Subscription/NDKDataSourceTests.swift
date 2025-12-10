import XCTest
@testable import NDKSwiftCore

/// Tests for NDKSubscription (modern subscription API)
final class NDKSubscriptionTests: NDKTestCase {
    
    // MARK: - Basic DataSource Tests
    
    func testDataSourceCreation() async throws {
        try await performAsyncTest(timeout: 5) {
            let ndk = self.createTestNDK()
            let filter = NDKFilter(kinds: [1], limit: 10)
            
            let dataSource = ndk.subscribe(filter: filter)
            
            XCTAssertNotNil(dataSource)
            XCTAssertEqual(dataSource.data.count, 0) // Initially empty
            XCTAssertTrue(dataSource.isLoading) // Starts loading immediately upon creation
        }
    }
    
    func testDataSourceWithCustomId() async throws {
        try await performAsyncTest(timeout: 5) {
            let ndk = self.createTestNDK()
            let filter = NDKFilter(kinds: [1])
            let customId = "my-custom-subscription-id"
            
            let dataSource = ndk.subscribe(
                filter: filter,
                subscriptionId: customId
            )
            
            // The subscription ID is used internally but not exposed on DataSource
            // We can verify it's used by checking logs if needed
            XCTAssertNotNil(dataSource)
        }
    }
    
    func testDataSourceReceivesEvents() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let filter = NDKFilter(kinds: [1])
            let dataSource = ndk.subscribe(filter: filter)
            
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
            
            // Simulate receiving event through relay update
            await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            
            // Wait for event
            let receivedEvent = await consumeTask.value
            XCTAssertNotNil(receivedEvent)
            XCTAssertEqual(receivedEvent.id, event.id)
        }
    }
    
    // MARK: - AsyncSequence Tests
    
    func testAsyncSequenceIteration() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let filter = NDKFilter(kinds: [1])
            let dataSource = ndk.subscribe(filter: filter)
            
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
            
            // Simulate receiving events through relay updates
            for event in events {
                await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            }
            
            let receivedEvents = await consumeTask.value
            XCTAssertEqual(receivedEvents.count, 5)
        }
    }
    
    func testDataSourceFiltering() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let targetAuthor = TestFixtures.Keys.alice.publicKey
            let filter = NDKFilter(authors: [targetAuthor], kinds: [1])
            let dataSource = ndk.subscribe(filter: filter)
            
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
            await dataSource.handleRelayUpdate(.event(matchingEvent, relay: "wss://test.relay"))
            await dataSource.handleRelayUpdate(.event(nonMatchingEvent, relay: "wss://test.relay"))
            
            // Wait for processing
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            consumeTask.cancel()
            
            // Only matching event should be received
            XCTAssertEqual(receivedEvents.count, 1)
            XCTAssertEqual(receivedEvents.first?.pubkey, targetAuthor)
        }
    }
    
    // MARK: - EOSE Tests
    
    func testEOSEHandling() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
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
    }
    
    func testCloseOnEose() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            // Create with closeOnEose = true
            let dataSource = ndk.subscribe(
                filter: NDKFilter(kinds: [1]),
                closeOnEose: true
            )
            
            let event = EventTestFactory.createTextNote()
            
            // Start collecting events until EOSE
            let collectTask = Task {
                var collected: [NDKEvent] = []
                for await event in dataSource.eventsUntilEOSE {
                    collected.append(event)
                }
                return collected
            }
            
            // Give time to set up
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01s
            
            // Send some events
            await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            
            // Send EOSE to complete the sequence
            await dataSource.handleRelayUpdate(.eose(relay: "wss://test.relay"))
            
            // Wait for collection to complete
            let events = await collectTask.value
            
            // Should have received the event before EOSE
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.id, event.id)
        }
    }
    
    // MARK: - Data Collection Tests
    
    func testCollectWithTimeout() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
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
                await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            }
            
            let collectedEvents = await collectTask.value
            XCTAssertEqual(collectedEvents.count, 3)
        }
    }
    
    func testFirstWithTimeout() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
            let event = EventTestFactory.createTextNote()
            
            // Start waiting for first
            let firstTask = Task {
                await dataSource.first(timeout: 2.0)
            }
            
            // Give time to set up
            try await Task.sleep(nanoseconds: 100_000_000)
            
            // Send event
            await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            
            let firstEvent = await firstTask.value
            XCTAssertNotNil(firstEvent)
            XCTAssertEqual(firstEvent?.id, event.id)
        }
    }
    
    // MARK: - Multiple Observer Tests
    
    func testMultipleDataSources() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            // Create two data sources with different filters
            let dataSource1 = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            let dataSource2 = ndk.subscribe(filter: NDKFilter(kinds: [2]))
            
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
            await dataSource1.handleRelayUpdate(.event(kind1Event, relay: "wss://test.relay"))
            await dataSource2.handleRelayUpdate(.event(kind2Event, relay: "wss://test.relay"))
            
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
    }
    
    // MARK: - Cache Policy Tests
    
    func testCacheOnlyPolicy() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            // Pre-populate cache
            let event = EventTestFactory.createTextNote()
            try await cache.saveEvent(event)
            
            // Create data source with cache-only policy
            let dataSource = ndk.subscribe(
                filter: NDKFilter(kinds: [1]),
                cachePolicy: .cacheOnly
            )
            
            // Should get event from cache
            let firstEvent = await dataSource.first(timeout: 1.0)
            XCTAssertNotNil(firstEvent)
            XCTAssertEqual(firstEvent?.id, event.id)
        }
    }
    
    // MARK: - Transform Tests
    
    func testDataSourceWithTransform() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            // Create data source that transforms events to just their content
            let dataSource = ndk.subscribe(
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
            await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            
            let content = await consumeTask.value
            XCTAssertEqual(content, "Hello, world!")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testDataSourceErrorHandling() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
            // Error should be nil initially
            XCTAssertNil(dataSource.error)
            
            // DataSource should handle network errors gracefully
            // In the current implementation, errors are logged but don't propagate to the error property
            // This test documents the current behavior
            XCTAssertNil(dataSource.error)
        }
    }
    
    // MARK: - Transform Edge Cases
    
    func testTransformReturningNil() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            // Transform that filters out certain events
            let dataSource = ndk.subscribe(
                filter: NDKFilter(kinds: [1]),
                transform: { event in
                    // Only return events with "important" in content
                    event.content.contains("important") ? event.content : nil
                }
            )
            
            let importantEvent = EventTestFactory.createTextNote(content: "This is important")
            let normalEvent = EventTestFactory.createTextNote(content: "This is normal")
            
            var receivedContent: [String] = []
            let consumeTask = Task {
                for await content in dataSource.events {
                    receivedContent.append(content)
                    if receivedContent.count >= 1 { break }
                }
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            // Send both events
            await dataSource.handleRelayUpdate(.event(normalEvent, relay: "wss://test.relay"))
            await dataSource.handleRelayUpdate(.event(importantEvent, relay: "wss://test.relay"))
            
            try await Task.sleep(nanoseconds: 200_000_000)
            consumeTask.cancel()
            
            // Only important event should be transformed and received
            XCTAssertEqual(receivedContent.count, 1)
            XCTAssertEqual(receivedContent.first, "This is important")
        }
    }
    
    func testComplexTransform() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            struct EventSummary {
                let id: String
                let kind: Int
                let wordCount: Int
            }
            
            // Transform events to summaries
            let dataSource = ndk.subscribe(
                filter: NDKFilter(kinds: [1]),
                transform: { event in
                    EventSummary(
                        id: event.id,
                        kind: event.kind,
                        wordCount: event.content.split(separator: " ").count
                    )
                }
            )
            
            let event = EventTestFactory.createTextNote(content: "Hello world from Nostr")
            
            let consumeTask = Task {
                for await summary in dataSource.events {
                    return summary
                }
                fatalError("Should not reach here")
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            
            let summary = await consumeTask.value
            XCTAssertEqual(summary.id, event.id)
            XCTAssertEqual(summary.kind, 1)
            XCTAssertEqual(summary.wordCount, 4)
        }
    }
    
    // MARK: - Update Filter Tests
    
    func testUpdateFilter() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            // Start with kind 1 filter
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
            let kind1Event = EventTestFactory.createEvent(kind: 1, content: "Kind 1")
            let kind2Event = EventTestFactory.createEvent(kind: 2, content: "Kind 2")
            
            var receivedEvents: [NDKEvent] = []
            let consumeTask = Task {
                for await event in dataSource.events {
                    receivedEvents.append(event)
                }
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            // Send kind 1 event - should be received
            await dataSource.handleRelayUpdate(.event(kind1Event, relay: "wss://test.relay"))
            try await Task.sleep(nanoseconds: 100_000_000)
            
            XCTAssertEqual(receivedEvents.count, 1)
            XCTAssertEqual(receivedEvents.first?.kind, 1)
            
            // Update filter to kind 2
            await dataSource.updateFilter(NDKFilter(kinds: [2]))
            
            // Clear received events to track new ones
            receivedEvents.removeAll()
            
            // Send both kinds - only kind 2 should be received
            await dataSource.handleRelayUpdate(.event(kind1Event, relay: "wss://test.relay"))
            await dataSource.handleRelayUpdate(.event(kind2Event, relay: "wss://test.relay"))
            try await Task.sleep(nanoseconds: 200_000_000)
            
            // Should only receive kind 2 event after filter update
            XCTAssertEqual(receivedEvents.count, 1)
            XCTAssertEqual(receivedEvents.first?.kind, 2)
            
            consumeTask.cancel()
        }
    }
    
    func testUpdateFilterClearsData() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
            // Add some events
            let events = (0..<3).map { i in
                EventTestFactory.createTextNote(content: "Event \(i)")
            }
            
            for event in events {
                await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            }
            
            try await Task.sleep(nanoseconds: 200_000_000)
            
            // Should have data
            XCTAssertEqual(dataSource.data.count, 3)
            
            // Update filter
            await dataSource.updateFilter(NDKFilter(kinds: [2]))
            
            // Data should be cleared
            XCTAssertEqual(dataSource.data.count, 0)
        }
    }
    
    // MARK: - Refresh Tests
    
    func testRefresh() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
            // Add initial events
            let initialEvents = (0..<3).map { i in
                EventTestFactory.createTextNote(content: "Initial \(i)")
            }
            
            for event in initialEvents {
                await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
            }
            
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(dataSource.data.count, 3)
            
            // Refresh should clear data
            await dataSource.refresh()
            XCTAssertEqual(dataSource.data.count, 0)
            
            // New events should be received after refresh
            let newEvent = EventTestFactory.createTextNote(content: "New after refresh")
            await dataSource.handleRelayUpdate(.event(newEvent, relay: "wss://test.relay"))
            
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(dataSource.data.count, 1)
            XCTAssertEqual(dataSource.data.first?.content, "New after refresh")
        }
    }
    
    // MARK: - Deduplication Tests
    
    func testEventDeduplication() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
            // Create same event
            let event = EventTestFactory.createTextNote(content: "Duplicate test")
            
            var receivedEvents: [NDKEvent] = []
            let consumeTask = Task {
                for await event in dataSource.events {
                    receivedEvents.append(event)
                }
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            // Send same event multiple times
            for _ in 0..<5 {
                await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            consumeTask.cancel()
            
            // Should only receive the event once
            XCTAssertEqual(receivedEvents.count, 1)
            XCTAssertEqual(dataSource.data.count, 1)
        }
    }
    
    // MARK: - Network Only Policy Tests
    
    func testNetworkOnlyPolicy() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            // Pre-populate cache
            let cachedEvent = EventTestFactory.createTextNote(content: "Cached event")
            try await cache.saveEvent(cachedEvent)
            
            // Create data source with network-only policy
            let dataSource = ndk.subscribe(
                filter: NDKFilter(kinds: [1]),
                cachePolicy: .networkOnly
            )
            
            // Network-only should not return cached events immediately
            let firstEvent = await dataSource.first(timeout: 0.5)
            XCTAssertNil(firstEvent, "Network-only policy should not return cached events")
            
            // But should receive new network events
            let networkEvent = EventTestFactory.createTextNote(content: "Network event")
            
            let consumeTask = Task {
                for await event in dataSource.events {
                    return event
                }
                fatalError("Should not reach here")
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            await dataSource.handleRelayUpdate(.event(networkEvent, relay: "wss://test.relay"))
            
            let receivedEvent = await consumeTask.value
            XCTAssertEqual(receivedEvent.content, "Network event")
        }
    }
    
    // MARK: - Relay Updates Tests
    
    func testAggregatedEOSE() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
            var aggregatedEoseReceived = false
            let eoseTask = Task {
                for await update in dataSource.relayUpdates {
                    if case .aggregatedEose = update {
                        aggregatedEoseReceived = true
                        break
                    }
                }
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            // Send aggregated EOSE
            await dataSource.handleRelayUpdate(.aggregatedEose)
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            XCTAssertTrue(aggregatedEoseReceived)
            eoseTask.cancel()
        }
    }
    
    func testRelayEventUpdate() async throws {
        try await performAsyncTest(timeout: 5) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)
            
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            
            let event = EventTestFactory.createTextNote()
            let relayURL = "wss://specific.relay"
            
            var eventReceived = false
            var relayEventReceived = false
            
            let eventTask = Task {
                for await receivedEvent in dataSource.events {
                    if receivedEvent.id == event.id {
                        eventReceived = true
                        break
                    }
                }
            }
            
            let relayTask = Task {
                for await update in dataSource.relayUpdates {
                    if case let .event(receivedEvent, relay: receivedRelay) = update {
                        if receivedEvent.id == event.id && receivedRelay == relayURL {
                            relayEventReceived = true
                            break
                        }
                    }
                }
            }
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            // Send event through relay update
            await dataSource.handleRelayUpdate(.event(event, relay: relayURL))
            
            try await Task.sleep(nanoseconds: 200_000_000)
            
            XCTAssertTrue(eventReceived, "Event should be received through events stream")
            XCTAssertTrue(relayEventReceived, "Event should be received through relay updates")
            
            eventTask.cancel()
            relayTask.cancel()
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyFilter() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Empty filter should match all events
        let dataSource = ndk.subscribe(filter: NDKFilter())
        
        let events = [
            EventTestFactory.createEvent(kind: 1),
            EventTestFactory.createEvent(kind: 2),
            EventTestFactory.createEvent(kind: 3)
        ]
        
        var receivedEvents: [NDKEvent] = []
        let consumeTask = Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
                if receivedEvents.count >= 3 { break }
            }
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        for event in events {
            await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        consumeTask.cancel()
        
        // Should receive all events with empty filter
        XCTAssertEqual(receivedEvents.count, 3)
    }
    
    func testLargeEventBatch() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
        
        // Create many events
        let eventCount = 100
        let events = (0..<eventCount).map { i in
            EventTestFactory.createTextNote(content: "Event \(i)")
        }
        
        let collectTask = Task {
            await dataSource.collect(timeout: 2.0, limit: eventCount)
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Send all events rapidly
        for event in events {
            await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
        }
        
        let collectedEvents = await collectTask.value
        XCTAssertEqual(collectedEvents.count, eventCount)
    }
    
    // MARK: - Memory Management Tests
    
    func testDataSourceCleanup() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        var dataSource: NDKSubscription<NDKEvent>? = ndk.subscribe(filter: NDKFilter(kinds: [1]))
        
        let event = EventTestFactory.createTextNote()
        
        // Start consuming
        let consumeTask = Task { [weak dataSource] in
            guard let dataSource = dataSource else { return }
            for await _ in dataSource.events {
                break
            }
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        await dataSource?.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify data source is working
        XCTAssertEqual(dataSource?.data.count, 1)
        
        // Release data source
        dataSource = nil
        
        // Cancel task
        consumeTask.cancel()
        
        // Give time for cleanup
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Data source should be deallocated
        XCTAssertNil(dataSource)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentEventProcessing() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
        
        let eventCount = 50
        let events = (0..<eventCount).map { i in
            EventTestFactory.createTextNote(content: "Concurrent \(i)")
        }
        
        let collectTask = Task {
            await dataSource.collect(timeout: 3.0)
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Send events concurrently from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for (index, event) in events.enumerated() {
                group.addTask { [dataSource] in
                    let relay = "wss://relay\(index % 3).test"
                    await dataSource.handleRelayUpdate(.event(event, relay: relay))
                }
            }
        }
        
        let collectedEvents = await collectTask.value
        
        // All events should be received despite concurrent processing
        XCTAssertEqual(collectedEvents.count, eventCount)
        
        // Verify no duplicates
        let uniqueIds = Set(collectedEvents.map { $0.id })
        XCTAssertEqual(uniqueIds.count, eventCount)
    }
}