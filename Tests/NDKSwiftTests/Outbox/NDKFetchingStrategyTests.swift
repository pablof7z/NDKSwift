import XCTest
@testable import NDKSwift

final class NDKFetchingStrategyTests: XCTestCase {
    var mockNDK: MockNDKForFetching!
    var tracker: NDKOutboxTracker!
    var ranker: NDKRelayRanker!
    var selector: NDKRelaySelector!
    var strategy: NDKFetchingStrategy!
    
    override func setUp() async throws {
        mockNDK = MockNDKForFetching()
        tracker = NDKOutboxTracker(ndk: mockNDK)
        ranker = NDKRelayRanker(ndk: mockNDK, tracker: tracker)
        selector = NDKRelaySelector(ndk: mockNDK, tracker: tracker, ranker: ranker)
        strategy = NDKFetchingStrategy(ndk: mockNDK, selector: selector, ranker: ranker)
    }
    
    func testFetchEventsSuccess() async throws {
        // Set up mock relays with events
        let event1 = createTestEvent(id: "event1", content: "Content 1")
        let event2 = createTestEvent(id: "event2", content: "Content 2")
        
        let relay1 = MockFetchRelay(
            url: "wss://relay1.com",
            events: [event1, event2]
        )
        let relay2 = MockFetchRelay(
            url: "wss://relay2.com",
            events: [event1] // Duplicate event
        )
        
        mockNDK.mockRelays = [relay1, relay2]
        
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://relay1.com", "wss://relay2.com"]
        )
        
        let filter = NDKFilter(
            authors: ["author1"],
            kinds: [1]
        )
        
        let events = try await strategy.fetchEvents(filter: filter)
        
        // Should deduplicate
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.contains { $0.id == "event1" })
        XCTAssertTrue(events.contains { $0.id == "event2" })
    }
    
    func testFetchWithMinimumRelays() async throws {
        let relay1 = MockFetchRelay(
            url: "wss://relay1.com",
            shouldFail: false,
            events: [createTestEvent()]
        )
        let relay2 = MockFetchRelay(
            url: "wss://relay2.com",
            shouldFail: true
        )
        let relay3 = MockFetchRelay(
            url: "wss://relay3.com",
            shouldFail: true
        )
        
        mockNDK.mockRelays = [relay1, relay2, relay3]
        
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://relay1.com", "wss://relay2.com", "wss://relay3.com"]
        )
        
        let filter = NDKFilter(authors: ["author1"])
        
        // Require 2 successful relays but only 1 will succeed
        let config = OutboxFetchConfig(minSuccessfulRelays: 2)
        
        do {
            _ = try await strategy.fetchEvents(filter: filter, config: config)
            XCTFail("Should have thrown insufficient relays error")
        } catch let error as FetchError {
            if case .insufficientRelays(let required, let successful) = error {
                XCTAssertEqual(required, 2)
                XCTAssertEqual(successful, 1)
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testFetchTimeout() async throws {
        let slowRelay = MockFetchRelay(
            url: "wss://slow.relay",
            responseDelay: 2.0
        )
        
        mockNDK.mockRelays = [slowRelay]
        
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://slow.relay"]
        )
        
        let filter = NDKFilter(authors: ["author1"])
        let config = OutboxFetchConfig(timeoutInterval: 0.1) // 100ms timeout
        
        do {
            _ = try await strategy.fetchEvents(filter: filter, config: config)
            XCTFail("Should have timed out")
        } catch {
            // Expected timeout
        }
    }
    
    func testSubscriptionCreation() async throws {
        let relay1 = MockFetchRelay(url: "wss://relay1.com")
        let relay2 = MockFetchRelay(url: "wss://relay2.com")
        
        mockNDK.mockRelays = [relay1, relay2]
        
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://relay1.com", "wss://relay2.com"]
        )
        
        let filters = [
            NDKFilter(authors: ["author1"], kinds: [1])
        ]
        
        var receivedEvents: [NDKEvent] = []
        
        let subscription = try await strategy.subscribe(
            filters: filters,
            eventHandler: { event in
                receivedEvents.append(event)
            }
        )
        
        XCTAssertNotNil(subscription)
        XCTAssertEqual(subscription.targetRelays.count, 2)
        
        // Simulate events
        let newEvent = createTestEvent(id: "new_event")
        relay1.simulateEvent(newEvent)
        
        // Give time for event to propagate
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.id, "new_event")
        
        // Clean up
        await strategy.closeSubscription(subscription.id)
    }
    
    func testSubscriptionDeduplication() async throws {
        let relay1 = MockFetchRelay(url: "wss://relay1.com")
        let relay2 = MockFetchRelay(url: "wss://relay2.com")
        
        mockNDK.mockRelays = [relay1, relay2]
        
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://relay1.com", "wss://relay2.com"]
        )
        
        var receivedEvents: [NDKEvent] = []
        
        let subscription = try await strategy.subscribe(
            filters: [NDKFilter(authors: ["author1"])],
            eventHandler: { event in
                receivedEvents.append(event)
            }
        )
        
        // Both relays send the same event
        let duplicateEvent = createTestEvent(id: "duplicate_event")
        relay1.simulateEvent(duplicateEvent)
        relay2.simulateEvent(duplicateEvent)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should only receive once
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(subscription.eventCount, 1)
        
        await strategy.closeSubscription(subscription.id)
    }
    
    func testActiveSubscriptions() async throws {
        let relay = MockFetchRelay(url: "wss://relay.com")
        mockNDK.mockRelays = [relay]
        
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://relay.com"]
        )
        
        // Create multiple subscriptions
        let sub1 = try await strategy.subscribe(
            filters: [NDKFilter(authors: ["author1"])],
            eventHandler: { _ in }
        )
        
        let sub2 = try await strategy.subscribe(
            filters: [NDKFilter(kinds: [1])],
            eventHandler: { _ in }
        )
        
        let activeSubscriptions = await strategy.getActiveSubscriptions()
        XCTAssertEqual(activeSubscriptions.count, 2)
        
        // Close one
        await strategy.closeSubscription(sub1.id)
        
        let remainingSubscriptions = await strategy.getActiveSubscriptions()
        XCTAssertEqual(remainingSubscriptions.count, 1)
        XCTAssertEqual(remainingSubscriptions.first?.id, sub2.id)
        
        await strategy.closeSubscription(sub2.id)
    }
    
    func testRelaySelectionIntegration() async throws {
        // Set up complex relay scenario
        await tracker.track(
            pubkey: "user",
            readRelays: ["wss://user-read.relay"]
        )
        
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://author1-read.relay"]
        )
        
        await tracker.track(
            pubkey: "author2",
            readRelays: ["wss://author2-read.relay", "wss://common.relay"]
        )
        
        await tracker.track(
            pubkey: "author3",
            readRelays: ["wss://common.relay"]
        )
        
        // Mock all relays
        let userRelay = MockFetchRelay(url: "wss://user-read.relay")
        let author1Relay = MockFetchRelay(url: "wss://author1-read.relay")
        let author2Relay = MockFetchRelay(url: "wss://author2-read.relay")
        let commonRelay = MockFetchRelay(url: "wss://common.relay")
        
        mockNDK.mockRelays = [userRelay, author1Relay, author2Relay, commonRelay]
        mockNDK.mockSigner = MockSigner(publicKey: "user")
        
        let filter = NDKFilter(
            authors: ["author1", "author2", "author3"],
            kinds: [1]
        )
        
        _ = try await strategy.fetchEvents(filter: filter)
        
        // Verify relay selection worked correctly
        XCTAssertTrue(userRelay.wasQueried)
        XCTAssertTrue(author1Relay.wasQueried)
        XCTAssertTrue(commonRelay.wasQueried)
        // author2Relay might or might not be queried depending on ranking
    }
    
    // MARK: - Helper Methods
    
    private func createTestEvent(
        id: String = UUID().uuidString,
        pubkey: String = "author1",
        content: String = "Test content"
    ) -> NDKEvent {
        return NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: content,
            sig: "test_sig"
        )
    }
}

