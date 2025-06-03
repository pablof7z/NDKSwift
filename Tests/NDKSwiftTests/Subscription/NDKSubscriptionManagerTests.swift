import XCTest
@testable import NDKSwift

final class NDKSubscriptionManagerTests: XCTestCase {
    var ndk: NDK!
    var manager: NDKSubscriptionManager!
    var mockRelay1: MockRelay!
    var mockRelay2: MockRelay!
    var mockCache: MockCacheAdapter!
    
    override func setUp() async throws {
        try await super.setUp()
        
        ndk = NDK()
        manager = NDKSubscriptionManager(ndk: ndk)
        
        mockRelay1 = MockRelay(url: "wss://relay1.example.com")
        mockRelay2 = MockRelay(url: "wss://relay2.example.com")
        mockCache = MockCacheAdapter()
        
        ndk.relays = [mockRelay1, mockRelay2]
        ndk.cacheAdapter = mockCache
    }
    
    override func tearDown() async throws {
        ndk = nil
        manager = nil
        mockRelay1 = nil
        mockRelay2 = nil
        mockCache = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Subscription Management Tests
    
    func testAddSubscription() async {
        // Given
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter], ndk: ndk)
        
        // When
        await manager.addSubscription(subscription)
        
        // Then
        let stats = await manager.getStats()
        XCTAssertEqual(stats.totalSubscriptions, 1)
        XCTAssertEqual(stats.activeSubscriptions, 1)
    }
    
    func testRemoveSubscription() async {
        // Given
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter], ndk: ndk)
        await manager.addSubscription(subscription)
        
        // When
        await manager.removeSubscription(subscription.id)
        
        // Then
        let stats = await manager.getStats()
        XCTAssertEqual(stats.activeSubscriptions, 0)
    }
    
    // MARK: - Subscription Grouping Tests
    
    func testSubscriptionGrouping() async {
        // Given - Two similar subscriptions that should be grouped
        let filter1 = NDKFilter(kinds: [1], authors: ["pubkey1"])
        let filter2 = NDKFilter(kinds: [1], authors: ["pubkey2"])
        
        let subscription1 = NDKSubscription(filters: [filter1], ndk: ndk)
        let subscription2 = NDKSubscription(filters: [filter2], ndk: ndk)
        
        // When
        await manager.addSubscription(subscription1)
        await manager.addSubscription(subscription2)
        
        // Wait for grouping delay
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Then
        let stats = await manager.getStats()
        XCTAssertEqual(stats.totalSubscriptions, 2)
        XCTAssertEqual(stats.groupedSubscriptions, 2)
        XCTAssertGreaterThan(stats.requestsSaved, 0)
    }
    
    func testSubscriptionGroupingWithIncompatibleFilters() async {
        // Given - Subscriptions with time constraints shouldn't be grouped
        let filter1 = NDKFilter(kinds: [1], since: 1000)
        let filter2 = NDKFilter(kinds: [1], since: 2000)
        
        let subscription1 = NDKSubscription(filters: [filter1], ndk: ndk)
        let subscription2 = NDKSubscription(filters: [filter2], ndk: ndk)
        
        // When
        await manager.addSubscription(subscription1)
        await manager.addSubscription(subscription2)
        
        // Wait for potential grouping
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then - Should execute immediately, no grouping
        let stats = await manager.getStats()
        XCTAssertEqual(stats.totalSubscriptions, 2)
        XCTAssertEqual(stats.groupedSubscriptions, 0)
    }
    
    func testSubscriptionGroupingWithSpecificRelays() async {
        // Given - Subscription with specific relays shouldn't be grouped
        var options = NDKSubscriptionOptions()
        options.relays = Set([mockRelay1])
        
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter], options: options, ndk: ndk)
        
        // When
        await manager.addSubscription(subscription)
        
        // Wait for potential grouping
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then - Should execute immediately
        let stats = await manager.getStats()
        XCTAssertEqual(stats.groupedSubscriptions, 0)
    }
    
    // MARK: - Event Processing Tests
    
    func testEventDeduplication() async {
        // Given
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter], ndk: ndk)
        await manager.addSubscription(subscription)
        
        let event = NDKEvent(
            pubkey: "testpubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            content: "test content"
        )
        event.id = "testeventid"
        
        var receivedEvents: [NDKEvent] = []
        subscription.onEvent { event in
            receivedEvents.append(event)
        }
        
        // When - Process same event twice
        await manager.processEvent(event, from: mockRelay1)
        await manager.processEvent(event, from: mockRelay2)
        
        // Then - Should only receive event once
        XCTAssertEqual(receivedEvents.count, 1)
        
        let stats = await manager.getStats()
        XCTAssertEqual(stats.eventsDeduped, 1)
    }
    
    func testEventMatchingMultipleSubscriptions() async {
        // Given - Two subscriptions that match the same event
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(authors: ["testpubkey"])
        
        let subscription1 = NDKSubscription(filters: [filter1], ndk: ndk)
        let subscription2 = NDKSubscription(filters: [filter2], ndk: ndk)
        
        await manager.addSubscription(subscription1)
        await manager.addSubscription(subscription2)
        
        var events1: [NDKEvent] = []
        var events2: [NDKEvent] = []
        
        subscription1.onEvent { events1.append($0) }
        subscription2.onEvent { events2.append($0) }
        
        let event = NDKEvent(
            pubkey: "testpubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            content: "test content"
        )
        event.id = "testeventid"
        
        // When
        await manager.processEvent(event, from: mockRelay1)
        
        // Then - Both subscriptions should receive the event
        XCTAssertEqual(events1.count, 1)
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events1.first?.id, events2.first?.id)
    }
    
    // MARK: - EOSE Handling Tests
    
    func testEOSEHandling() async {
        // Given
        let filter = NDKFilter(kinds: [1])
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        
        let subscription = NDKSubscription(filters: [filter], options: options, ndk: ndk)
        await manager.addSubscription(subscription)
        
        var eoseReceived = false
        subscription.onEOSE {
            eoseReceived = true
        }
        
        // When - Process EOSE from all relays
        await manager.processEOSE(subscriptionId: subscription.id, from: mockRelay1)
        await manager.processEOSE(subscriptionId: subscription.id, from: mockRelay2)
        
        // Then
        XCTAssertTrue(eoseReceived)
        XCTAssertTrue(subscription.eoseReceived)
        
        // Subscription should be removed due to closeOnEose
        let stats = await manager.getStats()
        XCTAssertEqual(stats.activeSubscriptions, 0)
    }
    
    func testPartialEOSETimeout() async {
        // Given
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter], ndk: ndk)
        await manager.addSubscription(subscription)
        
        var eoseReceived = false
        subscription.onEOSE {
            eoseReceived = true
        }
        
        // When - Only one relay sends EOSE (should trigger timeout logic)
        await manager.processEOSE(subscriptionId: subscription.id, from: mockRelay1)
        
        // Wait a bit for timeout logic
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Then - Should eventually emit EOSE due to 50% threshold
        XCTAssertTrue(eoseReceived)
    }
    
    // MARK: - Cache Integration Tests
    
    func testCacheFirstStrategy() async {
        // Given
        let filter = NDKFilter(kinds: [1])
        var options = NDKSubscriptionOptions()
        options.cacheStrategy = .cacheFirst
        
        let subscription = NDKSubscription(filters: [filter], options: options, ndk: ndk)
        
        let cachedEvent = NDKEvent(
            pubkey: "cachedpubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            content: "cached content"
        )
        cachedEvent.id = "cachedeventid"
        mockCache.storedEvents = [cachedEvent]
        
        var receivedEvents: [NDKEvent] = []
        subscription.onEvent { receivedEvents.append($0) }
        
        // When
        await manager.addSubscription(subscription)
        
        // Wait for cache query
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then - Should receive cached event
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.id, "cachedeventid")
        XCTAssertTrue(mockCache.queryCalled)
    }
    
    func testCacheOnlyStrategy() async {
        // Given
        let filter = NDKFilter(kinds: [1])
        var options = NDKSubscriptionOptions()
        options.cacheStrategy = .cacheOnly
        
        let subscription = NDKSubscription(filters: [filter], options: options, ndk: ndk)
        
        var eoseReceived = false
        subscription.onEOSE {
            eoseReceived = true
        }
        
        // When
        await manager.addSubscription(subscription)
        
        // Wait for cache-only execution
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then - Should immediately get EOSE from cache
        XCTAssertTrue(eoseReceived)
        XCTAssertTrue(mockCache.queryCalled)
    }
    
    // MARK: - Filter Merging Tests
    
    func testFilterMerging() async {
        // Given
        let filter1 = NDKFilter(kinds: [1], authors: ["pubkey1"])
        let filter2 = NDKFilter(kinds: [1], authors: ["pubkey2"])
        
        // When
        let merged = filter1.merged(with: filter2)
        
        // Then
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.kinds, [1])
        XCTAssertEqual(Set(merged?.authors ?? []), Set(["pubkey1", "pubkey2"]))
    }
    
    func testFilterMergingWithIncompatibleFilters() async {
        // Given - Filters with very different time constraints
        let filter1 = NDKFilter(kinds: [1], since: 1000)
        let filter2 = NDKFilter(kinds: [1], since: 5000) // 4000 seconds difference
        
        // When
        let merged = filter1.merged(with: filter2)
        
        // Then - Should not merge due to time difference
        XCTAssertNil(merged)
    }
    
    func testFilterMergingWithSmallLimits() async {
        // Given - Filters with small limits shouldn't merge
        let filter1 = NDKFilter(kinds: [1], limit: 5)
        let filter2 = NDKFilter(kinds: [1], limit: 3)
        
        // When
        let merged = filter1.merged(with: filter2)
        
        // Then - Should not merge due to small limits
        XCTAssertNil(merged)
    }
    
    // MARK: - Performance Tests
    
    func testHighVolumeSubscriptions() async {
        // Given - Many subscriptions
        let subscriptionCount = 100
        var subscriptions: [NDKSubscription] = []
        
        for i in 0..<subscriptionCount {
            let filter = NDKFilter(kinds: [1], authors: ["pubkey\(i)"])
            let subscription = NDKSubscription(filters: [filter], ndk: ndk)
            subscriptions.append(subscription)
        }
        
        // When
        let startTime = Date()
        for subscription in subscriptions {
            await manager.addSubscription(subscription)
        }
        
        // Wait for all grouping to complete
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // Then
        let stats = await manager.getStats()
        XCTAssertEqual(stats.totalSubscriptions, subscriptionCount)
        XCTAssertLessThan(duration, 2.0) // Should complete within 2 seconds
        XCTAssertGreaterThan(stats.requestsSaved, 0) // Should have saved some requests
        
        print("Processed \(subscriptionCount) subscriptions in \(duration)s")
        print("Saved \(stats.requestsSaved) requests through grouping")
        print("Average group size: \(stats.averageGroupSize)")
    }
    
    func testEventProcessingPerformance() async {
        // Given - Many subscriptions and events
        let subscriptionCount = 50
        let eventCount = 1000
        
        // Create subscriptions
        for i in 0..<subscriptionCount {
            let filter = NDKFilter(kinds: [1])
            let subscription = NDKSubscription(filters: [filter], ndk: ndk)
            await manager.addSubscription(subscription)
        }
        
        // Create events
        var events: [NDKEvent] = []
        for i in 0..<eventCount {
            let event = NDKEvent(
                pubkey: "pubkey\(i % 10)",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: 1,
                content: "content \(i)"
            )
            event.id = "event\(i)"
            events.append(event)
        }
        
        // When
        let startTime = Date()
        for event in events {
            await manager.processEvent(event, from: mockRelay1)
        }
        let endTime = Date()
        
        let duration = endTime.timeIntervalSince(startTime)
        let eventsPerSecond = Double(eventCount) / duration
        
        // Then
        let stats = await manager.getStats()
        XCTAssertLessThan(duration, 1.0) // Should process within 1 second
        XCTAssertGreaterThan(eventsPerSecond, 500) // Should handle at least 500 events/sec
        
        print("Processed \(eventCount) events in \(duration)s (\(eventsPerSecond) events/sec)")
        print("Deduped \(stats.eventsDeduped) events")
    }
    
    // MARK: - Statistics Tests
    
    func testStatisticsTracking() async {
        // Given
        let filter1 = NDKFilter(kinds: [1], authors: ["pubkey1"])
        let filter2 = NDKFilter(kinds: [1], authors: ["pubkey2"])
        let filter3 = NDKFilter(kinds: [2])
        
        let subscription1 = NDKSubscription(filters: [filter1], ndk: ndk)
        let subscription2 = NDKSubscription(filters: [filter2], ndk: ndk)
        let subscription3 = NDKSubscription(filters: [filter3], ndk: ndk)
        
        // When
        await manager.addSubscription(subscription1)
        await manager.addSubscription(subscription2)
        await manager.addSubscription(subscription3)
        
        // Wait for grouping
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        let stats = await manager.getStats()
        XCTAssertEqual(stats.totalSubscriptions, 3)
        XCTAssertEqual(stats.activeSubscriptions, 3)
        XCTAssertGreaterThan(stats.groupedSubscriptions, 0)
        XCTAssertGreaterThan(stats.requestsSaved, 0)
    }
}

