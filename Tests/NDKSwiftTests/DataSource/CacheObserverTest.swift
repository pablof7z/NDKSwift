import XCTest
@testable import NDKSwift

// Simple test observer
class TestCacheObserver: CacheObserver {
    var receivedEvents: [NDKEvent] = []
    
    func handleEvent(_ event: NDKEvent) async {
        print("TestCacheObserver: Received event \(event.id)")
        receivedEvents.append(event)
    }
}

final class CacheObserverTest: XCTestCase {
    
    func testDirectCacheObserver() async throws {
        print("=== DIRECT CACHE OBSERVER TEST ===")
        
        // Create cache
        let cache = MemoryCache()
        
        // Create test event
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        
        let builder = NDKEventBuilder()
            .content("Test event")
            .kind(1)
        
        let event = try await builder.build(signer: signer)
        
        // Create filter matching our event
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [1]
        )
        
        // Create observer
        let observer = TestCacheObserver()
        
        // Register observer with cache
        print("Registering observer with cache...")
        let handle = await cache.observeEvents(
            matching: filter,
            observer: observer
        )
        
        // Give it a moment
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Save event to cache
        print("Saving event to cache...")
        try await cache.saveEvent(event)
        
        // Wait for notification
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Check results
        print("Observer received \(observer.receivedEvents.count) events")
        XCTAssertEqual(observer.receivedEvents.count, 1, "Observer should have received 1 event")
        XCTAssertEqual(observer.receivedEvents.first?.id, event.id, "Should have received the correct event")
        
        // Clean up
        await handle.cancel()
    }
}