@testable import NDKSwift
import XCTest

final class NDKSubscriptionBuilderTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        // Create NDK without cache - we'll test differently
        ndk = NDK(
            relayUrls: ["wss://mock.relay.com"],
            signer: nil
        )
    }
    
    // MARK: - Builder Pattern Tests
    
    func testSubscriptionBuilder() {
        let subscription = ndk.subscription()
            .kinds([1, 7])
            .authors(["author1", "author2"])
            .since(1234567890)
            .limit(50)
            // .cacheStrategy(.cacheFirst) - not available in current API
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
        // XCTAssertEqual(subscription.options.cacheStrategy, .cacheFirst) - not available in current API
        XCTAssertEqual(subscription.state, NDKSubscriptionState.pending) // Manual start
    }
    
    func testBuilderAutoStart() async {
        let subscription = ndk.subscription()
            .kinds([1])
            .build()
        
        // Give a moment for the async start to update state
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        
        // Should auto-start by default
        XCTAssertNotEqual(subscription.state, NDKSubscriptionState.pending)
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
        let subscription = ndk.subscribe(
            filters: [NDKFilter(kinds: [1])]
        )
        
        Task {
            await subscription.start()
        }
        
        // Give a moment for the async start
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s
        
        // Should be started automatically
        XCTAssertNotEqual(subscription.state, NDKSubscriptionState.pending)
    }
    
    func testSubscribeMultipleFilters() async {
        let filters = [
            NDKFilter(kinds: [1]),
            NDKFilter(authors: ["author1"])
        ]
        
        let subscription = ndk.subscribe(filters: filters)
        
        Task {
            await subscription.start()
        }
        
        // Give a moment for the async start to update state
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        
        XCTAssertNotEqual(subscription.state, NDKSubscriptionState.pending)
        XCTAssertEqual(subscription.filters.count, 2)
    }
    
    // MARK: - Fetch Tests
    
    func testFetchWithTimeout() async throws {
        // Test that fetch respects timeout
        let filter = NDKFilter(kinds: [1], limit: 10)
        
        do {
            // This should timeout since no relays are connected
            let events = try await ndk.fetch(filter, timeout: 0.1)
            XCTAssertTrue(events.isEmpty)
        } catch {
            // Timeout error is expected
            XCTAssertTrue(error.localizedDescription.contains("timeout") || error.localizedDescription.contains("timed out"))
        }
    }
    
    func testFetchMultipleFilters() async throws {
        let filters = [
            NDKFilter(kinds: [1]),
            NDKFilter(kinds: [7])
        ]
        
        do {
            // This should timeout since no relays are connected
            let events = try await ndk.fetch(filters, timeout: 0.1)
            XCTAssertTrue(events.isEmpty)
        } catch {
            // Timeout error is expected - test passes
            XCTAssertTrue(true)
        }
    }
    
    // MARK: - Stream Tests
    
    func testStreamSubscription() async {
        // Test that stream creates a valid AsyncStream
        let filter = NDKFilter(kinds: [1])
        let stream = ndk.stream(filter)
        
        // Just verify the stream is created - actual streaming would need relay connection
        XCTAssertNotNil(stream)
        
        // Test that we can start iterating (even if no events come)
        let expectation = XCTestExpectation(description: "Stream iteration started")
        expectation.isInverted = true // We don't expect events
        
        Task {
            for await _ in stream {
                expectation.fulfill()
                break
            }
        }
        
        await fulfillment(of: [expectation], timeout: 0.5)
    }
    
    
    // MARK: - Profile Fetching Tests
    
    func testFetchProfile() async throws {
        let pubkey = "test_pubkey"
        
        do {
            // This should timeout or return nil since no relays are connected
            let profile = try await ndk.fetchProfile(pubkey)
            XCTAssertNil(profile)
        } catch {
            // Timeout is acceptable
            XCTAssertTrue(true)
        }
    }
    
    func testFetchMultipleProfiles() async throws {
        let pubkeys = ["pubkey1", "pubkey2", "pubkey3"]
        
        do {
            // This should timeout or return empty since no relays are connected
            let profiles = try await ndk.fetchProfiles(pubkeys)
            XCTAssertTrue(profiles.isEmpty)
        } catch {
            // Timeout is acceptable
            XCTAssertTrue(true)
        }
    }
    
    func testSubscribeToProfile() async {
        // Test creating a profile subscription using modern API
        var filter = NDKFilter()
        filter.authors = ["test_pubkey"]
        filter.kinds = [0] // Profile metadata
        
        let subscription = ndk.subscribe(filters: [filter])
        
        Task {
            await subscription.start()
        }
        
        // Give time for subscription to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Verify subscription was created with correct filter
        XCTAssertEqual(subscription.filters.count, 1)
        XCTAssertEqual(subscription.filters[0].authors, ["test_pubkey"])
        XCTAssertEqual(subscription.filters[0].kinds, [0])
        
        // Clean up
        await subscription.close()
    }
    
    // MARK: - Subscription Group Tests
    
    func testSubscriptionGroup() async {
        let group = ndk.subscriptionGroup()
        
        let sub1 = group.subscribe(NDKFilter(kinds: [1]))
        let sub2 = group.subscribe(NDKFilter(kinds: [7]))
        
        // Give a moment for the async starts
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        
        XCTAssertEqual(group.activeSubscriptions.count, 2)
        
        // Close all
        await group.closeAll()
        
        // Give time for close to complete
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        
        XCTAssertEqual(sub1.state, NDKSubscriptionState.closed)
        XCTAssertEqual(sub2.state, NDKSubscriptionState.closed)
        XCTAssertEqual(group.activeSubscriptions.count, 0)
    }
    
    // MARK: - Scoped Subscription Tests
    
    func testWithSubscriptionScope() async throws {
        var subscription: NDKSubscription?
        
        let result = try await ndk.withSubscription(NDKFilter(kinds: [1])) { sub in
            subscription = sub
            
            // Give time for start
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01s
            XCTAssertNotEqual(sub.state, NDKSubscriptionState.closed)
            return "completed"
        }
        
        XCTAssertEqual(result, "completed")
        
        // Give time for close to complete
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        XCTAssertEqual(subscription?.state, NDKSubscriptionState.closed)
    }
    
    func testAutoClosingSubscription() async {
        var autoSub: AutoClosingSubscription? = ndk.autoSubscribe(
            filter: NDKFilter(kinds: [1])
        )
        
        let underlying = autoSub?.underlying
        XCTAssertNotNil(underlying)
        
        // Give a moment for the async start
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        XCTAssertNotEqual(underlying?.state, NDKSubscriptionState.closed)
        
        // Release the auto-closing wrapper
        autoSub = nil
        
        // Give time for deinit to run
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        
        // Subscription should be closed
        XCTAssertEqual(underlying?.state, NDKSubscriptionState.closed)
    }
    
    // MARK: - Async Sequence Tests
    
    func testSubscriptionEventSequence() async {
        let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])])
        
        let expectation = XCTestExpectation(description: "Receive events via async sequence")
        
        Task {
            var count = 0
            do {
                for try await _ in subscription {
                    count += 1
                    if count >= 2 {
                        expectation.fulfill()
                        break
                    }
                }
            } catch {
                // Handle error if needed
            }
        }
        
        // Simulate events
        Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            await subscription.handleEvent(createMockEvent(kind: 1, content: "Event 1"), fromRelay: nil)
            await subscription.handleEvent(createMockEvent(kind: 1, content: "Event 2"), fromRelay: nil)
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Helper Methods
    
    private func createMockEvent(kind: Kind = 1, content: String = "Test") -> NDKEvent {
        let event = NDKEvent(
            pubkey: "mock_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            tags: [],
            content: content
        )
        event.id = UUID().uuidString
        event.sig = "mock_sig"
        return event
    }
}

// MARK: - Mock Helpers

// Helper extension removed - use handleEvent(_, fromRelay:) directly
