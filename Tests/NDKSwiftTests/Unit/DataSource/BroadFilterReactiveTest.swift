import XCTest
@testable import NDKSwift

/// Tests that verify broader filters receive events from more specific subscriptions
final class BroadFilterReactiveTest: XCTestCase {
    var ndk: NDK!
    var cache: NDKSQLiteCache!
    
    override func setUp() async throws {
        try await super.setUp()
        // Use SQLiteCache which properly implements reactive observation
        cache = try await NDKSQLiteCache(path: ":memory:")
        ndk = NDK(cache: cache)
        ndk.outboxEnabled = false
    }
    
    override func tearDown() async throws {
        ndk = nil
        cache = nil
        try await super.tearDown()
    }
    
    func testBroadFilterReceivesEventsFromSpecificSubscription() async throws {
        // Create test authors
        let author1 = "author1_\(UUID().uuidString)"
        let author2 = "author2_\(UUID().uuidString)"
        
        // Track events
        var broadFilterEvents: [NDKEvent] = []
        var specificFilterEvents: [NDKEvent] = []
        
        // Create broad cache-only subscription (all kind:1 events)
        let broadFilter = NDKFilter(kinds: [1])
        let broadDataSource = ndk.subscribe(
            filter: broadFilter,
            cachePolicy: .cacheOnly,
            subscriptionId: "broad-cache-sub"
        )
        
        let broadExpectation = expectation(description: "Broad filter should receive events")
        broadExpectation.expectedFulfillmentCount = 2 // Expect 2 events
        
        let broadTask = Task {
            for await event in broadDataSource.events {
                broadFilterEvents.append(event)
                broadExpectation.fulfill()
            }
        }
        
        // Give broad subscription time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Create specific network subscription (only author1's kind:1 events)
        let specificFilter = NDKFilter(authors: [author1], kinds: [1])
        let specificDataSource = ndk.subscribe(
            filter: specificFilter,
            cachePolicy: .networkOnly,
            subscriptionId: "specific-network-sub"
        )
        
        let specificTask = Task {
            for await event in specificDataSource.events {
                specificFilterEvents.append(event)
            }
        }
        
        // Give specific subscription time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Create events from both authors
        let event1 = EventTestFactory.createEvent(
            kind: 1,
            content: "Event from author1",
            pubkey: author1,
            id: "event1_\(UUID().uuidString)"
        )
        
        let event2 = EventTestFactory.createEvent(
            kind: 1,
            content: "Event from author2",
            pubkey: author2,
            id: "event2_\(UUID().uuidString)"
        )
        
        // Process events through the cache since we're testing cache-only subscriptions
        // The broad filter is cache-only, so it will only see events that are saved to cache
        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        
        // Wait for events to propagate
        await fulfillment(of: [broadExpectation], timeout: 2.0)
        
        // Verify results
        XCTAssertEqual(specificFilterEvents.count, 1, "Specific filter should only receive author1's event")
        XCTAssertEqual(specificFilterEvents.first?.pubkey, author1, "Specific filter got correct event")
        
        XCTAssertEqual(broadFilterEvents.count, 2, "Broad filter should receive all kind:1 events")
        let receivedAuthors = Set(broadFilterEvents.map { $0.pubkey })
        XCTAssertTrue(receivedAuthors.contains(author1), "Broad filter should have author1's event")
        XCTAssertTrue(receivedAuthors.contains(author2), "Broad filter should have author2's event")
        
        // Cancel tasks
        broadTask.cancel()
        specificTask.cancel()
    }
    
    func testMultipleBroadFiltersReceiveEvents() async throws {
        // Track events
        var allKind1Events: [NDKEvent] = []
        var allKind4Events: [NDKEvent] = []
        var allEventsFromAuthor: [NDKEvent] = []
        
        let testAuthor = "test_author_\(UUID().uuidString)"
        
        // Create multiple broad filters
        let kind1Filter = NDKFilter(kinds: [1])
        let kind4Filter = NDKFilter(kinds: [4])
        let authorFilter = NDKFilter(authors: [testAuthor])
        
        // Create cache-only subscriptions
        let kind1DataSource = ndk.subscribe(
            filter: kind1Filter,
            cachePolicy: .cacheOnly,
            subscriptionId: "kind1-cache"
        )
        
        let kind4DataSource = ndk.subscribe(
            filter: kind4Filter,
            cachePolicy: .cacheOnly,
            subscriptionId: "kind4-cache"
        )
        
        let authorDataSource = ndk.subscribe(
            filter: authorFilter,
            cachePolicy: .cacheOnly,
            subscriptionId: "author-cache"
        )
        
        // Set up expectations
        let kind1Expectation = expectation(description: "Kind 1 filter receives event")
        let kind4Expectation = expectation(description: "Kind 4 filter receives event")
        let authorExpectation = expectation(description: "Author filter receives events")
        authorExpectation.expectedFulfillmentCount = 2 // Expect both events from author
        
        // Start collecting events
        let kind1Task = Task {
            for await event in kind1DataSource.events {
                allKind1Events.append(event)
                kind1Expectation.fulfill()
            }
        }
        
        let kind4Task = Task {
            for await event in kind4DataSource.events {
                allKind4Events.append(event)
                kind4Expectation.fulfill()
            }
        }
        
        let authorTask = Task {
            for await event in authorDataSource.events {
                allEventsFromAuthor.append(event)
                authorExpectation.fulfill()
            }
        }
        
        // Give subscriptions time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Create test events
        let kind1Event = EventTestFactory.createEvent(
            kind: 1,
            content: "Kind 1 event",
            pubkey: testAuthor,
            id: "kind1_\(UUID().uuidString)"
        )
        
        let kind4Event = EventTestFactory.createEvent(
            kind: 4,
            content: "Kind 4 event",
            pubkey: testAuthor,
            id: "kind4_\(UUID().uuidString)"
        )
        
        // Process events through the cache since we're testing cache-only subscriptions
        try await cache.saveEvent(kind1Event)
        try await cache.saveEvent(kind4Event)
        
        // Wait for events
        await fulfillment(of: [kind1Expectation, kind4Expectation, authorExpectation], timeout: 2.0)
        
        // Verify
        XCTAssertEqual(allKind1Events.count, 1, "Kind 1 filter should receive kind 1 event")
        XCTAssertEqual(allKind1Events.first?.kind, 1, "Kind 1 filter got correct event")
        
        XCTAssertEqual(allKind4Events.count, 1, "Kind 4 filter should receive kind 4 event")
        XCTAssertEqual(allKind4Events.first?.kind, 4, "Kind 4 filter got correct event")
        
        XCTAssertEqual(allEventsFromAuthor.count, 2, "Author filter should receive all events from author")
        let receivedKinds = Set(allEventsFromAuthor.map { $0.kind })
        XCTAssertTrue(receivedKinds.contains(1), "Author filter should have kind 1 event")
        XCTAssertTrue(receivedKinds.contains(4), "Author filter should have kind 4 event")
        
        // Cancel tasks
        kind1Task.cancel()
        kind4Task.cancel()
        authorTask.cancel()
    }
}