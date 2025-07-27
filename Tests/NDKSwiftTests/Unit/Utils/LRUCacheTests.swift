import XCTest
@testable import NDKSwift

final class LRUCacheTests: XCTestCase {
    
    func testBasicSetAndGet() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        await cache.set("key3", value: 3)
        
        let value1 = await cache.get("key1")
        let value2 = await cache.get("key2")
        let value3 = await cache.get("key3")
        
        XCTAssertEqual(value1, 1)
        XCTAssertEqual(value2, 2)
        XCTAssertEqual(value3, 3)
    }
    
    func testCapacityEviction() async {
        let cache = LRUCache<String, Int>(capacity: 2)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        await cache.set("key3", value: 3) // Should evict key1
        
        let value1 = await cache.get("key1")
        let value2 = await cache.get("key2")
        let value3 = await cache.get("key3")
        
        XCTAssertNil(value1) // Should be evicted
        XCTAssertEqual(value2, 2)
        XCTAssertEqual(value3, 3)
    }
    
    func testLRUOrdering() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        await cache.set("key3", value: 3)
        
        // Access key1 to make it recently used
        _ = await cache.get("key1")
        
        // Add key4, should evict key2 (least recently used)
        await cache.set("key4", value: 4)
        
        let value1 = await cache.get("key1")
        let value2 = await cache.get("key2")
        let value3 = await cache.get("key3")
        let value4 = await cache.get("key4")
        
        XCTAssertEqual(value1, 1)
        XCTAssertNil(value2) // Should be evicted
        XCTAssertEqual(value3, 3)
        XCTAssertEqual(value4, 4)
    }
    
    func testTTLExpiration() async {
        let cache = LRUCache<String, Int>(capacity: 10, defaultTTL: 0.1) // 100ms TTL
        
        await cache.set("key1", value: 1)
        let value1 = await cache.get("key1")
        XCTAssertEqual(value1, 1)
        
        // Wait for expiration
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        let expiredValue = await cache.get("key1")
        XCTAssertNil(expiredValue)
    }
    
    func testCustomTTL() async {
        let cache = LRUCache<String, Int>(capacity: 10, defaultTTL: 1.0)
        
        // Set with custom TTL
        await cache.set("key1", value: 1, ttl: 0.1) // 100ms TTL
        await cache.set("key2", value: 2) // Uses default TTL
        
        // Wait for key1 to expire but not key2
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        let value1 = await cache.get("key1")
        let value2 = await cache.get("key2")
        
        XCTAssertNil(value1) // Should be expired
        XCTAssertEqual(value2, 2) // Should still be valid
    }
    
    func testDelete() async {
        let cache = LRUCache<String, Int>(capacity: 10)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        
        await cache.delete("key1")
        
        let value1 = await cache.get("key1")
        let value2 = await cache.get("key2")
        
        XCTAssertNil(value1)
        XCTAssertEqual(value2, 2)
    }
    
    func testClear() async {
        let cache = LRUCache<String, Int>(capacity: 10)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        await cache.set("key3", value: 3)
        
        await cache.clear()
        
        let value1 = await cache.get("key1")
        let value2 = await cache.get("key2")
        let value3 = await cache.get("key3")
        
        XCTAssertNil(value1)
        XCTAssertNil(value2)
        XCTAssertNil(value3)
    }
    
    func testHitRate() async {
        let cache = LRUCache<String, Int>(capacity: 10)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        
        // 2 hits
        _ = await cache.get("key1")
        _ = await cache.get("key2")
        
        // 2 misses
        _ = await cache.get("key3")
        _ = await cache.get("key4")
        
        let hitRate = await cache.getHitRate()
        XCTAssertEqual(hitRate, 0.5) // 2 hits / 4 total = 0.5
    }
    
    func testAllItems() async {
        let cache = LRUCache<String, Int>(capacity: 10)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        await cache.set("key3", value: 3)
        
        let allItems = await cache.allItems()
        
        XCTAssertEqual(allItems.count, 3)
        XCTAssertEqual(allItems["key1"], 1)
        XCTAssertEqual(allItems["key2"], 2)
        XCTAssertEqual(allItems["key3"], 3)
    }
    
    func testUpdateExistingKey() async {
        let cache = LRUCache<String, Int>(capacity: 3)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        await cache.set("key3", value: 3)
        
        // Update key1 with new value
        await cache.set("key1", value: 10)
        
        // Add key4, should evict key2 (since key1 was recently updated)
        await cache.set("key4", value: 4)
        
        let value1 = await cache.get("key1")
        let value2 = await cache.get("key2")
        let value3 = await cache.get("key3")
        let value4 = await cache.get("key4")
        
        XCTAssertEqual(value1, 10) // Updated value
        XCTAssertNil(value2) // Should be evicted
        XCTAssertEqual(value3, 3)
        XCTAssertEqual(value4, 4)
    }
    
    func testGetAllKeys() async {
        let cache = LRUCache<String, Int>(capacity: 10)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        await cache.set("key3", value: 3)
        
        let keys = await cache.getAllKeys()
        
        XCTAssertEqual(keys.count, 3)
        XCTAssertTrue(keys.contains("key1"))
        XCTAssertTrue(keys.contains("key2"))
        XCTAssertTrue(keys.contains("key3"))
    }
    
    func testCleanupExpired() async {
        let cache = LRUCache<String, Int>(capacity: 10, defaultTTL: 0.1)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2, ttl: 1.0) // Longer TTL
        
        // Wait for key1 to expire
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        await cache.cleanupExpired()
        
        let allItems = await cache.allItems()
        XCTAssertEqual(allItems.count, 1)
        XCTAssertNil(allItems["key1"])
        XCTAssertEqual(allItems["key2"], 2)
    }
    
    func testZeroCapacity() async {
        let cache = LRUCache<String, Int>(capacity: 0)
        
        await cache.set("key1", value: 1)
        
        let value = await cache.get("key1")
        XCTAssertNil(value) // Should not store anything with 0 capacity
    }
    
    func testConcurrentAccess() async {
        let cache = LRUCache<Int, String>(capacity: 100)
        
        // Test concurrent writes and reads
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<50 {
                group.addTask {
                    await cache.set(i, value: "value\(i)")
                }
            }
            
            // Readers
            for i in 0..<50 {
                group.addTask {
                    _ = await cache.get(i)
                }
            }
        }
        
        // Verify some values are present
        let allItems = await cache.allItems()
        XCTAssertGreaterThan(allItems.count, 0)
        XCTAssertLessThanOrEqual(allItems.count, 100)
    }
    
    func testHitRateWithNoAccess() async {
        let cache = LRUCache<String, Int>(capacity: 10)
        
        let hitRate = await cache.getHitRate()
        XCTAssertEqual(hitRate, 0.0)
    }
    
    func testExpiredEntriesEviction() async {
        let cache = LRUCache<String, Int>(capacity: 2, defaultTTL: 0.1)
        
        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        
        // Wait for both to expire
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        // Add new items - expired entries should be evicted first
        await cache.set("key3", value: 3)
        await cache.set("key4", value: 4)
        
        let allItems = await cache.allItems()
        XCTAssertEqual(allItems.count, 2)
        XCTAssertEqual(allItems["key3"], 3)
        XCTAssertEqual(allItems["key4"], 4)
    }
}