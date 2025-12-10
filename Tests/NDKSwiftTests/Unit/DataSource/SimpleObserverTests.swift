import XCTest
@testable import NDKSwiftCore

final class SimpleObserverTest: XCTestCase {
    
    func testSimpleObserverWithCache() async throws {
        // Create a test keypair and signer
        let signer = try NDKPrivateKeySigner.generate()
        let testPubkey = try await signer.pubkey
        
        // Initialize NDK with in-memory cache
        let cache = MemoryCache()
        let ndk = NDK(cache: cache)
        ndk.signer = signer
        ndk.debugMode = true
        ndk.outboxEnabled = false  // Disable outbox to avoid relay fetching
        
        // Create filter for kind:1 notes from our test pubkey
        let filter = NDKFilter(
            authors: [testPubkey],
            kinds: [1]
        )
        
        print("=== TEST START ===")
        print("Filter: authors=[\(testPubkey)], kinds=[1]")
        
        // Create observer
        print("Creating observer...")
        let observer = ndk.subscribe(
            filter: filter,
            maxAge: 0  // Real-time updates only
        )
        
        // Track received events
        var receivedEvents: [NDKEvent] = []
        
        // Start monitoring in a task
        let observerTask = Task {
            print("Observer task started")
            for await event in observer.events {
                print("Observer received event: \(event.id)")
                receivedEvents.append(event)
            }
            print("Observer task ended")
        }
        
        // Give observer time to register
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        print("Observer should be registered now")
        
        // Create and publish test event
        print("Creating test event...")
        let (event1, _) = try await ndk.publish { builder in
            builder
                .content("Test note")
                .kind(1)
        }
        print("Event created: id=\(event1.id), kind=\(event1.kind), author=\(event1.pubkey)")
        
        // Manually save to cache
        print("Saving event to cache...")
        try await cache.saveEvent(event1)
        print("Event saved to cache")
        
        // Wait for propagation
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        print("Waited for propagation")
        
        // Check results
        print("Received events count: \(receivedEvents.count)")
        if receivedEvents.isEmpty {
            print("ERROR: No events received!")
            
            // Let's check if the event is in cache
            let cachedEvent = await cache.getEvent(id: event1.id)
            print("Event in cache: \(cachedEvent != nil)")
            
            // Let's check if filter matches
            if let cached = cachedEvent {
                print("Filter matches event: \(filter.matches(event: cached))")
            }
        } else {
            print("SUCCESS: Received \(receivedEvents.count) events")
        }
        
        // Clean up
        observerTask.cancel()
        
        XCTAssertEqual(receivedEvents.count, 1, "Should have received 1 event")
        XCTAssertEqual(receivedEvents.first?.id, event1.id, "Should have received the correct event")
    }
}