import XCTest
@testable import NDKSwift

final class WeakObserverTests: XCTestCase {
    
    // Test observer implementation
    class TestObserver: CacheObserver {
        let id: String
        var receivedEvents: [NDKEvent] = []
        
        init(id: String) {
            self.id = id
        }
        
        func handleEvent(_ event: NDKEvent) async {
            receivedEvents.append(event)
        }
    }
    
    func testWeakObserverUsesObjectIdentity() async throws {
        // Create two observers
        let observer1 = TestObserver(id: "1")
        let observer2 = TestObserver(id: "2")
        
        // Create WeakObserver wrappers
        let weak1a = WeakObserver(observer: observer1)
        let weak1b = WeakObserver(observer: observer1)
        let weak2 = WeakObserver(observer: observer2)
        
        // Test equality based on object identity
        XCTAssertEqual(weak1a, weak1b, "Same observer should produce equal WeakObservers")
        XCTAssertNotEqual(weak1a, weak2, "Different observers should produce different WeakObservers")
        
        // Test Set behavior - no duplicates for same observer
        var observerSet = Set<WeakObserver>()
        observerSet.insert(weak1a)
        observerSet.insert(weak1b)
        
        XCTAssertEqual(observerSet.count, 1, "Set should contain only one entry for the same observer")
        
        // Add different observer
        observerSet.insert(weak2)
        XCTAssertEqual(observerSet.count, 2, "Set should contain two entries for different observers")
    }
    
    func testMemoryCacheDoesNotCrashWithDuplicateObservers() async throws {
        // Create cache and observer
        let cache = MemoryCache()
        let observer = TestObserver(id: "test")
        
        // Create a filter
        let filter = NDKFilter(authors: ["test_author"], kinds: [1])
        
        // Add the same observer multiple times - should not crash
        let handle1 = await cache.observeEvents(matching: filter, observer: observer)
        let handle2 = await cache.observeEvents(matching: filter, observer: observer)
        
        // Verify we can add events without issues
        let testEvent = NDKEvent(
            id: "test_id",
            pubkey: "test_author",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test content",
            sig: "test_sig"
        )
        
        try await cache.saveEvent(testEvent)
        
        // Give notifications time to process
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        
        // Both handles should work, but observer should only receive event once
        // since it's the same observer registered twice
        XCTAssertEqual(observer.receivedEvents.count, 1, "Observer should receive event only once")
        
        // Clean up
        await handle1.cancel()
        await handle2.cancel()
    }
}