import XCTest
@testable import NDKSwift

final class NDKSubscriptionBuilderTests: XCTestCase {
    var ndk: NDK!
    var mockRelayPool: MockRelayPool!
    
    override func setUp() async throws {
        mockRelayPool = MockRelayPool()
        ndk = NDK(relayPool: mockRelayPool, signer: nil)
    }
    
    // MARK: - Builder Pattern Tests
    
    func testSubscriptionBuilder() {
        let subscription = ndk.subscription()
            .kinds([1, 7])
            .authors(["author1", "author2"])
            .since(1234567890)
            .limit(50)
            .cacheStrategy(.cacheFirst)
            .closeOnEose()
            .manualStart()
            .build()
        
        XCTAssertEqual(subscription.filters.count, 1)
        let filter = subscription.filters[0]
        XCTAssertEqual(filter.kinds, [1, 7])
        XCTAssertEqual(filter.authors, ["author1", "author2"])
        XCTAssertEqual(filter.since, 1234567890)
        XCTAssertEqual(filter.limit, 50)
        XCTAssertEqual(subscription.options.closeOnEose, true)
        XCTAssertEqual(subscription.options.cacheStrategy, .cacheFirst)
        XCTAssertEqual(subscription.state, .pending) // Manual start
    }
    
    func testBuilderAutoStart() {
        let subscription = ndk.subscription()
            .kinds([1])
            .build()
        
        // Should auto-start by default
        XCTAssertNotEqual(subscription.state, .pending)
    }
    
    func testBuilderWithMultipleFilters() {
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(authors: ["author1"])
        
        let subscription = ndk.subscription()
            .filter(filter1)
            .filter(filter2)
            .build()
        
        XCTAssertEqual(subscription.filters.count, 2)
    }
    
    func testBuilderHashtagFilter() {
        let subscription = ndk.subscription()
            .hashtags(["nostr", "Bitcoin"])
            .build()
        
        XCTAssertEqual(subscription.filters.count, 1)
        let filter = subscription.filters[0]
        XCTAssertEqual(filter.tagFilter("t"), ["nostr", "bitcoin"])
    }
    
    // MARK: - Auto-Start Subscribe Tests
    
    func testSubscribeWithAutoStart() async {
        var receivedEvents: [NDKEvent] = []
        
        let subscription = ndk.subscribe(
            filter: NDKFilter(kinds: [1])
        ) { event in
            receivedEvents.append(event)
        }
        
        // Should be started automatically
        XCTAssertNotEqual(subscription.state, .pending)
        
        // Simulate receiving an event
        let event = createMockEvent(kind: 1)
        await subscription.handleEvent(event)
        
        XCTAssertEqual(receivedEvents.count, 1)
    }
    
    func testSubscribeMultipleFilters() async {
        var receivedEvents: [NDKEvent] = []
        
        let filters = [
            NDKFilter(kinds: [1]),
            NDKFilter(authors: ["author1"])
        ]
        
        let subscription = ndk.subscribe(filters: filters) { event in
            receivedEvents.append(event)
        }
        
        XCTAssertNotEqual(subscription.state, .pending)
        XCTAssertEqual(subscription.filters.count, 2)
    }
    
    // MARK: - Fetch Tests
    
