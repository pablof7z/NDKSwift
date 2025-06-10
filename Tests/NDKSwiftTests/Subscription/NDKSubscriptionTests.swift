@testable import NDKSwift
import XCTest

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

    func testEventHandling() async {
        let filter = NDKFilter(kinds: [1])
        let subscription = NDKSubscription(filters: [filter])

        // Create a matching event
        let event = NDKEvent(
            pubkey: "test123",
            createdAt: 12345,
            kind: 1,
            content: "Test message"
        )
        event.id = "event123"

        // Handle event in background
        Task {
            subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
            subscription.handleEOSE()
        }

        // Collect events using AsyncStream
        var receivedEvents: [NDKEvent] = []
        for await update in subscription.updates {
            switch update {
            case .event(let event):
                receivedEvents.append(event)
            case .eose:
                break
            case .error:
                XCTFail("Unexpected error")
            }
        }

        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.id, "event123")
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

    func testEOSEHandling() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])

        XCTAssertFalse(subscription.eoseReceived)

        Task {
            subscription.handleEOSE()
        }

        // Wait for EOSE using update stream
        for await update in subscription.updates {
            if case .eose = update {
                break
            }
        }

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
        for i in 1 ... 3 {
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

    // MARK: - Subscription merging was removed in simplification
    /*
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
    */

    func testAsyncStreamAPI() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])

        Task {
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

        var receivedEvent: NDKEvent?
        var receivedEOSE = false
        
        for await update in subscription.updates {
            switch update {
            case .event(let event):
                receivedEvent = event
            case .eose:
                receivedEOSE = true
                break
            case .error:
                XCTFail("Unexpected error")
            }
        }
        
        XCTAssertEqual(receivedEvent?.id, "test123")
        XCTAssertTrue(receivedEOSE)
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

    func testAsyncSequenceIteration() async {
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
            subscription.close() // Close to end iteration
        }

        var receivedEvents: [NDKEvent] = []
        for await event in subscription {
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

    func testBackwardCompatibility() async {
        // Test that deprecated callback methods still work
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])
        
        var eventReceived = false
        var eoseReceived = false
        
        subscription.onEvent { _ in
            eventReceived = true
        }
        
        subscription.onEOSE {
            eoseReceived = true
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
        
        // Give callbacks time to execute
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        XCTAssertTrue(eventReceived)
        XCTAssertTrue(eoseReceived)
    }
}
