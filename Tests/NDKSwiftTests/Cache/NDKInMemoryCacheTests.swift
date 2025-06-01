import XCTest
@testable import NDKSwift

final class NDKInMemoryCacheTests: XCTestCase {
    var cache: NDKInMemoryCache!
    var ndk: NDK!
    
    override func setUp() {
        super.setUp()
        cache = NDKInMemoryCache()
        ndk = NDK(cacheAdapter: cache)
    }
    
    override func tearDown() {
        cache = nil
        ndk = nil
        super.tearDown()
    }
    
    func testCacheProperties() {
        XCTAssertTrue(cache.locking)
        XCTAssertTrue(cache.ready)
    }
    
    func testEventCaching() async throws {
        // Create test events
        let event1 = createTestEvent(id: "event1", pubkey: "alice", kind: 1, content: "Hello")
        let event2 = createTestEvent(id: "event2", pubkey: "bob", kind: 1, content: "World")
        let event3 = createTestEvent(id: "event3", pubkey: "alice", kind: 2, content: "Repost")
        
        // Store events
        let filter1 = NDKFilter(authors: ["alice"], kinds: [1])
        let filter2 = NDKFilter(kinds: [1])
        
        await cache.setEvent(event1, filters: [filter1, filter2], relay: nil)
        await cache.setEvent(event2, filters: [filter2], relay: nil)
        await cache.setEvent(event3, filters: [], relay: nil)
        
        // Query by author and kind
        let subscription1 = NDKSubscription(filters: [filter1], ndk: ndk)
        let results1 = await cache.query(subscription: subscription1)
        XCTAssertEqual(results1.count, 1)
        XCTAssertEqual(results1.first?.id, "event1")
        
        // Query by kind only
        let subscription2 = NDKSubscription(filters: [filter2], ndk: ndk)
        let results2 = await cache.query(subscription: subscription2)
        XCTAssertEqual(results2.count, 2)
        XCTAssertTrue(results2.contains { $0.id == "event1" })
        XCTAssertTrue(results2.contains { $0.id == "event2" })
        
        // Query with no matches
        let filter3 = NDKFilter(kinds: [999])
        let subscription3 = NDKSubscription(filters: [filter3], ndk: ndk)
        let results3 = await cache.query(subscription: subscription3)
        XCTAssertEqual(results3.count, 0)
    }
    
    func testProfileCaching() async throws {
        let pubkey = "alice123"
        let profile = NDKUserProfile(
            name: "Alice",
            displayName: "Alice in Wonderland",
            about: "Down the rabbit hole",
            picture: "https://example.com/alice.jpg"
        )
        
        // Initially no profile
        let cached1 = await cache.fetchProfile(pubkey: pubkey)
        XCTAssertNil(cached1)
        
        // Save profile
        await cache.saveProfile(pubkey: pubkey, profile: profile)
        
        // Fetch cached profile
        let cached2 = await cache.fetchProfile(pubkey: pubkey)
        XCTAssertNotNil(cached2)
        XCTAssertEqual(cached2?.name, "Alice")
        XCTAssertEqual(cached2?.displayName, "Alice in Wonderland")
    }
    
    func testNIP05Caching() async throws {
        let nip05 = "alice@example.com"
        let pubkey = "alice123"
        let relays = ["wss://relay1.com", "wss://relay2.com"]
        
        // Initially no data
        let cached1 = await cache.loadNip05(nip05)
        XCTAssertNil(cached1)
        
        // Save NIP-05 data
        await cache.saveNip05(nip05, pubkey: pubkey, relays: relays)
        
        // Load cached data
        let cached2 = await cache.loadNip05(nip05)
        XCTAssertNotNil(cached2)
        XCTAssertEqual(cached2?.pubkey, pubkey)
        XCTAssertEqual(cached2?.relays, relays)
        
        // Case insensitive
        let cached3 = await cache.loadNip05("ALICE@EXAMPLE.COM")
        XCTAssertNotNil(cached3)
        XCTAssertEqual(cached3?.pubkey, pubkey)
    }
    
    func testRelayStatus() async throws {
        let relay1 = "wss://relay1.com"
        let relay2 = "wss://relay2.com"
        
        // Initially no status
        let status1 = await cache.getRelayStatus(relay1)
        XCTAssertNil(status1)
        
        // Update status
        await cache.updateRelayStatus(relay1, status: .connected)
        await cache.updateRelayStatus(relay2, status: .failed("Connection refused"))
        
        // Get status
        let status2 = await cache.getRelayStatus(relay1)
        XCTAssertEqual(status2, .connected)
        
        let status3 = await cache.getRelayStatus(relay2)
        if case .failed(let message) = status3 {
            XCTAssertEqual(message, "Connection refused")
        } else {
            XCTFail("Expected failed status")
        }
    }
    
