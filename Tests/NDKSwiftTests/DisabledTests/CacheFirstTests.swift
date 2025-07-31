import XCTest
@testable import NDKSwift

/// Tests for cache-first behavior in NDKSubscriptionManager
class CacheFirstTests: XCTestCase {
    var ndk: NDK!
    var cache: MemoryCache!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create memory cache and NDK instance
        cache = MemoryCache()
        ndk = NDK(
            relayUrls: [], // No relays to ensure we're testing cache-only behavior
            cache: cache
        )
    }
    
    override func tearDown() async throws {
        await ndk.disconnect()
        ndk = nil
        cache = nil
        try await super.tearDown()
    }
    
    func testImmediateCacheHit() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
        // Arrange: Pre-populate cache with some events
        var events: [NDKEvent] = []
        for i in 0..<5 {
            let event = try await self.createTestEvent(
                content: "Test event \(i)",
                pubkey: "test_pubkey"
            )
            events.append(event)
            try await self.cache.saveEvent(event)
        }
        
        // Create filter matching cached events
        let filter = NDKFilter(kinds: [1])
        
        // Track when events are received
        var receivedEvents: [NDKEvent] = []
        let startTime = Date()
        
        // Act: Create data source (should immediately hit cache)
        let dataSource = NDKSubscription(
            ndk: self.ndk,
            filter: filter,
            maxAge: 60, // 1 minute - cache should be fresh
            cachePolicy: .cacheWithNetwork
        )
        
        // Collect events with timeout
        let collectTask = Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
                
                // Check timing - should be immediate (< 50ms)
                let elapsed = Date().timeIntervalSince(startTime)
                print("Received event \(receivedEvents.count) after \(elapsed * 1000)ms")
            }
        }
        
        // Wait briefly to ensure cache delivery
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        collectTask.cancel()
        
        // Assert: Should have received all cached events immediately
        XCTAssertEqual(receivedEvents.count, 5, "Should receive all cached events")
        XCTAssertEqual(Set(receivedEvents.map { $0.id }), Set(events.map { $0.id }))
        }
    }
    
    func testCacheFreshnessCheck() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
        // Arrange: Create filter and record fetch time
        let filter = NDKFilter(kinds: [1])
        await self.cache.recordFetchTime(for: filter, timestamp: Date())
        
        // Pre-populate with events
        var events: [NDKEvent] = []
        for i in 0..<3 {
            let event = try await self.createTestEvent(
                content: "Fresh event \(i)",
                pubkey: "test_pubkey"
            )
            events.append(event)
            try await self.cache.saveEvent(event)
        }
        
        // Add a relay to test network behavior
        await self.ndk.addRelay("wss://test.relay")
        
        // Act: Create data source with maxAge that makes cache fresh
        let dataSource = NDKSubscription(
            ndk: self.ndk,
            filter: filter,
            maxAge: 300, // 5 minutes - cache should be fresh
            cachePolicy: .cacheWithNetwork
        )
        
        // Collect events
        var receivedEvents: [NDKEvent] = []
        let collectTask = Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
            }
        }
        
        // Wait for grouping window to pass
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        collectTask.cancel()
        
        // Assert: Should receive cached events
        // Note: We can't easily verify no network subscription was created without internal mocking
        XCTAssertEqual(receivedEvents.count, 3, "Should receive cached events")
        }
    }
    
    func testStaleCache() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
        // Arrange: Create filter with old fetch time
        let filter = NDKFilter(kinds: [1])
        let oldDate = Date().addingTimeInterval(-3600) // 1 hour ago
        await self.cache.recordFetchTime(for: filter, timestamp: oldDate)
        
        // Pre-populate with events
        var events: [NDKEvent] = []
        for i in 0..<2 {
            let event = try await self.createTestEvent(
                content: "Stale event \(i)",
                pubkey: "test_pubkey"
            )
            events.append(event)
            try await self.cache.saveEvent(event)
        }
        
        // Act: Create data source with maxAge that makes cache stale
        let dataSource = NDKSubscription(
            ndk: self.ndk,
            filter: filter,
            maxAge: 300, // 5 minutes - cache is stale (1 hour old)
            cachePolicy: .cacheWithNetwork
        )
        
        // Collect events
        var receivedEvents: [NDKEvent] = []
        let collectTask = Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
                print("Received event from stale cache test")
            }
        }
        
        // Wait for initial cache delivery
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Wait for grouping window to pass
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms more
        collectTask.cancel()
        
        // Assert: Should receive cached events immediately
        XCTAssertEqual(receivedEvents.count, 2, "Should receive cached events immediately even when stale")
        }
    }
    
    func testNetworkOnlyPolicy() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
        // Arrange: Pre-populate cache
        for i in 0..<3 {
            let event = try await self.createTestEvent(
                content: "Cached event \(i)",
                pubkey: "test_pubkey"
            )
            try await self.cache.saveEvent(event)
        }
        
        let filter = NDKFilter(kinds: [1])
        
        // Act: Create data source with networkOnly policy
        let dataSource = NDKSubscription(
            ndk: self.ndk,
            filter: filter,
            cachePolicy: .networkOnly
        )
        
        // Try to collect events immediately
        var receivedEvents: [NDKEvent] = []
        let collectTask = Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
            }
        }
        
        // Wait briefly
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        collectTask.cancel()
        
        // Assert: Should NOT receive cached events immediately
        XCTAssertEqual(receivedEvents.count, 0, "NetworkOnly should not deliver cached events immediately")
        }
    }
    
    func testCacheOnlyPolicy() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
        // Arrange: Pre-populate cache
        var events: [NDKEvent] = []
        for i in 0..<4 {
            let event = try await self.createTestEvent(
                content: "Cache only event \(i)",
                pubkey: "test_pubkey"
            )
            events.append(event)
            try await self.cache.saveEvent(event)
        }
        
        let filter = NDKFilter(kinds: [1])
        
        // Act: Create data source with cacheOnly policy
        let dataSource = NDKSubscription(
            ndk: self.ndk,
            filter: filter,
            cachePolicy: .cacheOnly
        )
        
        // Collect events
        var receivedEvents: [NDKEvent] = []
        let collectTask = Task {
            for await event in dataSource.events {
                receivedEvents.append(event)
            }
        }
        
        // Wait for cache delivery and grouping window
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        collectTask.cancel()
        
        // Assert: Should receive cached events but no network request
        XCTAssertEqual(receivedEvents.count, 4, "Should receive all cached events")
    }
}