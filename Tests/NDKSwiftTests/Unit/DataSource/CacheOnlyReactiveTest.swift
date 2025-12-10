import XCTest
@testable import NDKSwiftCore
import NDKSwiftSQLite

/// Tests that verify cache-only subscriptions participate in the reactive system
/// and receive events from network subscriptions with the same fingerprint
final class CacheOnlyReactiveTest: XCTestCase {
    var ndk: NDK!
    var cache: NDKSQLiteCache!
    
    override func setUp() async throws {
        try await super.setUp()
        cache = try await NDKSQLiteCache()
        ndk = NDK(cache: cache)
        ndk.outboxEnabled = false
    }
    
    override func tearDown() async throws {
        try await cache.clear()
        ndk = nil
        cache = nil
        try await super.tearDown()
    }
    
    func testCacheOnlySubscriptionReceivesEventsFromNetworkSubscription() async throws {
        // Create a unique filter
        let testAuthor = "test_author_\(UUID().uuidString)"
        let filter = NDKFilter(authors: [testAuthor], kinds: [1])
        
        // Track events
        var networkEvents: [NDKEvent] = []
        var cacheOnlyEvents: [NDKEvent] = []
        
        // Create network subscription
        let networkDataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly,
            subscriptionId: "network-sub"
        )
        
        let networkTask = Task {
            for await event in networkDataSource.events {
                networkEvents.append(event)
            }
        }
        
        // Give network subscription time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Create cache-only subscription with same filter
        let cacheDataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheOnly,
            subscriptionId: "cache-sub"
        )
        
        let cacheExpectation = expectation(description: "Cache subscription should receive event")
        
        let cacheTask = Task {
            for await event in cacheDataSource.events {
                cacheOnlyEvents.append(event)
                cacheExpectation.fulfill()
            }
        }
        
        // Give cache subscription time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Create and process event through internal subscription system
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test reactive system",
            tags: [],
            pubkey: testAuthor,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            id: "test_event_\(UUID().uuidString)"
        )
        
        // Simulate event arriving from relay
        let mockRelay = MockRelay(url: "wss://test.relay/")
        await ndk.internalSubscriptionManager.processEvent(
            event,
            subscriptionId: "network-sub",
            from: mockRelay
        )
        
        // Wait for event propagation
        await fulfillment(of: [cacheExpectation], timeout: 2.0)
        
        // Verify both subscriptions received the event
        XCTAssertEqual(networkEvents.count, 1, "Network subscription should receive the event")
        XCTAssertEqual(cacheOnlyEvents.count, 1, "Cache-only subscription should receive the event")
        XCTAssertEqual(cacheOnlyEvents.first?.id, event.id, "Cache subscription got correct event")
        
        // Cancel tasks
        networkTask.cancel()
        cacheTask.cancel()
    }
    
    func testMultipleCacheOnlySubscriptionsShareEvents() async throws {
        // Create a unique filter
        let testAuthor = "shared_author_\(UUID().uuidString)"
        let filter = NDKFilter(authors: [testAuthor], kinds: [1])
        
        // Track events
        var cache1Events: [NDKEvent] = []
        var cache2Events: [NDKEvent] = []
        var networkEvents: [NDKEvent] = []
        
        // Create first cache-only subscription
        let cache1DataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheOnly,
            subscriptionId: "cache-1"
        )
        
        let cache1Task = Task {
            for await event in cache1DataSource.events {
                cache1Events.append(event)
            }
        }
        
        // Create second cache-only subscription
        let cache2DataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheOnly,
            subscriptionId: "cache-2"
        )
        
        let cache2Task = Task {
            for await event in cache2DataSource.events {
                cache2Events.append(event)
            }
        }
        
        // Give cache subscriptions time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Create network subscription
        let networkDataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly,
            subscriptionId: "network-sub"
        )
        
        let networkExpectation = expectation(description: "Network subscription should receive event")
        
        let networkTask = Task {
            for await event in networkDataSource.events {
                networkEvents.append(event)
                networkExpectation.fulfill()
            }
        }
        
        // Give network subscription time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Create and process event
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Shared event test",
            tags: [],
            pubkey: testAuthor,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            id: "shared_event_\(UUID().uuidString)"
        )
        
        // Process through network subscription
        let mockRelay = MockRelay(url: "wss://test.relay/")
        await ndk.internalSubscriptionManager.processEvent(
            event,
            subscriptionId: "network-sub",
            from: mockRelay
        )
        
        // Wait for event propagation
        await fulfillment(of: [networkExpectation], timeout: 2.0)
        
        // Give cache subscriptions time to receive event
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // All subscriptions should have received the event
        XCTAssertEqual(networkEvents.count, 1, "Network subscription should receive the event")
        XCTAssertEqual(cache1Events.count, 1, "First cache subscription should receive the event")
        XCTAssertEqual(cache2Events.count, 1, "Second cache subscription should receive the event")
        XCTAssertEqual(cache1Events.first?.id, event.id, "First cache got correct event")
        XCTAssertEqual(cache2Events.first?.id, event.id, "Second cache got correct event")
        
        // Cancel tasks
        cache1Task.cancel()
        cache2Task.cancel()
        networkTask.cancel()
    }
    
    func testCacheOnlySubscriptionDoesNotCreateNetworkTraffic() async throws {
        // Create a unique filter
        let testAuthor = "no_network_\(UUID().uuidString)"
        let filter = NDKFilter(authors: [testAuthor], kinds: [1])
        
        // Track if any network activity happens
        var networkActivityDetected = false
        
        // Monitor relay pool for any subscription activity
        Task {
            for await change in await ndk.pool.relayChanges {
                if case .relayConnected = change {
                    networkActivityDetected = true
                }
            }
        }
        
        // Create cache-only subscription
        let cacheDataSource = ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheOnly,
            subscriptionId: "cache-only-no-network"
        )
        
        var cacheEvents: [NDKEvent] = []
        let cacheTask = Task {
            for await event in cacheDataSource.events {
                cacheEvents.append(event)
            }
        }
        
        // Give subscription time to set up
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Verify no network activity
        XCTAssertFalse(networkActivityDetected, "Cache-only subscription should not cause network activity")
        
        // Cancel task
        cacheTask.cancel()
    }
}