    func testUnpublishedEvents() async throws {
        let event1 = createTestEvent(id: "event1", pubkey: "alice", kind: 1, content: "Test 1")
        let event2 = createTestEvent(id: "event2", pubkey: "alice", kind: 1, content: "Test 2")
        let relay1 = "wss://relay1.com"
        let relay2 = "wss://relay2.com"
        
        // Add unpublished events
        await cache.addUnpublishedEvent(event1, relayUrls: [relay1, relay2])
        await cache.addUnpublishedEvent(event2, relayUrls: [relay1])
        
        // Get unpublished events for relay1
        let unpublished1 = await cache.getUnpublishedEvents(for: relay1)
        XCTAssertEqual(unpublished1.count, 2)
        
        // Get unpublished events for relay2
        let unpublished2 = await cache.getUnpublishedEvents(for: relay2)
        XCTAssertEqual(unpublished2.count, 1)
        XCTAssertEqual(unpublished2.first?.id, "event1")
        
        // Remove event1 from relay1
        await cache.removeUnpublishedEvent("event1", from: relay1)
        
        let unpublished3 = await cache.getUnpublishedEvents(for: relay1)
        XCTAssertEqual(unpublished3.count, 1)
        XCTAssertEqual(unpublished3.first?.id, "event2")
        
        // relay2 should still have event1
        let unpublished4 = await cache.getUnpublishedEvents(for: relay2)
        XCTAssertEqual(unpublished4.count, 1)
        XCTAssertEqual(unpublished4.first?.id, "event1")
    }
    
    func testBroadFilterQuery() async throws {
        // Create events
        let events = (1...5).map { i in
            createTestEvent(id: "event\(i)", pubkey: "user\(i)", kind: i, content: "Content \(i)")
        }
        
        // Store all events
        for event in events {
            await cache.setEvent(event, filters: [], relay: nil)
        }
        
        // Query with broad filter (no constraints)
        let broadFilter = NDKFilter()
        let subscription = NDKSubscription(filters: [broadFilter], ndk: ndk)
        let results = await cache.query(subscription: subscription)
        
        XCTAssertEqual(results.count, 5)
    }
    
    func testCacheStatistics() async throws {
        // Add some data
        let event = createTestEvent(id: "event1", pubkey: "alice", kind: 1, content: "Test")
        await cache.setEvent(event, filters: [], relay: nil)
        
        let profile = NDKUserProfile(name: "Alice")
        await cache.saveProfile(pubkey: "alice", profile: profile)
        
        await cache.saveNip05("alice@example.com", pubkey: "alice", relays: [])
        
        // Get statistics
        let stats = await cache.statistics()
        XCTAssertEqual(stats.events, 1)
        XCTAssertEqual(stats.profiles, 1)
        XCTAssertEqual(stats.nip05, 1)
    }
    
    func testCacheClear() async throws {
        // Add data
        let event = createTestEvent(id: "event1", pubkey: "alice", kind: 1, content: "Test")
        await cache.setEvent(event, filters: [], relay: nil)
        await cache.saveProfile(pubkey: "alice", profile: NDKUserProfile(name: "Alice"))
        await cache.saveNip05("alice@example.com", pubkey: "alice", relays: [])
        
        // Verify data exists
        var stats = await cache.statistics()
        XCTAssertGreaterThan(stats.events, 0)
        XCTAssertGreaterThan(stats.profiles, 0)
        XCTAssertGreaterThan(stats.nip05, 0)
        
        // Clear cache
        await cache.clear()
        
        // Verify cache is empty
        stats = await cache.statistics()
        XCTAssertEqual(stats.events, 0)
        XCTAssertEqual(stats.profiles, 0)
        XCTAssertEqual(stats.nip05, 0)
    }
    
    func testComplexQueries() async throws {
        // Create a variety of events
        let events = [
            createTestEvent(id: "1", pubkey: "alice", kind: 1, content: "Alice post 1"),
            createTestEvent(id: "2", pubkey: "alice", kind: 1, content: "Alice post 2"),
            createTestEvent(id: "3", pubkey: "alice", kind: 2, content: "Alice repost"),
            createTestEvent(id: "4", pubkey: "bob", kind: 1, content: "Bob post 1"),
            createTestEvent(id: "5", pubkey: "bob", kind: 3, content: "Bob contacts"),
            createTestEvent(id: "6", pubkey: "charlie", kind: 1, content: "Charlie post")
        ]
        
        // Add timestamp variations
        events[0].createdAt = 1000
        events[1].createdAt = 2000
        events[2].createdAt = 3000
        events[3].createdAt = 1500
        events[4].createdAt = 2500
        events[5].createdAt = 3500
        
        // Store all events
        for event in events {
            await cache.setEvent(event, filters: [], relay: nil)
        }
        
        // Test 1: Multiple filters in subscription
        let filters = [
            NDKFilter(authors: ["alice"], kinds: [1]),
            NDKFilter(authors: ["bob"], kinds: [3])
        ]
        let sub1 = NDKSubscription(filters: filters, ndk: ndk)
        let results1 = await cache.query(subscription: sub1)
        XCTAssertEqual(results1.count, 3) // Alice's 2 kind:1 posts + Bob's contacts
        
        // Test 2: Time-based filter
        let filter2 = NDKFilter(since: 1500, until: 2500)
        let sub2 = NDKSubscription(filters: [filter2], ndk: ndk)
        let results2 = await cache.query(subscription: sub2)
        XCTAssertEqual(results2.count, 3) // Events at 1500, 2000, 2500
        
        // Test 3: Specific IDs
        let filter3 = NDKFilter(ids: ["1", "3", "5"])
        let sub3 = NDKSubscription(filters: [filter3], ndk: ndk)
        let results3 = await cache.query(subscription: sub3)
        XCTAssertEqual(results3.count, 3)
        XCTAssertTrue(results3.allSatisfy { ["1", "3", "5"].contains($0.id ?? "") })
    }
    
    // MARK: - Helpers
    
    private func createTestEvent(id: String, pubkey: String, kind: Int, content: String) -> NDKEvent {
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            content: content
        )
        event.id = id
        return event
    }
}