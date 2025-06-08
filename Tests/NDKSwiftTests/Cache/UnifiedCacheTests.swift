import XCTest
@testable import NDKSwift

final class UnifiedCacheTests: XCTestCase {
    
    override func tearDown() async throws {
        // Clean up test cache directories
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_cache")
        try? FileManager.default.removeItem(at: cacheDir)
    }
    
    // MARK: - Memory Cache Layer Tests
    
    func testMemoryCacheBasicOperations() async throws {
        let cache = MemoryCacheLayer(config: CacheLayerConfig(maxSize: 10))
        
        // Test set and get
        try await cache.set("key1", value: "value1", ttl: nil)
        let retrieved: String? = await cache.get("key1", type: String.self)
        XCTAssertEqual(retrieved, "value1")
        
        // Test contains
        XCTAssertTrue(await cache.contains("key1"))
        XCTAssertFalse(await cache.contains("nonexistent"))
        
        // Test remove
        await cache.remove("key1")
        XCTAssertFalse(await cache.contains("key1"))
        
        // Test clear
        try await cache.set("key2", value: "value2", ttl: nil)
        try await cache.set("key3", value: "value3", ttl: nil)
        await cache.clear()
        XCTAssertFalse(await cache.contains("key2"))
        XCTAssertFalse(await cache.contains("key3"))
    }
    
    func testMemoryCacheTTL() async throws {
        let cache = MemoryCacheLayer()
        
        // Set with TTL
        try await cache.set("ttl_key", value: "ttl_value", ttl: 0.1) // 100ms
        
        // Should exist immediately
        XCTAssertNotNil(await cache.get("ttl_key", type: String.self))
        
        // Wait for expiration
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Should be expired
        XCTAssertNil(await cache.get("ttl_key", type: String.self))
    }
    
