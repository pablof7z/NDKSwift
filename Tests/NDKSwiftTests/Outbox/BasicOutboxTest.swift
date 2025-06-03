import XCTest
@testable import NDKSwift

final class BasicOutboxTest: XCTestCase {
    
    func testLRUCacheBasics() async throws {
        let cache = LRUCache<String, String>(capacity: 2, defaultTTL: 60)
        
        // Test set and get
        await cache.set("key1", value: "value1")
        let value1 = await cache.get("key1")
        XCTAssertEqual(value1, "value1")
        
        // Test capacity eviction
        await cache.set("key2", value: "value2")
        await cache.set("key3", value: "value3")
        
        // key1 should be evicted
        let evictedValue = await cache.get("key1")
        XCTAssertNil(evictedValue)
        
        // key2 and key3 should still be there
        let value2 = await cache.get("key2")
        XCTAssertEqual(value2, "value2")
        
        let value3 = await cache.get("key3")
        XCTAssertEqual(value3, "value3")
    }
    
    func testRelaySelection() async throws {
        let ndk = NDK()
        let tracker = NDKOutboxTracker(ndk: ndk)
        let ranker = NDKRelayRanker()
        let selector = NDKRelaySelector(
            ndk: ndk,
            tracker: tracker,
            ranker: ranker
        )
        
        // Create a test event
        let event = NDKEvent(ndk: ndk)
        event.kind = 1
        event.content = "Test message"
        event.pubkey = "test-pubkey"
        
        // Test relay selection
        let result = await selector.selectRelaysForPublishing(event: event)
        
        XCTAssertFalse(result.relays.isEmpty)
        XCTAssertNotNil(result.selectionMethod)
    }
}