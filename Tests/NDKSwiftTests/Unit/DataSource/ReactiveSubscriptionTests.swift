@testable import NDKSwiftCore
import NDKSwiftSQLite
import XCTest

final class ReactiveSubscriptionTests: XCTestCase {
    var ndk: NDK!
    var cache: NDKSQLiteCache!
    var tempDbPath: String!

    override func setUp() async throws {
        try await super.setUp()
        // Use SQLiteCache which supports reactive observation
        tempDbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("reactive-test-\(UUID().uuidString).db").path
        cache = try await NDKSQLiteCache(path: tempDbPath, debugMode: true)
        ndk = NDK(cache: cache)
        ndk.outboxEnabled = false // Simplify test by disabling outbox
    }

    override func tearDown() async throws {
        if let cache = cache {
            try await cache.clear()
        }
        ndk = nil
        cache = nil
        // Clean up temp database
        if let tempDbPath = tempDbPath {
            try? FileManager.default.removeItem(atPath: tempDbPath)
        }
        try await super.tearDown()
    }

    func testCacheOnlySubscriptionReceivesNetworkEvents() async throws {
        // Create a filter for specific author
        let testAuthor = "test_author_pubkey_\(UUID().uuidString)"
        let filter = NDKFilter(authors: [testAuthor], kinds: [1])

        // Create network subscription first
        let networkEvents = ActorQueue<NDKEvent>()
        let networkDataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly,
            subscriptionId: "network-sub"
        )

        Task {
            for await event in networkDataSource.events {
                await networkEvents.enqueue(event)
            }
        }

        // Give network subscription time to set up
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

        // Create cache-only subscription with same filter
        let cacheOnlyEvents = ActorQueue<NDKEvent>()
        let cacheOnlyDataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheOnly,
            subscriptionId: "cache-only-sub"
        )

        Task {
            for await event in cacheOnlyDataSource.events {
                await cacheOnlyEvents.enqueue(event)
            }
        }

        // Give cache subscription time to set up
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

        // Create test event
        let event = NDKEvent(
            id: "test_reactive_event_\(UUID().uuidString)",
            pubkey: testAuthor,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test reactive behavior",
            sig: "test_signature"
        )

        // Process event through the cache, which will notify observers
        // This simulates what happens when an event arrives from a relay
        try await cache.processEvent(event, from: "wss://test.relay/", subscriptionId: "network-sub")

        // Give events time to propagate
        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

        // Both subscriptions should have received the event
        let cacheOnlyReceived = await cacheOnlyEvents.dequeueAll()
        let networkReceived = await networkEvents.dequeueAll()

        XCTAssertEqual(networkReceived.count, 1, "Network subscription should receive 1 event")
        XCTAssertEqual(cacheOnlyReceived.count, 1, "Cache-only subscription should receive 1 event via fingerprint routing")
        XCTAssertEqual(cacheOnlyReceived.first?.id, event.id, "Cache-only got correct event")
        XCTAssertEqual(networkReceived.first?.id, event.id, "Network got correct event")
    }

    func testDynamicRelayDiscoveryWithReactiveSubscriptions() async throws {
        // This test simulates the outbox scenario where:
        // 1. Initial subscription uses fallback relay
        // 2. Cache-only subscription observes same filter
        // 3. Relay discovery adds new relays dynamically
        // 4. Events from new relays should reach cache-only subscription

        let testAuthor = "dynamic_test_author"
        let filter = NDKFilter(authors: [testAuthor], kinds: [1], limit: 10)

        // Track all events received
        let allEvents = ActorQueue<(event: NDKEvent, source: String)>()

        // Create main network subscription
        let networkDataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly,
            subscriptionId: "main-network-sub"
        )

        Task {
            for await event in networkDataSource.events {
                await allEvents.enqueue((event: event, source: "network"))
            }
        }

        // Create cache-only reactive subscription
        let cacheDataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheOnly,
            subscriptionId: "reactive-cache-sub"
        )

        Task {
            for await event in cacheDataSource.events {
                await allEvents.enqueue((event: event, source: "cache"))
            }
        }

        // Give subscriptions time to set up
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds

        // Simulate event from initial relay
        let event1 = NDKEvent(
            id: "initial_relay_event",
            pubkey: testAuthor,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Event from initial relay",
            sig: "test_signature1"
        )

        try await cache.saveEvent(event1)

        // Simulate dynamic relay discovery creating enhanced subscription
        // In real scenario, this happens via handleRelayDiscovery
        let enhancedFilter = filter // Same filter, different relay
        let enhancedDataSource = ndk.subscribe(
            filter: enhancedFilter,
            cachePolicy: .networkOnly,
            subscriptionId: "main-network-sub_enhanced_relay2"
        )

        Task {
            for await event in enhancedDataSource.events {
                await allEvents.enqueue((event: event, source: "enhanced"))
            }
        }

        // Simulate event from newly discovered relay
        let event2 = NDKEvent(
            id: "discovered_relay_event",
            pubkey: testAuthor,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Event from discovered relay",
            sig: "test_signature2"
        )

        try await cache.saveEvent(event2)

        // Give events time to propagate
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Check all received events
        let receivedEvents = await allEvents.dequeueAll()

        // We expect at least 4 events:
        // - event1 received by network and cache subscriptions
        // - event2 received by enhanced and cache subscriptions
        XCTAssertGreaterThanOrEqual(receivedEvents.count, 4, "Should receive events from all sources")

        // Verify cache-only subscription received both events
        let cacheEvents = receivedEvents.filter { $0.source == "cache" }
        let cacheEventIds = Set(cacheEvents.map { $0.event.id })

        XCTAssertTrue(cacheEventIds.contains(event1.id), "Cache subscription should receive initial event")
        XCTAssertTrue(cacheEventIds.contains(event2.id), "Cache subscription should receive discovered relay event")
    }
}

// Helper actor for thread-safe event collection
actor ActorQueue<T> {
    private var items: [T] = []

    func enqueue(_ item: T) {
        items.append(item)
    }

    func dequeueAll() -> [T] {
        let result = items
        items.removeAll()
        return result
    }
}