    func testMemoryCacheStatistics() async throws {
        let cache = MemoryCacheLayer(config: CacheLayerConfig(maxSize: 5))
        
        // Initial stats
        var stats = await cache.statistics()
        XCTAssertEqual(stats.hits, 0)
        XCTAssertEqual(stats.misses, 0)
        XCTAssertEqual(stats.currentSize, 0)
        
        // Add items and test hits/misses
        try await cache.set("key1", value: "value1", ttl: nil)
        _ = await cache.get("key1", type: String.self) // Hit
        _ = await cache.get("key2", type: String.self) // Miss
        
        stats = await cache.statistics()
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hitRate, 0.5)
    }
    
    // MARK: - Disk Cache Layer Tests
    
    func testDiskCacheBasicOperations() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_cache")
        let cache = try DiskCacheLayer(baseURL: cacheDir)
        
        // Test set and get
        try await cache.set("key1", value: "value1", ttl: nil)
        let retrieved: String? = await cache.get("key1", type: String.self)
        XCTAssertEqual(retrieved, "value1")
        
        // Test persistence - create new cache instance
        let cache2 = try DiskCacheLayer(baseURL: cacheDir)
        let retrieved2: String? = await cache2.get("key1", type: String.self)
        XCTAssertEqual(retrieved2, "value1")
        
        // Test remove
        await cache2.remove("key1")
        XCTAssertFalse(await cache2.contains("key1"))
    }
    
    func testDiskCacheSizeEviction() async throws {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_cache_eviction")
        let cache = try DiskCacheLayer(
            baseURL: cacheDir,
            config: CacheLayerConfig(maxSize: 1000) // Small size for testing
        )
        
        // Add items until eviction occurs
        for i in 0..<10 {
            let value = String(repeating: "x", count: 200) // ~200 bytes each
            try await cache.set("key\(i)", value: value, ttl: nil)
        }
        
        // Check that eviction occurred
        let stats = await cache.statistics()
        XCTAssertGreaterThan(stats.evictions, 0)
        XCTAssertLessThanOrEqual(stats.currentSize, 1000)
    }
    
    // MARK: - Layered Cache Tests
    
    func testLayeredCacheWriteThrough() async throws {
        let memoryCache = MemoryCacheLayer()
        let diskDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_layered")
        let diskCache = try DiskCacheLayer(baseURL: diskDir)
        
        let layeredCache = LayeredCache(layers: [memoryCache, diskCache], writeThrough: true)
        
        // Set value
        try await layeredCache.set("key1", value: "value1")
        
        // Both layers should have the value
        XCTAssertNotNil(await memoryCache.get("key1", type: String.self))
        XCTAssertNotNil(await diskCache.get("key1", type: String.self))
        
        // Clear memory cache
        await memoryCache.clear()
        
        // Layered cache should still find it in disk
        let retrieved: String? = await layeredCache.get("key1", type: String.self)
        XCTAssertEqual(retrieved, "value1")
        
        // Memory cache should be repopulated (write-through on read)
        XCTAssertNotNil(await memoryCache.get("key1", type: String.self))
    }
    
    func testLayeredCacheNoWriteThrough() async throws {
        let memoryCache = MemoryCacheLayer()
        let diskDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_layered_no_wt")
        let diskCache = try DiskCacheLayer(baseURL: diskDir)
        
        let layeredCache = LayeredCache(layers: [memoryCache, diskCache], writeThrough: false)
        
        // Set value
        try await layeredCache.set("key1", value: "value1")
        
        // Only first layer should have the value
        XCTAssertNotNil(await memoryCache.get("key1", type: String.self))
        XCTAssertNil(await diskCache.get("key1", type: String.self))
    }
    
    // MARK: - Unified Cache Adapter Tests
    
    func testUnifiedCacheAdapterEvents() async throws {
        let adapter = await UnifiedCacheAdapter()
        
        // Create test event
        let event = createMockEvent(id: "test1", content: "Hello")
        
        // Save event
        try await adapter.saveEvent(event)
        
        // Retrieve event
        let retrieved = await adapter.event(by: "test1")
        XCTAssertEqual(retrieved?.id, "test1")
        XCTAssertEqual(retrieved?.content, "Hello")
        
        // Test filter by ID
        let filter = NDKFilter(ids: ["test1"])
        let events = await adapter.events(filter: filter)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "test1")
    }
    
    func testUnifiedCacheAdapterProfiles() async throws {
        let adapter = await UnifiedCacheAdapter()
        
        // Create test profile
        let profile = NDKUserProfile(
            name: "Test User",
            displayName: "Test",
            about: "Test profile",
            picture: "https://example.com/pic.jpg"
        )
        
        // Save profile
        try await adapter.setProfile(profile, for: "pubkey1")
        
        // Retrieve profile
        let retrieved = await adapter.profile(for: "pubkey1")
        XCTAssertEqual(retrieved?.name, "Test User")
        XCTAssertEqual(retrieved?.displayName, "Test")
    }
    
    func testUnifiedCacheAdapterNIP05() async throws {
        let adapter = await UnifiedCacheAdapter()
        
        // Save NIP-05
        await adapter.saveNip05("test@example.com", pubkey: "pubkey1", relays: ["wss://relay1.com", "wss://relay2.com"])
        
        // Retrieve NIP-05
        let retrieved = await adapter.loadNip05("test@example.com")
        XCTAssertEqual(retrieved?.pubkey, "pubkey1")
        XCTAssertEqual(retrieved?.relays.count, 2)
        
        // Test case insensitive
        let retrieved2 = await adapter.loadNip05("TEST@EXAMPLE.COM")
        XCTAssertNotNil(retrieved2)
    }
    
    func testUnifiedCacheAdapterOutbox() async throws {
        let adapter = await UnifiedCacheAdapter()
        
        // Create test event
        let event = createMockEvent(id: "unpub1", content: "Unpublished")
        
        // Save unpublished event
        try await adapter.saveUnpublishedEvent(event, to: ["relay1", "relay2"])
        
        // Check unpublished events
        let allUnpublished = await adapter.unpublishedEvents()
        XCTAssertEqual(allUnpublished.count, 1)
        
        let relay1Unpublished = await adapter.unpublishedEvents(for: "relay1")
        XCTAssertEqual(relay1Unpublished.count, 1)
        
        // Mark as published to relay1
        try await adapter.markEventAsPublished("unpub1", to: "relay1")
        
        // Should still be in relay2
        let relay2Unpublished = await adapter.unpublishedEvents(for: "relay2")
        XCTAssertEqual(relay2Unpublished.count, 1)
        
        // Should not be in relay1 anymore
        let relay1After = await adapter.unpublishedEvents(for: "relay1")
        XCTAssertEqual(relay1After.count, 0)
    }
    
    func testCacheFactory() async throws {
        // Test standard cache creation
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_factory")
        let cache = try await CacheFactory.createStandardCache(
            diskURL: cacheDir,
            memorySize: 100,
            diskSize: 10000
        )
        
        // Test that it works
        try await cache.set("test", value: "value")
        let retrieved: String? = await cache.get("test", type: String.self)
        XCTAssertEqual(retrieved, "value")
        
        // Test memory-only cache
        let memCache = await CacheFactory.createMemoryCache(size: 50)
        try await memCache.set("mem", value: "memory")
        let memRetrieved: String? = await memCache.get("mem", type: String.self)
        XCTAssertEqual(memRetrieved, "memory")
    }
    
    // MARK: - Performance Tests
    
    func testLayeredCachePerformance() async throws {
        let cache = try await CacheFactory.createStandardCache(
            diskURL: FileManager.default.temporaryDirectory.appendingPathComponent("perf_test"),
            memorySize: 1000,
            diskSize: 10_000_000
        )
        
        // Measure write performance
        let writeStart = Date()
        for i in 0..<1000 {
            try await cache.set("key\(i)", value: "value\(i)")
        }
        let writeTime = Date().timeIntervalSince(writeStart)
        print("Write 1000 items: \(writeTime)s")
        
        // Measure read performance (should hit memory cache)
        let readStart = Date()
        for i in 0..<1000 {
            _ = await cache.get("key\(i)", type: String.self)
        }
        let readTime = Date().timeIntervalSince(readStart)
        print("Read 1000 items: \(readTime)s")
        
        XCTAssertLessThan(readTime, writeTime, "Reads should be faster than writes")
    }
    
    // MARK: - Helper Methods
    
    private func createMockEvent(id: String, content: String) -> NDKEvent {
        return NDKEvent(
            id: id,
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: content,
            sig: "test_sig"
        )
    }
}