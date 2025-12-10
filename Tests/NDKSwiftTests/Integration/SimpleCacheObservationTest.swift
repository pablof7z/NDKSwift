import XCTest
@testable import NDKSwiftCore
import NDKSwiftSQLite

final class SimpleCacheObservationTest: XCTestCase {
    
    func testCacheObservationActuallyWorks() async throws {
        // Create a simple in-memory test
        print("🧪 Testing cache observation...")
        
        // Create SQLite cache
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db").path
        let cache = try await NDKSQLiteCache(path: tempPath, debugMode: true)
        
        // Set up cache observation for all kind:1 events
        let cacheFilter = NDKFilter(kinds: [1])
        var observedEvents: [NDKEvent] = []
        
        let observationTask = Task {
            print("📡 Starting cache observation for kind:1 events...")
            let eventStream = await cache.observeEvents(
                matching: cacheFilter,
                includeExisting: true
            )
            
            do {
                for try await events in eventStream {
                    print("✅ Cache observer received \(events.count) events!")
                    observedEvents.append(contentsOf: events)
                }
            } catch {
                print("❌ Cache observation error: \(error)")
            }
        }
        
        // Give observer time to set up
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Now save a kind:1 event to the cache
        print("💾 Saving a kind:1 event to cache...")
        let testEvent = EventTestFactory.createEvent(
            kind: 1,
            content: "Hello from test!",
            pubkey: "test-author-12345"
        )
        
        try await cache.saveEvent(testEvent)
        print("✅ Event saved to cache")
        
        // Give time for observation to trigger
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Check results
        print("\n📊 Results:")
        print("   Events observed: \(observedEvents.count)")
        if !observedEvents.isEmpty {
            print("   ✅ SUCCESS! Cache observation is working!")
            for event in observedEvents {
                print("   - Event: \(event.content)")
            }
        } else {
            print("   ❌ FAILURE! No events were observed")
        }
        
        observationTask.cancel()
        
        XCTAssertFalse(observedEvents.isEmpty, "Cache observer should have received the saved event")
    }
}