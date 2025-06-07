import XCTest
@testable import NDKSwift

class NDKFetchEventTests: XCTestCase {
    
    func testFetchEventByIdBasic() async throws {
        // Setup
        let ndk = NDK()
        let mockRelay = MockRelay(url: "wss://mock.relay")
        
        // Create a mock event
        let testEvent = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            content: "Test content"
        )
        testEvent.id = "test_event_id"
        testEvent.sig = "test_signature"
        
        // Add the event to mock relay
        mockRelay.mockEvents = [testEvent]
        
        // Test fetching by ID
        let fetchedEvent = try await ndk.fetchEvent("test_event_id", relays: Set([mockRelay]))
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.id, "test_event_id")
        XCTAssertEqual(fetchedEvent?.content, "Test content")
    }
    
    func testFetchEventWithMultipleRelays() async throws {
        // Setup
        let ndk = NDK()
        let mockRelay1 = MockRelay(url: "wss://relay1.mock")
        let mockRelay2 = MockRelay(url: "wss://relay2.mock")
        
        // Create a mock event (only on relay2)
        let testEvent = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            content: "Test content"
        )
        testEvent.id = "test_event_id"
        testEvent.sig = "test_signature"
        
        // Add event only to relay2
        mockRelay2.mockEvents = [testEvent]
        
        // Test fetching from multiple relays
        let fetchedEvent = try await ndk.fetchEvent("test_event_id", relays: Set([mockRelay1, mockRelay2]))
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.id, "test_event_id")
        XCTAssertEqual(fetchedEvent?.content, "Test content")
    }
    
    func testFetchEventByFilter() async throws {
        // Setup
        let ndk = NDK()
        let mockRelay = MockRelay(url: "wss://mock.relay")
        
        // Create mock events
        let event1 = NDKEvent(
            pubkey: "author1",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            content: "Event 1"
        )
        event1.id = "event1"
        event1.sig = "sig1"
        
        let event2 = NDKEvent(
            pubkey: "author2",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            content: "Event 2"
        )
        event2.id = "event2"
        event2.sig = "sig2"
        
        mockRelay.mockEvents = [event1, event2]
        
        // Test fetching by author filter
        let filter = NDKFilter(authors: ["author1"], kinds: [1])
        let fetchedEvent = try await ndk.fetchEvent(filter, relays: Set([mockRelay]))
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.pubkey, "author1")
        XCTAssertEqual(fetchedEvent?.content, "Event 1")
    }
    
    func testFetchAddressableEvent() async throws {
        // Setup
        let ndk = NDK()
        let mockRelay = MockRelay(url: "wss://mock.relay")
        
        // Create an addressable event (kind 30023 - article)
        let article = NDKEvent(
            pubkey: "author_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 30023,
            content: "Article content",
            tags: [["d", "my-article"]]
        )
        article.id = "article_id"
        article.sig = "article_sig"
        
        mockRelay.mockEvents = [article]
        
        // Test fetching by d-tag
        let filter = NDKFilter(
            authors: ["author_pubkey"],
            kinds: [30023],
            tags: ["d": ["my-article"]]
        )
        let fetchedArticle = try await ndk.fetchEvent(filter, relays: Set([mockRelay]))
        
        XCTAssertNotNil(fetchedArticle)
        XCTAssertEqual(fetchedArticle?.id, "article_id")
        XCTAssertEqual(fetchedArticle?.tags.first { $0.first == "d" }?[1], "my-article")
    }
    
    func testFetchEventTimeout() async throws {
        // Setup
        let ndk = NDK()
        let mockRelay = MockRelay(url: "wss://mock.relay")
        mockRelay.responseDelay = 5.0 // 5 second delay
        
        // Test fetching with timeout
        let filter = NDKFilter(ids: ["nonexistent"])
        
        do {
            let _ = try await ndk.fetchEvent(filter, relays: Set([mockRelay]), timeout: 0.1)
            XCTFail("Should have timed out")
        } catch {
            // Expected timeout error
            XCTAssertTrue(true)
        }
    }
    
    func testFetchEventFromCache() async throws {
        // Setup
        let mockCache = MockCache()
        let ndk = NDK(cacheAdapter: mockCache)
        
        // Create a cached event
        let cachedEvent = NDKEvent(
            pubkey: "cached_author",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            content: "Cached content"
        )
        cachedEvent.id = "cached_event_id"
        cachedEvent.sig = "cached_sig"
        
        mockCache.mockEvents = [cachedEvent]
        
        // Test fetching from cache
        let fetchedEvent = try await ndk.fetchEvent("cached_event_id")
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.id, "cached_event_id")
        XCTAssertEqual(fetchedEvent?.content, "Cached content")
        XCTAssertTrue(mockCache.queryCalled)
    }
    
    func testFetchEventNotFound() async throws {
        // Setup
        let ndk = NDK()
        let mockRelay = MockRelay(url: "wss://mock.relay")
        
        // No events in mock relay
        mockRelay.mockEvents = []
        
        // Test fetching non-existent event
        let eventId = "nonexistent_event_id"
        
        let fetchedEvent = try await ndk.fetchEvent(eventId, relays: Set([mockRelay]))
        
        XCTAssertNil(fetchedEvent)
    }
}