    func testFetchWithTimeout() async throws {
        let expectation = XCTestExpectation(description: "Fetch completes")
        
        Task {
            do {
                let filter = NDKFilter(kinds: [1], limit: 10)
                let events = try await ndk.fetch(filter, timeout: 1.0)
                XCTAssertTrue(events.isEmpty) // Mock doesn't return events
                expectation.fulfill()
            } catch {
                if case NDKUnifiedError.network(.timeout) = error {
                    // Expected timeout
                    expectation.fulfill()
                } else {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testFetchMultipleFilters() async throws {
        let filters = [
            NDKFilter(kinds: [1]),
            NDKFilter(kinds: [7])
        ]
        
        let events = try await ndk.fetch(filters, timeout: 1.0)
        XCTAssertNotNil(events) // Just verify it doesn't crash
    }
    
    // MARK: - Stream Tests
    
    func testStreamSubscription() async {
        let filter = NDKFilter(kinds: [1])
        let stream = ndk.stream(filter)
        
        let expectation = XCTestExpectation(description: "Receive streamed event")
        
        Task {
            var count = 0
            for await event in stream {
                count += 1
                if count >= 1 {
                    expectation.fulfill()
                    break
                }
            }
        }
        
        // Simulate event after a delay
        Task {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            // In real implementation, events would come from relays
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Subscribe Once Tests
    
    func testSubscribeOnce() async {
        let expectation = XCTestExpectation(description: "Receive limited events")
        var receivedEvents: [NDKEvent] = []
        
        let subscription = ndk.subscribeOnce(
            NDKFilter(kinds: [1]),
            limit: 3
        ) { events in
            receivedEvents = events
            expectation.fulfill()
        }
        
        // Simulate receiving events
        Task {
            for i in 1...5 {
                let event = createMockEvent(kind: 1, content: "Event \(i)")
                await subscription.handleEvent(event)
            }
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedEvents.count, 3)
        XCTAssertEqual(subscription.state, .closed)
    }
    
    // MARK: - Profile Fetching Tests
    
    func testFetchProfile() async throws {
        let pubkey = "test_pubkey"
        
        // In a real test, we'd mock the relay responses
        let profile = try await ndk.fetchProfile(pubkey)
        
        // Just verify it doesn't crash
        XCTAssertNil(profile) // Mock doesn't return real data
    }
    
    func testFetchMultipleProfiles() async throws {
        let pubkeys = ["pubkey1", "pubkey2", "pubkey3"]
        
        let profiles = try await ndk.fetchProfiles(pubkeys)
        
        XCTAssertNotNil(profiles)
        XCTAssertTrue(profiles.isEmpty) // Mock doesn't return real data
    }
    
    func testSubscribeToProfile() async {
        var receivedProfile: NDKUserProfile?
        let expectation = XCTestExpectation(description: "Profile update received")
        
        let subscription = ndk.subscribeToProfile("test_pubkey") { profile in
            receivedProfile = profile
            expectation.fulfill()
        }
        
        // Simulate profile event
        let profileData = """
        {
            "name": "Test User",
            "about": "Test bio",
            "picture": "https://example.com/pic.jpg"
        }
        """
        
        let event = NDKEvent(
            pubkey: "test_pubkey",
            kind: 0,
            tags: [],
            content: profileData
        )
        
        await subscription.handleEvent(event)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertNotNil(receivedProfile)
        XCTAssertEqual(receivedProfile?.name, "Test User")
    }
    
    // MARK: - Subscription Group Tests
    
    func testSubscriptionGroup() async {
        let group = ndk.subscriptionGroup()
        
        var events1: [NDKEvent] = []
        var events2: [NDKEvent] = []
        
        let sub1 = group.subscribe(NDKFilter(kinds: [1])) { event in
            events1.append(event)
        }
        
        let sub2 = group.subscribe(NDKFilter(kinds: [7])) { event in
            events2.append(event)
        }
        
        XCTAssertEqual(group.activeSubscriptions.count, 2)
        
        // Close all
        group.closeAll()
        
        XCTAssertEqual(sub1.state, .closed)
        XCTAssertEqual(sub2.state, .closed)
        XCTAssertEqual(group.activeSubscriptions.count, 0)
    }
    
    // MARK: - Scoped Subscription Tests
    
    func testWithSubscriptionScope() async throws {
        var subscription: NDKSubscription?
        
        let result = try await ndk.withSubscription(NDKFilter(kinds: [1])) { sub in
            subscription = sub
            XCTAssertNotEqual(sub.state, .closed)
            return "completed"
        }
        
        XCTAssertEqual(result, "completed")
        XCTAssertEqual(subscription?.state, .closed)
    }
    
    func testAutoClosingSubscription() {
        var autoSub: AutoClosingSubscription? = ndk.autoSubscribe(
            filter: NDKFilter(kinds: [1])
        )
        
        let underlying = autoSub?.underlying
        XCTAssertNotNil(underlying)
        XCTAssertNotEqual(underlying?.state, .closed)
        
        // Release the auto-closing wrapper
        autoSub = nil
        
        // Subscription should be closed
        XCTAssertEqual(underlying?.state, .closed)
    }
    
    // MARK: - Async Sequence Tests
    
    func testSubscriptionEventSequence() async {
        let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])])
        
        let expectation = XCTestExpectation(description: "Receive events via async sequence")
        
        Task {
            var count = 0
            for await event in subscription.events {
                count += 1
                if count >= 2 {
                    expectation.fulfill()
                    break
                }
            }
        }
        
        // Simulate events
        Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            await subscription.handleEvent(createMockEvent(kind: 1, content: "Event 1"))
            await subscription.handleEvent(createMockEvent(kind: 1, content: "Event 2"))
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Helper Methods
    
    private func createMockEvent(kind: Kind = 1, content: String = "Test") -> NDKEvent {
        return NDKEvent(
            id: UUID().uuidString,
            pubkey: "mock_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            tags: [],
            content: content,
            sig: "mock_sig"
        )
    }
}

// MARK: - Mock Helpers

extension NDKSubscription {
    /// Helper for tests to simulate receiving events
    func handleEvent(_ event: NDKEvent) async {
        await handleMessage(.event(subscriptionId: id, event: event), from: NDKRelay(url: "wss://mock.relay"))
    }
}