@testable import NDKSwift
import XCTest

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
        
        // Add some test relays
        let relay1 = ndk.addRelay("wss://relay1.test")
        let relay2 = ndk.addRelay("wss://relay2.test")
        let relay3 = ndk.addRelay("wss://relay3.test")
        
        let tracker = NDKOutboxTracker(ndk: ndk)
        let ranker = NDKRelayRanker(ndk: ndk, tracker: tracker)
        let selector = NDKRelaySelector(
            ndk: ndk,
            tracker: tracker,
            ranker: ranker
        )

        // Create a test event
        let event = NDKEvent(
            pubkey: "test-pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test message"
        )

        // Test relay selection
        let result = await selector.selectRelaysForPublishing(event: event)

        XCTAssertFalse(result.relays.isEmpty)
        XCTAssertNotNil(result.selectionMethod)
    }
}