// MARK: - Mock Classes

class MockNDKForFetching: NDK {
    var mockRelays: [MockFetchRelay] = []
    var mockSigner: NDKSigner?
    
    override var relayPool: NDKRelayPool {
        return MockRelayPoolForFetching(mockRelays: mockRelays)
    }
    
    override var signer: NDKSigner? {
        get { mockSigner }
        set { mockSigner = newValue }
    }
}

class MockRelayPoolForFetching: NDKRelayPool {
    let mockRelays: [MockFetchRelay]
    
    init(mockRelays: [MockFetchRelay]) {
        self.mockRelays = mockRelays
        super.init()
    }
    
    override func relay(for url: String) -> NDKRelay? {
        return mockRelays.first { $0.url == url }
    }
    
    override func addRelay(url: String) async -> NDKRelay? {
        return mockRelays.first { $0.url == url }
    }
}

class MockFetchRelay: NDKRelay {
    let shouldFail: Bool
    let responseDelay: TimeInterval
    var events: [NDKEvent]
    var wasQueried = false
    
    private var activeSubscriptions: [String: NDKSubscription] = [:]
    
    init(
        url: String,
        shouldFail: Bool = false,
        responseDelay: TimeInterval = 0,
        events: [NDKEvent] = []
    ) {
        self.shouldFail = shouldFail
        self.responseDelay = responseDelay
        self.events = events
        super.init(url: url)
    }
    
    override func fetchEvents(filter: NDKFilter) async throws -> [NDKEvent] {
        wasQueried = true
        
        if responseDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        
        if shouldFail {
            throw FetchError.relayError(url, "Mock relay error")
        }
        
        // Filter events based on filter
        return events.filter { event in
            filterMatches(filter: filter, event: event)
        }
    }
    
    override func subscribe(
        filters: [NDKFilter],
        eventHandler: @escaping (NDKEvent) -> Void
    ) -> NDKSubscription {
        var options = NDKSubscriptionOptions()
        options.relays = Set([self])
        
        let subscription = NDKSubscription(
            filters: filters,
            options: options,
            ndk: nil
        )
        
        subscription.onEvent(eventHandler)
        
        activeSubscriptions[subscription.id] = subscription
        
        return subscription
    }
    
    func simulateEvent(_ event: NDKEvent) {
        for subscription in activeSubscriptions.values {
            if subscription.filters.contains(where: { filter in
                filterMatches(filter: filter, event: event)
            }) {
                subscription.handleEvent(event, fromRelay: self)
            }
        }
    }
    
    private func filterMatches(filter: NDKFilter, event: NDKEvent) -> Bool {
        if let authors = filter.authors, !authors.contains(event.pubkey) {
            return false
        }
        
        if let kinds = filter.kinds, !kinds.contains(event.kind) {
            return false
        }
        
        if let ids = filter.ids, !ids.contains(event.id ?? "") {
            return false
        }
        
        return true
    }
}

// Remove MockSubscription class - we'll use the real NDKSubscription