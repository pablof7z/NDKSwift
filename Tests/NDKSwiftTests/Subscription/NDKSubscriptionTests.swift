import XCTest
@testable import NDKSwift

final class NDKSubscriptionTests: XCTestCase {
    
    func testSubscriptionCreation() {
        let filters = [NDKFilter(kinds: [1], limit: 10)]
        let subscription = NDKSubscription(filters: filters)
        
        XCTAssertFalse(subscription.id.isEmpty)
        XCTAssertEqual(subscription.filters.count, 1)
        XCTAssertFalse(subscription.isActive)
        XCTAssertFalse(subscription.isClosed)
        XCTAssertFalse(subscription.eoseReceived)
        XCTAssertTrue(subscription.events.isEmpty)
    }
    
    func testSubscriptionOptions() {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        options.cacheStrategy = .cacheOnly
        options.limit = 50
        options.timeout = 30.0
        
        let subscription = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options
        )
        
        XCTAssertTrue(subscription.options.closeOnEose)
        XCTAssertEqual(subscription.options.cacheStrategy, .cacheOnly)
        XCTAssertEqual(subscription.options.limit, 50)
        XCTAssertEqual(subscription.options.timeout, 30.0)
    }
    
    func testEventHandling() {
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter])
        
        let expectation = XCTestExpectation(description: "Event received")
        
        subscription.onEvent { event in
            expectation.fulfill()
        }
        
        // Create a matching event
        let event = NDKEvent(
            pubkey: "test123",
            createdAt: 12345,
            kind: 1,
            content: "Test message"
        )
        event.id = "event123"
        
        subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(subscription.events.count, 1)
        XCTAssertEqual(subscription.events.first?.id, "event123")
    }
    
    func testEventDeduplication() {
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter])
        
        let event = NDKEvent(
            pubkey: "test123",
            createdAt: 12345,
            kind: 1,
            content: "Test message"
        )
        event.id = "event123"
        
        // Add same event twice
        subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        
        // Should only have one event
        XCTAssertEqual(subscription.events.count, 1)
    }
    
    func testFilterMatching() {
        let filter = NDKFilter(authors: ["alice"], kinds: [1])
        let subscription = NDKSubscription(filters: [filter])
        
        // Matching event
        let matchingEvent = NDKEvent(
            pubkey: "alice",
            createdAt: 12345,
            kind: 1,
            content: "From Alice"
        )
        matchingEvent.id = "event1"
        
        // Non-matching event (wrong author)
        let nonMatchingEvent = NDKEvent(
            pubkey: "bob",
            createdAt: 12345,
            kind: 1,
            content: "From Bob"
        )
        nonMatchingEvent.id = "event2"
        
        subscription.handleEvent(matchingEvent, fromRelay: nil as NDKRelay?)
        subscription.handleEvent(nonMatchingEvent, fromRelay: nil as NDKRelay?)
        
        // Should only have the matching event
        XCTAssertEqual(subscription.events.count, 1)
        XCTAssertEqual(subscription.events.first?.pubkey, "alice")
    }
    
    func testEOSEHandling() {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])
        
        let expectation = XCTestExpectation(description: "EOSE received")
        
        subscription.onEOSE {
            expectation.fulfill()
        }
        
        XCTAssertFalse(subscription.eoseReceived)
        
        subscription.handleEOSE()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(subscription.eoseReceived)
    }
    
    func testCloseOnEOSE() {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        
        let subscription = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options
        )
        
        subscription.start()
        XCTAssertTrue(subscription.isActive)
        XCTAssertFalse(subscription.isClosed)
        
        subscription.handleEOSE()
        
        XCTAssertFalse(subscription.isActive)
        XCTAssertTrue(subscription.isClosed)
    }
    
    func testSubscriptionLimit() {
        var options = NDKSubscriptionOptions()
        options.limit = 2
        
        let subscription = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options
        )
        
        subscription.start()
        
        // Add events up to limit
        for i in 1...3 {
            let event = NDKEvent(
                pubkey: "test",
                createdAt: Int64(i),
                kind: 1,
                content: "Event \(i)"
            )
            event.id = "event\(i)"
            
            subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        }
        
        // Should close after limit is reached
        XCTAssertEqual(subscription.events.count, 2)
        XCTAssertTrue(subscription.isClosed)
    }
    
    func testSubscriptionMerging() {
        // Test merging subscriptions with compatible filters (same kinds)
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(kinds: [1], limit: 10)
        
        let subscription1 = NDKSubscription(filters: [filter1])
        let subscription2 = NDKSubscription(filters: [filter2])
        
        XCTAssertTrue(subscription1.canMerge(with: subscription2))
        
        let merged = subscription1.merge(with: subscription2)
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.filters.count, 2)
    }
    
    func testSubscriptionMergingIncompatible() {
        var options1 = NDKSubscriptionOptions()
        options1.closeOnEose = true
        
        var options2 = NDKSubscriptionOptions()
        options2.closeOnEose = false
        
        let subscription1 = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options1
        )
        
        let subscription2 = NDKSubscription(
            filters: [NDKFilter(kinds: [2])],
            options: options2
        )
        
        XCTAssertFalse(subscription1.canMerge(with: subscription2))
        XCTAssertNil(subscription1.merge(with: subscription2))
    }
    
    func testCallbackIntegration() {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])
        
        let eventExpectation = XCTestExpectation(description: "Event via callback")
        let eoseExpectation = XCTestExpectation(description: "EOSE via callback")
        
        subscription.onEvent { _ in
            eventExpectation.fulfill()
        }
        
        subscription.onEOSE {
            eoseExpectation.fulfill()
        }
        
        let event = NDKEvent(
            pubkey: "test",
            createdAt: 12345,
            kind: 1,
            content: "Test"
        )
        event.id = "test123"
        
        subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        subscription.handleEOSE()
        
        wait(for: [eventExpectation, eoseExpectation], timeout: 1.0)
    }
    
    func testSubscriptionLifecycle() {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])
        
        // Initial state
        XCTAssertFalse(subscription.isActive)
        XCTAssertFalse(subscription.isClosed)
        
        // Start subscription
        subscription.start()
        XCTAssertTrue(subscription.isActive)
        XCTAssertFalse(subscription.isClosed)
        
        // Close subscription
        subscription.close()
        XCTAssertFalse(subscription.isActive)
        XCTAssertTrue(subscription.isClosed)
        
        // Cannot restart after close
        subscription.start()
        XCTAssertFalse(subscription.isActive)
        XCTAssertTrue(subscription.isClosed)
    }
    
    func testCacheStrategies() {
        // Test different cache strategies
        let strategies: [NDKCacheStrategy] = [.cacheFirst, .cacheOnly, .relayOnly, .parallel]
        
        for strategy in strategies {
            var options = NDKSubscriptionOptions()
            options.cacheStrategy = strategy
            
            let subscription = NDKSubscription(
                filters: [NDKFilter(kinds: [1])],
                options: options
            )
            
            XCTAssertEqual(subscription.options.cacheStrategy, strategy)
        }
    }
    
    func testAsyncEventStream() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])
        
        Task {
            // Give a small delay before sending events
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            
            let event = NDKEvent(
                pubkey: "test",
                createdAt: 12345,
                kind: 1,
                content: "Test"
            )
            event.id = "test123"
            
            subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
            subscription.handleEOSE()
        }
        
        var receivedEvents: [NDKEvent] = []
        for await event in subscription.eventStream() {
            receivedEvents.append(event)
        }
        
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.id, "test123")
    }
    
    func testAsyncWaitForEOSE() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])
        
        Task {
            // Give a small delay before sending EOSE
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            subscription.handleEOSE()
        }
        
        await subscription.waitForEOSE()
        XCTAssertTrue(subscription.eoseReceived)
    }
    
    func testDelegatePattern() {
        class TestDelegate: NDKSubscriptionDelegate {
            var receivedEvent: NDKEvent?
            var receivedEOSE = false
            var receivedError: Error?
            
            func subscription(_ subscription: NDKSubscription, didReceiveEvent event: NDKEvent) {
                receivedEvent = event
            }
            
            func subscription(_ subscription: NDKSubscription, didReceiveEOSE: Void) {
                receivedEOSE = true
            }
            
            func subscription(_ subscription: NDKSubscription, didReceiveError error: Error) {
                receivedError = error
            }
        }
        
        let delegate = TestDelegate()
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])
        subscription.delegate = delegate
        
        let event = NDKEvent(
            pubkey: "test",
            createdAt: 12345,
            kind: 1,
            content: "Test"
        )
        event.id = "test123"
        
        subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        subscription.handleEOSE()
        
        XCTAssertEqual(delegate.receivedEvent?.id, "test123")
        XCTAssertTrue(delegate.receivedEOSE)
    }
}