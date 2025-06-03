import XCTest
@testable import NDKSwift

final class LRUCacheTests: XCTestCase {
    
    func testBasicOperations() async {
        let cache = LRUCache<String, String>(capacity: 3)
        
        // Test set and get
        await cache.set("key1", value: "value1")
        let value1 = await cache.get("key1")
        XCTAssertEqual(value1, "value1")
        
        // Test non-existent key
        let nonExistent = await cache.get("nonExistent")
        XCTAssertNil(nonExistent)
    }
    
    func testCapacityEviction() async {
        let cache = LRUCache<String, String>(capacity: 3)
        
        // Fill cache to capacity
        await cache.set("key1", value: "value1")
        await cache.set("key2", value: "value2")
        await cache.set("key3", value: "value3")
        
        // Add one more - should evict key1 (least recently used)
        await cache.set("key4", value: "value4")
        
        let value1 = await cache.get("key1")
        XCTAssertNil(value1, "key1 should have been evicted")
        
        let value4 = await cache.get("key4")
        XCTAssertEqual(value4, "value4")
    }
    
    func testLRUOrdering() async {
        let cache = LRUCache<String, String>(capacity: 3)
        
        // Add three items
        await cache.set("key1", value: "value1")
        await cache.set("key2", value: "value2")
        await cache.set("key3", value: "value3")
        
        // Access key1 to make it recently used
        _ = await cache.get("key1")
        
        // Add key4 - should evict key2 (now least recently used)
        await cache.set("key4", value: "value4")
        
        let value1 = await cache.get("key1")
        XCTAssertEqual(value1, "value1", "key1 should still be in cache")
        
        let value2 = await cache.get("key2")
        XCTAssertNil(value2, "key2 should have been evicted")
    }
    
    func testTTLExpiration() async {
        let cache = LRUCache<String, String>(capacity: 10, defaultTTL: 0.1) // 100ms TTL
        
        await cache.set("key1", value: "value1")
        
        // Should be available immediately
        let value1 = await cache.get("key1")
        XCTAssertEqual(value1, "value1")
        
        // Wait for expiration
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let expiredValue = await cache.get("key1")
        XCTAssertNil(expiredValue, "Value should have expired")
    }
    
    func testCustomTTL() async {
        let cache = LRUCache<String, String>(capacity: 10)
        
        // Set with custom TTL
        await cache.set("key1", value: "value1", ttl: 0.1)
        await cache.set("key2", value: "value2", ttl: 1.0)
        
        // Wait 200ms
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        let value1 = await cache.get("key1")
        XCTAssertNil(value1, "key1 should have expired")
        
        let value2 = await cache.get("key2")
        XCTAssertEqual(value2, "value2", "key2 should still be valid")
    }
    
    func testRemove() async {
        let cache = LRUCache<String, String>(capacity: 10)
        
        await cache.set("key1", value: "value1")
        await cache.set("key2", value: "value2")
        
        await cache.remove("key1")
        
        let value1 = await cache.get("key1")
        XCTAssertNil(value1)
        
        let value2 = await cache.get("key2")
        XCTAssertEqual(value2, "value2")
    }
    
    func testClear() async {
        let cache = LRUCache<String, String>(capacity: 10)
        
        await cache.set("key1", value: "value1")
        await cache.set("key2", value: "value2")
        await cache.set("key3", value: "value3")
        
        await cache.clear()
        
        let value1 = await cache.get("key1")
        let value2 = await cache.get("key2")
        let value3 = await cache.get("key3")
        
        XCTAssertNil(value1)
        XCTAssertNil(value2)
        XCTAssertNil(value3)
    }
    
    func testAllValues() async {
        let cache = LRUCache<String, String>(capacity: 10)
        
        await cache.set("key1", value: "value1")
        await cache.set("key2", value: "value2")
        await cache.set("key3", value: "value3")
        
        let allValues = await cache.allValues()
        XCTAssertEqual(Set(allValues), Set(["value1", "value2", "value3"]))
    }
    
    func testAllItems() async {
        let cache = LRUCache<String, String>(capacity: 10)
        
        await cache.set("key1", value: "value1")
        await cache.set("key2", value: "value2")
        
        let allItems = await cache.allItems()
        let itemsDict = Dictionary(uniqueKeysWithValues: allItems)
        
        XCTAssertEqual(itemsDict["key1"], "value1")
        XCTAssertEqual(itemsDict["key2"], "value2")
        XCTAssertEqual(itemsDict.count, 2)
    }
    
    func testCleanupExpired() async {
        let cache = LRUCache<String, String>(capacity: 10)
        
        // Add items with different TTLs
        await cache.set("key1", value: "value1", ttl: 0.1)
        await cache.set("key2", value: "value2", ttl: 1.0)
        await cache.set("key3", value: "value3") // No TTL
        
        // Wait for first to expire
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        await cache.cleanupExpired()
        
        let allValues = await cache.allValues()
        XCTAssertEqual(Set(allValues), Set(["value2", "value3"]))
    }
    
    func testUpdateExistingKey() async {
        let cache = LRUCache<String, String>(capacity: 3)
        
        await cache.set("key1", value: "value1")
        await cache.set("key2", value: "value2")
        await cache.set("key3", value: "value3")
        
        // Update existing key
        await cache.set("key2", value: "updatedValue2")
        
        let value2 = await cache.get("key2")
        XCTAssertEqual(value2, "updatedValue2")
        
        // Should not affect capacity
        let allItems = await cache.allItems()
        XCTAssertEqual(allItems.count, 3)
    }
    
    func testConcurrentAccess() async {
        let cache = LRUCache<Int, String>(capacity: 100)
        
        // Concurrent writes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await cache.set(i, value: "value\(i)")
                }
            }
        }
        
        // Concurrent reads
        await withTaskGroup(of: String?.self) { group in
            for i in 0..<100 {
                group.addTask {
                    return await cache.get(i)
                }
            }
            
            var foundCount = 0
            for await value in group {
                if value != nil {
                    foundCount += 1
                }
            }
            
            XCTAssertEqual(foundCount, 100)
        }
    }
    
    func testZeroCapacity() async {
        let cache = LRUCache<String, String>(capacity: 0)
        
        await cache.set("key1", value: "value1")
        
        // Should immediately evict
        let value = await cache.get("key1")
        XCTAssertNil(value)
    }
}