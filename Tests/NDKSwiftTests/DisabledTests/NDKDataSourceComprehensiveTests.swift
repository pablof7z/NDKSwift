@testable import NDKSwiftCore
import XCTest

/// Comprehensive tests for NDKSubscription
final class NDKSubscriptionComprehensiveTests: NDKTestCase {
    // MARK: - Transform Tests

    func testTransformFilteringOutEvents() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

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

        // Give time to set up
        try await Task.sleep(nanoseconds: 100_000_000)

        // Send both events
        try await cache.processEvent(normalEvent, from: "wss://test.relay", subscriptionId: "test")
        try await cache.processEvent(importantEvent, from: "wss://test.relay", subscriptionId: "test")

        // Wait for processing
        try await Task.sleep(nanoseconds: 200_000_000)
        consumeTask.cancel()

        // Only important event should be transformed and received
        XCTAssertEqual(receivedContent.count, 1)
        XCTAssertEqual(receivedContent.first, "This is important")
    }

    func testComplexTransformToCustomType() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        struct EventSummary: Equatable {
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
        try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")

        let summary = await consumeTask.value
        XCTAssertEqual(summary.id, event.id)
        XCTAssertEqual(summary.kind, 1)
        XCTAssertEqual(summary.wordCount, 4)
    }

    // MARK: - Filter Update Tests

    func testUpdateFilterChangesDataStream() async throws {
        try await performAsyncTest(timeout: 10) {
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
                    if receivedEvents.count >= 10 { break } // Add safety break
                }
            }

            try await Task.sleep(nanoseconds: 100_000_000)

            // Send kind 1 event - should be received
            try await cache.processEvent(kind1Event, from: "wss://test.relay", subscriptionId: "test")
            try await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertEqual(receivedEvents.count, 1)
            XCTAssertEqual(receivedEvents.first?.kind, 1)

            // Update filter to kind 2
            await dataSource.updateFilter(NDKFilter(kinds: [2]))

            // Clear received events to track new ones
            receivedEvents.removeAll()

            // Send both kinds - only kind 2 should be received
            try await cache.processEvent(kind1Event, from: "wss://test.relay", subscriptionId: "test2")
            try await cache.processEvent(kind2Event, from: "wss://test.relay", subscriptionId: "test2")
            try await Task.sleep(nanoseconds: 200_000_000)

            // Should only receive kind 2 event after filter update
            XCTAssertEqual(receivedEvents.count, 1)
            XCTAssertEqual(receivedEvents.first?.kind, 2)

            consumeTask.cancel()
        }
    }

    func testUpdateFilterClearsExistingData() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))

        // Add some events
        let events = (0 ..< 3).map { i in
            EventTestFactory.createTextNote(content: "Event \(i)")
        }

        for event in events {
            try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should have data
        XCTAssertEqual(dataSource.data.count, 3)

        // Update filter
        await dataSource.updateFilter(NDKFilter(kinds: [2]))

        // Data should be cleared
        XCTAssertEqual(dataSource.data.count, 0)
    }

    // MARK: - Refresh Tests

    func testRefreshClearsAndReloadsData() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))

        // Add initial events
        let initialEvents = (0 ..< 3).map { i in
            EventTestFactory.createTextNote(content: "Initial \(i)")
        }

        for event in initialEvents {
            try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(dataSource.data.count, 3)

        // Refresh should clear data
        await dataSource.refresh()
        XCTAssertEqual(dataSource.data.count, 0)

        // New events should be received after refresh
        let newEvent = EventTestFactory.createTextNote(content: "New after refresh")
        try await cache.processEvent(newEvent, from: "wss://test.relay", subscriptionId: "test")

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(dataSource.data.count, 1)
        XCTAssertEqual(dataSource.data.first?.content, "New after refresh")
    }

    // MARK: - Deduplication Tests

    func testDuplicateEventPrevention() async throws {
        try await performAsyncTest(timeout: 10) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)

            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))

            // Create same event
            let event = EventTestFactory.createTextNote(content: "Duplicate test")

            var receivedEvents: [NDKEvent] = []
            let consumeTask = Task {
                for await event in dataSource.events {
                    receivedEvents.append(event)
                    if receivedEvents.count >= 10 { break } // Add safety break
                }
            }

            try await Task.sleep(nanoseconds: 100_000_000)

            // Send same event multiple times
            for _ in 0 ..< 5 {
                try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            try await Task.sleep(nanoseconds: 100_000_000)
            consumeTask.cancel()

            // Should only receive the event once
            XCTAssertEqual(receivedEvents.count, 1)
            XCTAssertEqual(dataSource.data.count, 1)
        }
    }

    // MARK: - Cache Policy Tests

    func testNetworkOnlyPolicyIgnoresCache() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

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
        try await cache.processEvent(networkEvent, from: "wss://test.relay", subscriptionId: "test")

        let receivedEvent = await consumeTask.value
        XCTAssertEqual(receivedEvent.content, "Network event")
    }

    func testCacheWithNetworkPolicyReturnsAndUpdates() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        // Pre-populate cache
        let cachedEvent = EventTestFactory.createTextNote(content: "Cached event")
        try await cache.saveEvent(cachedEvent)

        let dataSource = ndk.subscribe(
            filter: NDKFilter(kinds: [1]),
            cachePolicy: .cacheWithNetwork
        )

        var receivedEvents: [NDKEvent] = []
        let consumeTask = Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
                if receivedEvents.count >= 2 { break }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Should get cached event
        XCTAssertEqual(dataSource.data.count, 1)
        XCTAssertEqual(dataSource.data.first?.content, "Cached event")

        // And should also receive new network events
        let networkEvent = EventTestFactory.createTextNote(content: "Network event")
        try await cache.processEvent(networkEvent, from: "wss://test.relay", subscriptionId: "test")

        try await Task.sleep(nanoseconds: 200_000_000)
        consumeTask.cancel()

        XCTAssertEqual(receivedEvents.count, 2)
        XCTAssertTrue(receivedEvents.contains { $0.content == "Cached event" })
        XCTAssertTrue(receivedEvents.contains { $0.content == "Network event" })
    }

    // MARK: - Relay Update Tests

    func testAggregatedEOSEHandling() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

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

    func testRelaySpecificEventHandling() async throws {
        try await performAsyncTest(timeout: 10) {
            let cache = self.createMemoryCache()
            let ndk = self.createTestNDK(cache: cache)

            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))

            let event = EventTestFactory.createTextNote()
            let relayURL = "wss://specific.relay"

            var eventReceived = false
            var relayEventReceived = false
            var receivedRelay: String?

            let eventTask = Task {
                for await receivedEvent in dataSource.events {
                    if receivedEvent.id == event.id {
                        eventReceived = true
                        break // Exit after finding the event
                    }
                }
            }

            let relayTask = Task {
                for await update in dataSource.relayUpdates {
                    if case let .event(receivedEvent, relay: relay) = update {
                        if receivedEvent.id == event.id {
                            relayEventReceived = true
                            receivedRelay = relay
                            break // Exit after finding the event
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
            XCTAssertEqual(receivedRelay, relayURL)

            eventTask.cancel()
            relayTask.cancel()
        }
    }

    func testMultipleRelayEOSETracking() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))

        var eoseRelays: Set<String> = []
        let eoseTask = Task {
            for await update in dataSource.relayUpdates {
                switch update {
                case let .eose(relay):
                    eoseRelays.insert(relay)
                case .aggregatedEose:
                    break
                default:
                    continue
                }

                if eoseRelays.count >= 3 {
                    break
                }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Send EOSE from multiple relays
        await dataSource.handleRelayUpdate(.eose(relay: "wss://relay1.test"))
        await dataSource.handleRelayUpdate(.eose(relay: "wss://relay2.test"))
        await dataSource.handleRelayUpdate(.eose(relay: "wss://relay3.test"))

        try await Task.sleep(nanoseconds: 200_000_000)
        eoseTask.cancel()

        XCTAssertEqual(eoseRelays.count, 3)
        XCTAssertTrue(eoseRelays.contains("wss://relay1.test"))
        XCTAssertTrue(eoseRelays.contains("wss://relay2.test"))
        XCTAssertTrue(eoseRelays.contains("wss://relay3.test"))
    }

    // MARK: - Edge Cases and Boundary Tests

    func testEmptyFilterMatchesAllEvents() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        // Empty filter should match all events
        let dataSource = ndk.subscribe(filter: NDKFilter())

        let events = [
            EventTestFactory.createEvent(kind: 1),
            EventTestFactory.createEvent(kind: 2),
            EventTestFactory.createEvent(kind: 3),
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
            try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        consumeTask.cancel()

        // Should receive all events with empty filter
        XCTAssertEqual(receivedEvents.count, 3)
    }

    func testLargeEventBatchProcessing() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))

        // Create many events
        let eventCount = 100
        let events = (0 ..< eventCount).map { i in
            EventTestFactory.createTextNote(content: "Event \(i)")
        }

        let collectTask = Task {
            await dataSource.collect(timeout: 3.0, limit: eventCount)
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Send all events rapidly
        for event in events {
            try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        }

        let collectedEvents = await collectTask.value
        XCTAssertEqual(collectedEvents.count, eventCount)

        // Verify no duplicates
        let uniqueIds = Set(collectedEvents.map { $0.id })
        XCTAssertEqual(uniqueIds.count, eventCount)
    }

    func testCollectWithLimit() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))

        // Create more events than limit
        let events = (0 ..< 20).map { i in
            EventTestFactory.createTextNote(content: "Event \(i)")
        }

        let collectTask = Task {
            await dataSource.collect(timeout: 2.0, limit: 10)
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Send all events
        for event in events {
            try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
        }

        let collectedEvents = await collectTask.value

        // Should only collect up to the limit
        XCTAssertEqual(collectedEvents.count, 10)
    }

    // MARK: - Memory Management Tests

    func testDataSourceDeallocatesCorrectly() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        weak var weakDataSource: NDKSubscription<NDKEvent>?
        var consumeTask: Task<Void, Never>?

        // Create data source in a scope so it can be deallocated
        do {
            let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))
            weakDataSource = dataSource

            // Start consuming to ensure it's active
            consumeTask = Task {
                for await _ in dataSource.events {
                    break
                }
            }

            // Give task a moment to start
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        // Cancel the task to prevent hanging
        consumeTask?.cancel()

        // Give time for deallocation
        try await Task.sleep(nanoseconds: 100_000_000)

        // Data source should be deallocated
        XCTAssertNil(weakDataSource)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentEventProcessingMaintainsOrder() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let dataSource = ndk.subscribe(filter: NDKFilter(kinds: [1]))

        let eventCount = 50
        let events = (0 ..< eventCount).map { i in
            EventTestFactory.createTextNote(content: "Concurrent \(i)")
        }

        let collectTask = Task {
            await dataSource.collect(timeout: 5.0)
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Send events concurrently from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for (index, event) in events.enumerated() {
                group.addTask {
                    let relay = "wss://relay\(index % 3).test"
                    try? await cache.processEvent(event, from: relay, subscriptionId: "test")
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

    func testMultipleObserversReceiveEvents() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let filter = NDKFilter(kinds: [1])

        // Create multiple observers for the same filter
        let observer1 = ndk.subscribe(filter: filter)
        let observer2 = ndk.subscribe(filter: filter)
        let observer3 = ndk.subscribe(filter: filter)

        var events1: [NDKEvent] = []
        var events2: [NDKEvent] = []
        var events3: [NDKEvent] = []

        let task1 = Task {
            for await event in observer1.events {
                events1.append(event)
                if events1.count >= 3 { break }
            }
        }

        let task2 = Task {
            for await event in observer2.events {
                events2.append(event)
                if events2.count >= 3 { break }
            }
        }

        let task3 = Task {
            for await event in observer3.events {
                events3.append(event)
                if events3.count >= 3 { break }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Send events
        for i in 0 ..< 3 {
            let event = EventTestFactory.createTextNote(content: "Event \(i)")
            try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        task1.cancel()
        task2.cancel()
        task3.cancel()

        // All observers should receive all events
        XCTAssertEqual(events1.count, 3)
        XCTAssertEqual(events2.count, 3)
        XCTAssertEqual(events3.count, 3)

        // Verify they received the same events
        XCTAssertEqual(Set(events1.map { $0.id }), Set(events2.map { $0.id }))
        XCTAssertEqual(Set(events2.map { $0.id }), Set(events3.map { $0.id }))
    }
}
