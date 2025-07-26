import XCTest
@testable import NDKSwift

final class NDKSubscriptionTests: NDKTestCase {
    
    // MARK: - Basic Subscription Tests
    
    func testSubscriptionCreation() async {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [1], limit: 10)
        
        let subscription = await ndk.subscribe(filter)
        
        XCTAssertNotNil(subscription)
        XCTAssertEqual(subscription.filter.kinds, [1])
        XCTAssertEqual(subscription.filter.limit, 10)
        XCTAssertFalse(subscription.id.isEmpty)
    }
    
    func testSubscriptionWithCustomId() async {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [1])
        let customId = "my-custom-subscription-id"
        
        let subscription = await ndk.subscribe(filter, subscriptionId: customId)
        
        XCTAssertEqual(subscription.id, customId)
    }
    
    func testSubscriptionAutoStart() async throws {
        let ndk = createTestNDK()
        let mockRelay = RelayTestFactory.createMockRelay()
        await ndk.pool.addRelay(mockRelay)
        
        let filter = NDKFilter(kinds: [1])
        let subscription = await ndk.subscribe(filter)
        
        // Create test event
        let event = EventTestFactory.createTextNote()
        
        // Simulate receiving event
        await ndk.pool.handleMessage(.event(subscription.id, event), from: mockRelay)
        
        // Event should be received
        var receivedEvent: NDKEvent?
        for await event in subscription {
            receivedEvent = event
            break
        }
        
        XCTAssertNotNil(receivedEvent)
        subscription.stop()
    }
    
    // MARK: - AsyncSequence Tests
    
    func testAsyncSequenceIteration() async throws {
        let ndk = createTestNDK()
        let mockRelay = RelayTestFactory.createMockRelay()
        await ndk.pool.addRelay(mockRelay)
        
        let filter = NDKFilter(kinds: [1])
        let subscription = await ndk.subscribe(filter)
        
        // Create test events
        let events = (0..<5).map { i in
            EventTestFactory.createTextNote(content: "Event \(i)")
        }
        
        // Start consuming events
        let consumeTask = Task {
            var received: [NDKEvent] = []
            for await event in subscription {
                received.append(event)
                if received.count >= 5 {
                    break
                }
            }
            return received
        }
        
        // Simulate receiving events
        for event in events {
            await ndk.pool.handleMessage(.event(subscription.id, event), from: mockRelay)
        }
        
        let receivedEvents = await consumeTask.value
        XCTAssertEqual(receivedEvents.count, 5)
        
        subscription.stop()
    }
    
    func testAsyncSequenceWithFilter() async throws {
        let ndk = createTestNDK()
        let mockRelay = RelayTestFactory.createMockRelay()
        await ndk.pool.addRelay(mockRelay)
        
        let targetAuthor = TestFixtures.Keys.alice.publicKey
        let filter = NDKFilter(authors: [targetAuthor], kinds: [1])
        let subscription = await ndk.subscribe(filter)
        
        // Create mixed events
        let matchingEvent = EventTestFactory.createTextNote(pubkey: targetAuthor)
        let nonMatchingEvent = EventTestFactory.createTextNote(pubkey: TestFixtures.Keys.bob.publicKey)
        
        var receivedEvents: [NDKEvent] = []
        let consumeTask = Task {
            for await event in subscription {
                receivedEvents.append(event)
                if receivedEvents.count >= 1 {
                    break
                }
            }
        }
        
        // Send both events
        await ndk.pool.handleMessage(.event(subscription.id, matchingEvent), from: mockRelay)
        await ndk.pool.handleMessage(.event(subscription.id, nonMatchingEvent), from: mockRelay)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        consumeTask.cancel()
        
        // Only matching event should be received
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.pubkey, targetAuthor)
        
        subscription.stop()
    }
    
    // MARK: - Stop and Cleanup Tests
    
    func testSubscriptionStop() async throws {
        let ndk = createTestNDK()
        let subscription = await ndk.subscribe(NDKFilter(kinds: [1]))
        
        // Verify it's tracked
        let activeSubscriptions = await ndk.subscriptionTracker.getActiveSubscriptions()
        XCTAssertTrue(activeSubscriptions.contains { $0.id == subscription.id })
        
        // Stop subscription
        subscription.stop()
        
        // Small delay for async cleanup
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should no longer be tracked
        let updatedSubscriptions = await ndk.subscriptionTracker.getActiveSubscriptions()
        XCTAssertFalse(updatedSubscriptions.contains { $0.id == subscription.id })
    }
    
    func testSubscriptionAutoCleanup() async throws {
        let ndk = createTestNDK()
        
        var subscription: NDKSubscription? = await ndk.subscribe(NDKFilter(kinds: [1]))
        let subId = subscription!.id
        
        // Verify it's tracked
        var activeSubscriptions = await ndk.subscriptionTracker.getActiveSubscriptions()
        XCTAssertTrue(activeSubscriptions.contains { $0.id == subId })
        
        // Release reference
        subscription = nil
        
        // Force cleanup
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // Should be cleaned up
        activeSubscriptions = await ndk.subscriptionTracker.getActiveSubscriptions()
        XCTAssertFalse(activeSubscriptions.contains { $0.id == subId })
    }
    
    // MARK: - EOSE Tests
    
    func testEOSEHandling() async throws {
        let ndk = createTestNDK()
        let mockRelay = RelayTestFactory.createMockRelay()
        await ndk.pool.addRelay(mockRelay)
        
        let subscription = await ndk.subscribe(NDKFilter(kinds: [1]))
        
        var eoseReceived = false
        let eoseTask = Task {
            await subscription.waitForEose()
            eoseReceived = true
        }
        
        // Send EOSE
        await ndk.pool.handleMessage(.eose(subscription.id), from: mockRelay)
        
        // Wait for EOSE to be processed
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertTrue(eoseReceived)
        
        subscription.stop()
        eoseTask.cancel()
    }
    
    func testCloseOnEose() async throws {
        let ndk = createTestNDK()
        let mockRelay = RelayTestFactory.createMockRelay()
        await ndk.pool.addRelay(mockRelay)
        
        let subscription = await ndk.subscribe(
            NDKFilter(kinds: [1]),
            closeOnEose: true
        )
        
        // Send some events
        let event1 = EventTestFactory.createTextNote(content: "Event 1")
        let event2 = EventTestFactory.createTextNote(content: "Event 2")
        
        await ndk.pool.handleMessage(.event(subscription.id, event1), from: mockRelay)
        await ndk.pool.handleMessage(.event(subscription.id, event2), from: mockRelay)
        
        // Send EOSE
        await ndk.pool.handleMessage(.eose(subscription.id), from: mockRelay)
        
        // Collect events
        var receivedEvents: [NDKEvent] = []
        for await event in subscription {
            receivedEvents.append(event)
        }
        
        XCTAssertEqual(receivedEvents.count, 2)
        
        // Subscription should be stopped
        let activeSubscriptions = await ndk.subscriptionTracker.getActiveSubscriptions()
        XCTAssertFalse(activeSubscriptions.contains { $0.id == subscription.id })
    }
    
    // MARK: - Multiple Relay Tests
    
    func testSubscriptionAcrossMultipleRelays() async throws {
        let ndk = createTestNDK()
        let relay1 = RelayTestFactory.createMockRelay(url: "wss://relay1.test")
        let relay2 = RelayTestFactory.createMockRelay(url: "wss://relay2.test")
        
        await ndk.pool.addRelay(relay1)
        await ndk.pool.addRelay(relay2)
        
        let subscription = await ndk.subscribe(NDKFilter(kinds: [1]))
        
        // Send different events from different relays
        let event1 = EventTestFactory.createTextNote(content: "From relay 1")
        let event2 = EventTestFactory.createTextNote(content: "From relay 2")
        
        await ndk.pool.handleMessage(.event(subscription.id, event1), from: relay1)
        await ndk.pool.handleMessage(.event(subscription.id, event2), from: relay2)
        
        // Collect events
        var receivedEvents: [NDKEvent] = []
        let collectTask = Task {
            for await event in subscription {
                receivedEvents.append(event)
                if receivedEvents.count >= 2 {
                    break
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        collectTask.cancel()
        
        XCTAssertEqual(receivedEvents.count, 2)
        
        subscription.stop()
    }
    
    // MARK: - Error Handling Tests
    
    func testSubscriptionWithInvalidFilter() async {
        let ndk = createTestNDK()
        
        // Create filter with invalid parameters
        let filter = NDKFilter(
            since: Timestamp.now + 3600, // Future
            until: Timestamp.now - 3600  // Past (invalid range)
        )
        
        let subscription = await ndk.subscribe(filter)
        XCTAssertNotNil(subscription) // Should still create subscription
        
        subscription.stop()
    }
    
    // MARK: - Cache Integration Tests
    
    func testSubscriptionWithCachePolicy() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Pre-populate cache
        let cachedEvent = EventTestFactory.createTextNote(content: "Cached event")
        try await cache.saveEvent(cachedEvent)
        
        let filter = NDKFilter(kinds: [1])
        let subscription = await ndk.subscribe(
            filter,
            cachePolicy: .cacheOnly
        )
        
        // Should receive cached event
        var receivedFromCache: NDKEvent?
        for await event in subscription {
            receivedFromCache = event
            break
        }
        
        XCTAssertNotNil(receivedFromCache)
        XCTAssertEqual(receivedFromCache?.content, "Cached event")
        
        subscription.stop()
    }
    
    // MARK: - Performance Tests
    
    func testHighVolumeEventStreaming() async throws {
        let ndk = createTestNDK()
        let mockRelay = RelayTestFactory.createMockRelay()
        await ndk.pool.addRelay(mockRelay)
        
        let subscription = await ndk.subscribe(NDKFilter(kinds: [1]))
        
        let eventCount = 1000
        let events = (0..<eventCount).map { i in
            EventTestFactory.createTextNote(content: "High volume event \(i)")
        }
        
        measureAsyncPerformance {
            var received = 0
            let consumeTask = Task {
                for await _ in subscription {
                    received += 1
                    if received >= eventCount {
                        break
                    }
                }
            }
            
            // Send all events
            for event in events {
                await ndk.pool.handleMessage(.event(subscription.id, event), from: mockRelay)
            }
            
            await consumeTask.value
        }
        
        subscription.stop()
    }
}