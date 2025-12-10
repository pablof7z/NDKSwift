import XCTest
@testable import NDKSwiftCore
import NDKSwiftSQLite

/// Enhanced base class for NDKSwift unit tests with common setup
/// Provides pre-configured NDK instance, signer, and cache
open class NDKUnitTestCase: NDKTestCase {
    
    // MARK: - Pre-configured Properties
    
    /// Pre-configured NDK instance with memory cache
    var ndk: NDK!
    
    /// Pre-configured test signer
    var signer: NDKPrivateKeySigner!
    
    /// Pre-configured memory cache
    var cache: MemoryCache!
    
    /// Test user created from signer
    var testUser: TestUser!
    
    // MARK: - Setup & Teardown
    
    open override func setUp() async throws {
        try await super.setUp()
        
        // Create cache
        cache = MemoryCache()
        
        // Create signer
        signer = try NDKPrivateKeySigner.generate()
        
        // Create NDK instance
        ndk = NDK(cache: cache)
        ndk.signer = signer
        ndk.debugMode = false // Keep tests quiet by default
        
        // Create test user
        let pubkey = try await signer.pubkey
        testUser = TestUser(signer: signer, pubkey: pubkey)
    }
    
    open override func tearDown() async throws {
        // Ensure NDK is disconnected
        await ndk?.disconnect()
        
        // Clear cache
        try? await cache?.clear()
        
        // Nil out references
        ndk = nil
        signer = nil
        cache = nil
        testUser = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Common Test Operations
    
    /// Creates a test event with default values
    func createTestEvent(
        kind: Kind = 1,
        content: String = "Test event",
        tags: [Tag] = []
    ) -> NDKEvent {
        return EventTestFactory.createEvent(
            kind: kind,
            content: content,
            tags: tags,
            pubkey: testUser.pubkey
        )
    }
    
    /// Creates and signs a test event
    func createSignedTestEvent(
        kind: Kind = 1,
        content: String = "Test event",
        tags: [Tag] = []
    ) async throws -> NDKEvent {
        return try await EventTestFactory.createSignedEvent(
            ndk: ndk,
            kind: kind,
            content: content,
            tags: tags,
            signer: signer
        )
    }
    
    /// Creates another test user with signer
    func createOtherTestUser(name: String = "Other User") async throws -> TestUser {
        return try await UserTestFactory.createUser(name: name)
    }
    
    /// Adds a mock relay to NDK
    @discardableResult
    func addMockRelay(url: String = "wss://mock.relay.test") async -> MockRelay {
        let relay = MockRelay(url: url)
        await ndk.addRelay(url)
        // Note: In real implementation, you'd need to inject the mock relay
        // This is a simplified version for demonstration
        return relay
    }
    
    /// Creates and caches test events
    func cacheTestEvents(count: Int = 5) async throws -> [NDKEvent] {
        var events: [NDKEvent] = []
        
        for i in 0..<count {
            let event = createTestEvent(
                content: "Cached test event #\(i)"
            )
            try await cache.saveEvent(event)
            events.append(event)
        }
        
        return events
    }
    
    /// Verifies event exists in cache
    func assertEventInCache(
        _ event: NDKEvent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent, "Event \(event.id) not found in cache", file: file, line: line)
        XCTAssertEqual(cachedEvent?.id, event.id, file: file, line: line)
    }
    
    /// Verifies event does not exist in cache
    func assertEventNotInCache(
        _ eventId: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let cachedEvent = await cache.getEvent(id: eventId)
        XCTAssertNil(cachedEvent, "Event \(eventId) should not be in cache", file: file, line: line)
    }
}

// MARK: - NDK Mock Test Case

/// Base class for tests that need mock relay functionality
open class NDKMockTestCase: NDKUnitTestCase {
    
    /// Collection of mock relays
    var mockRelays: [MockRelay] = []
    
    open override func setUp() async throws {
        try await super.setUp()
        
        // Create NDK with custom pool that supports mock injection
        // Note: This would require NDK to support relay injection for testing
    }
    
    open override func tearDown() async throws {
        mockRelays.removeAll()
        try await super.tearDown()
    }
    
    /// Adds a mock relay with custom behavior
    func addConfiguredMockRelay(
        url: String = "wss://mock.relay.test",
        shouldFailPublish: Bool = false,
        publishDelay: TimeInterval = 0,
        autoRespond: Bool = true
    ) -> MockRelay {
        let relay = RelayTestFactory.createMockRelay(
            url: url,
            shouldFailPublish: shouldFailPublish,
            publishDelay: publishDelay
        )
        mockRelays.append(relay)
        
        // Note: In real implementation, inject mock into NDK pool
        return relay
    }
    
    /// Simulates receiving an event from a mock relay
    func simulateEventFromRelay(
        _ event: NDKEvent,
        relay: MockRelay,
        subscriptionId: String = "test-sub"
    ) async {
        // Note: This would require mock relay to have a method to inject events
        // relay.simulateEvent(event, forSubscription: subscriptionId)
    }
    
    /// Simulates EOSE from a mock relay
    func simulateEOSEFromRelay(
        relay: MockRelay,
        subscriptionId: String = "test-sub"
    ) async {
        // Note: This would require mock relay to have a method to inject EOSE
        // relay.simulateEOSE(forSubscription: subscriptionId)
    }
}

// MARK: - NDK Cache Test Case

/// Base class for cache-specific tests
open class NDKCacheTestCase: NDKUnitTestCase {
    
    /// SQLite cache for testing persistence
    var sqliteCache: NDKSQLiteCache?
    
    /// Path to SQLite database
    var dbPath: String!
    
    open override func setUp() async throws {
        try await super.setUp()
        
        // Create SQLite cache for persistence tests
        dbPath = tempDirectory
            .appendingPathComponent("test-cache.db")
            .path
        
        sqliteCache = try await NDKSQLiteCache(path: dbPath)
    }
    
    open override func tearDown() async throws {
        // Clean up SQLite cache
        if let sqliteCache = sqliteCache {
            try await sqliteCache.clear()
        }
        sqliteCache = nil
        
        // Remove database file
        if let dbPath = dbPath {
            try? FileManager.default.removeItem(atPath: dbPath)
        }
        
        try await super.tearDown()
    }
    
    /// Tests both memory and SQLite caches with the same operation
    func testWithBothCaches<T>(
        operation: (NDKCache) async throws -> T
    ) async throws -> (memory: T, sqlite: T) {
        let memoryResult = try await operation(cache)
        let sqliteResult = try await operation(sqliteCache!)
        return (memoryResult, sqliteResult)
    }
    
    /// Populates cache with test data
    func populateCache(
        _ cache: NDKCache,
        eventCount: Int = 10,
        userCount: Int = 3
    ) async throws -> (events: [NDKEvent], users: [TestUser]) {
        let users = try await UserTestFactory.createUsers(count: userCount)
        var events: [NDKEvent] = []
        
        for i in 0..<eventCount {
            let user = users[i % users.count]
            let event = EventTestFactory.createEvent(
                content: "Test event #\(i)",
                pubkey: user.pubkey
            )
            try await cache.saveEvent(event)
            events.append(event)
        }
        
        return (events, users)
    }
}