// MARK: - Mock Classes

class MockRelay: NDKRelay {
    var sentMessages: [String] = []
    var isConnectedState = true
    
    override var isConnected: Bool {
        return isConnectedState
    }
    
    override func send(_ message: String) async throws {
        sentMessages.append(message)
    }
    
    override func addSubscription(_ subscription: NDKSubscription) {
        // Track subscription
    }
}

class MockCacheAdapter: NDKCacheAdapter {
    var storedEvents: [NDKEvent] = []
    var queryCalled = false
    var setEventCalled = false
    
    func query(subscription: NDKSubscription) async -> [NDKEvent] {
        queryCalled = true
        
        // Return events that match the subscription filters
        return storedEvents.filter { event in
            subscription.filters.contains { filter in
                filter.matches(event: event)
            }
        }
    }
    
    func setEvent(_ event: NDKEvent, filters: [NDKFilter], relay: NDKRelay?) async {
        setEventCalled = true
        
        // Add to stored events if not already present
        if !storedEvents.contains(where: { $0.id == event.id }) {
            storedEvents.append(event)
        }
    }
    
    func storeEvent(_ event: NDKEvent) async {
        setEventCalled = true
        
        if !storedEvents.contains(where: { $0.id == event.id }) {
            storedEvents.append(event)
        }
    }
    
    func storeProfile(_ profile: NDKUserProfile, pubkey: PublicKey) async {
        // Not implemented for these tests
    }
    
    func loadProfile(pubkey: PublicKey) async -> NDKUserProfile? {
        return nil
    }
    
    func storeUnpublishedEvent(_ event: NDKEvent, relayUrls: [RelayURL]) async {
        // Not implemented for these tests
    }
    
    func getUnpublishedEvents(relayUrl: RelayURL) async -> [NDKEvent] {
        return []
    }
    
    func removeUnpublishedEvent(eventId: EventID, relayUrl: RelayURL) async {
        // Not implemented for these tests
    }
    
    func clear() async {
        storedEvents.removeAll()
    }
    
    func stats() async -> (events: Int, profiles: Int, nip05: Int) {
        return (storedEvents.count, 0, 0)
    }
}