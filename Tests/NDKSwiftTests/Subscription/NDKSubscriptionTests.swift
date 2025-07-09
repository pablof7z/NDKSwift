@testable import NDKSwift
import XCTest

final class NDKSubscriptionTests: XCTestCase {
    func testSubscriptionCreation() async {
        let filters = [NDKFilter(kinds: [1], limit: 10)]
        let subscription = NDKSubscription(filters: filters)

        XCTAssertFalse(subscription.id.isEmpty)
        XCTAssertEqual(subscription.filters.count, 1)
        let isActive = await subscription.isActive
        XCTAssertFalse(isActive)
        let isClosed = await subscription.isClosed
        XCTAssertFalse(isClosed)
        let eoseReceived = await subscription.eoseReceived
        XCTAssertFalse(eoseReceived)
        let eventsIsEmpty = await subscription.events.isEmpty
        XCTAssertTrue(eventsIsEmpty)
    }

    func testSubscriptionOptions() {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        options.useCache = false  // Equivalent to the old .cacheOnly being false
        options.limit = 50
        options.timeout = 30.0

        let subscription = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options
        )

        XCTAssertTrue(subscription.options.closeOnEose)
        XCTAssertFalse(subscription.options.useCache)
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
            await subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
            await subscription.handleEOSE()
            await subscription.close()
        }

        // Collect events using AsyncSequence
        var receivedEvents: [NDKEvent] = []
        do {
            for try await event in subscription {
                receivedEvents.append(event)
            }
        } catch {
            // Expected when subscription closes
        }

        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.id, "event123")
    }

    func testEventDeduplication() async {
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
        await subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        await subscription.handleEvent(event, fromRelay: nil as NDKRelay?)

        // Should only have one event
        let events = await subscription.events
        XCTAssertEqual(events.count, 1)
    }

    func testFilterMatching() async {
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

        await subscription.handleEvent(matchingEvent, fromRelay: nil as NDKRelay?)
        await subscription.handleEvent(nonMatchingEvent, fromRelay: nil as NDKRelay?)

        // Should only have the matching event
        let events = await subscription.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.pubkey, "alice")
    }

    func testEOSEHandling() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])

        let eoseReceived = await subscription.eoseReceived
        XCTAssertFalse(eoseReceived)

        Task {
            await subscription.handleEOSE()
            await subscription.close()
        }

        // Wait for subscription to complete
        do {
            for try await _ in subscription {
                // Just consuming events
            }
        } catch {
            // Expected when subscription closes
        }

        let eoseReceivedAfter = await subscription.eoseReceived
        XCTAssertTrue(eoseReceivedAfter)
    }

    func testCloseOnEOSE() async {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true

        let subscription = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options
        )

        await subscription.start()
        let isActive = await subscription.isActive
        XCTAssertTrue(isActive)
        let isClosed = await subscription.isClosed
        XCTAssertFalse(isClosed)

        await subscription.handleEOSE()

        // Give it a moment to process
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let isActiveAfterEose = await subscription.isActive
        XCTAssertFalse(isActiveAfterEose)
        let isClosedAfterEose = await subscription.isClosed
        XCTAssertTrue(isClosedAfterEose)
    }

    func testSubscriptionLimit() async {
        var options = NDKSubscriptionOptions()
        options.limit = 2

        let subscription = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: options
        )

        await subscription.start()

        // Add events up to limit
        for i in 1 ... 3 {
            let event = NDKEvent(
                pubkey: "test",
                createdAt: Int64(i),
                kind: 1,
                content: "Event \(i)"
            )
            event.id = "event\(i)"

            await subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
        }

        // Should close after limit is reached
        let events = await subscription.events
        XCTAssertEqual(events.count, 2)
        let isClosed = await subscription.isClosed
        XCTAssertTrue(isClosed)
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

            await subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
            await subscription.handleEOSE()
            await subscription.close()
        }

        var receivedEvents: [NDKEvent] = []
        
        do {
            for try await event in subscription {
                receivedEvents.append(event)
            }
        } catch {
            // Expected when subscription closes
        }
        
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.id, "test123")
    }

    func testSubscriptionLifecycle() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])

        // Initial state
        let initialIsActive = await subscription.isActive
        XCTAssertFalse(initialIsActive)
        let initialIsClosed = await subscription.isClosed
        XCTAssertFalse(initialIsClosed)

        // Start subscription
        await subscription.start()
        let startedIsActive = await subscription.isActive
        XCTAssertTrue(startedIsActive)
        let startedIsClosed = await subscription.isClosed
        XCTAssertFalse(startedIsClosed)

        // Close subscription
        await subscription.close()
        let closedIsActive = await subscription.isActive
        XCTAssertFalse(closedIsActive)
        let closedIsClosed = await subscription.isClosed
        XCTAssertTrue(closedIsClosed)

        // Cannot restart after close
        await subscription.start()
        let restartIsActive = await subscription.isActive
        XCTAssertFalse(restartIsActive)
        let restartIsClosed = await subscription.isClosed
        XCTAssertTrue(restartIsClosed)
    }

    func testCacheUsage() {
        // Test cache enabled
        var optionsWithCache = NDKSubscriptionOptions()
        optionsWithCache.useCache = true

        let subscriptionWithCache = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: optionsWithCache
        )

        XCTAssertTrue(subscriptionWithCache.options.useCache)

        // Test cache disabled
        var optionsNoCache = NDKSubscriptionOptions()
        optionsNoCache.useCache = false

        let subscriptionNoCache = NDKSubscription(
            filters: [NDKFilter(kinds: [1])],
            options: optionsNoCache
        )

        XCTAssertFalse(subscriptionNoCache.options.useCache)
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

            await subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
            await subscription.close() // Close to end iteration
        }

        var receivedEvents: [NDKEvent] = []
        do {
            for try await event in subscription {
                receivedEvents.append(event)
            }
        } catch {
            // Expected when subscription closes
        }

        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.id, "test123")
    }

    func testAsyncWaitForEOSE() async {
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])

        Task {
            // Give a small delay before sending EOSE
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            await subscription.handleEOSE()
        }

        await subscription.waitForEOSE()
        let eoseReceived = await subscription.eoseReceived
        XCTAssertTrue(eoseReceived)
    }

    func testAsyncUpdatesAPI() async {
        // Test the modern async sequence API
        let subscription = NDKSubscription(filters: [NDKFilter(kinds: [1])])
        
        var eventReceived = false
        
        Task {
            let event = NDKEvent(
                pubkey: "test",
                createdAt: 12345,
                kind: 1,
                content: "Test"
            )
            event.id = "test123"
            
            await subscription.handleEvent(event, fromRelay: nil as NDKRelay?)
            await subscription.handleEOSE()
            
            // Close after EOSE to complete the sequence
            if subscription.options.closeOnEose {
                await subscription.close()
            } else {
                // Manually close for test
                await subscription.close()
            }
        }
        
        do {
            for try await event in subscription {
                eventReceived = true
                XCTAssertEqual(event.id, "test123")
            }
        } catch {
            // Expected when subscription closes
        }
        
        XCTAssertTrue(eventReceived)
        let eoseReceived = await subscription.eoseReceived
        XCTAssertTrue(eoseReceived)
    }
}