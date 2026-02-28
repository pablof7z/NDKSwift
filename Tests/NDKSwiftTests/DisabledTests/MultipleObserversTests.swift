@testable import NDKSwiftCore
import XCTest

final class MultipleObserversTests: XCTestCase {
    func testMultipleObserversOnSameFilterWithMaxAgeZero() async throws {
        // Create a test keypair and signer
        let signer = try NDKPrivateKeySigner.generate()
        let testPubkey = try await signer.pubkey

        // Initialize NDK with in-memory cache
        let cache = try await NDKTestFactory.createTestCache()
        let ndk = NDK(cache: cache, debugMode: true, outboxEnabled: false)
        ndk.signer = signer

        // Create filter for kind:1 notes from our test pubkey
        let filter = NDKFilter(
            authors: [testPubkey],
            kinds: [1]
        )

        // Create first observer with maxAge: 0
        print("Creating observer1 with filter: \(filter)")
        let observer1 = ndk.subscribe(
            filter: filter,
            maxAge: 0 // Real-time updates only
        )

        // Create second observer with maxAge: 0
        print("Creating observer2 with filter: \(filter)")
        let observer2 = ndk.subscribe(
            filter: filter,
            maxAge: 0 // Real-time updates only
        )

        // Track received events
        var observer1Events: [NDKEvent] = []
        var observer2Events: [NDKEvent] = []

        // Start monitoring observer 1
        let observer1Task = Task {
            print("Observer1 task started, waiting for events...")
            for await event in observer1.events {
                print("Observer1 received event: \(event.id)")
                observer1Events.append(event)
            }
            print("Observer1 task ended")
        }

        // Start monitoring observer 2
        let observer2Task = Task {
            print("Observer2 task started, waiting for events...")
            for await event in observer2.events {
                print("Observer2 received event: \(event.id)")
                observer2Events.append(event)
            }
            print("Observer2 task ended")
        }

        // Give observers time to start
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Create and publish first test event
        let (event1, _) = try await ndk.publish { builder in
            builder
                .content("Test note 1 - Both observers should see this")
                .kind(1)
        }

        // Since we have no relays, inject the event directly into cache
        // This simulates what would happen if the event came from a relay
        print("Saving event1 to cache: \(event1.id), kind: \(event1.kind), author: \(event1.pubkey)")
        try await cache.saveEvent(event1)

        // Wait for event propagation through observers
        print("Waiting for event propagation...")
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Check both observers received the event
        XCTAssertEqual(observer1Events.count, 1, "Observer 1 should have received 1 event")
        XCTAssertEqual(observer2Events.count, 1, "Observer 2 should have received 1 event")
        XCTAssertEqual(observer1Events.first?.id, event1.id, "Observer 1 should have received the correct event")
        XCTAssertEqual(observer2Events.first?.id, event1.id, "Observer 2 should have received the correct event")

        // Cancel observer 1
        observer1Task.cancel()
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Create and publish second test event
        let (event2, _) = try await ndk.publish { builder in
            builder
                .content("Test note 2 - Only observer 2 should see this")
                .kind(1)
        }

        // Inject into cache
        try await cache.saveEvent(event2)

        // Wait for event propagation
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Check observer 2 still receives events while observer 1 doesn't
        XCTAssertEqual(observer1Events.count, 1, "Observer 1 should still have only 1 event (it was cancelled)")
        XCTAssertEqual(observer2Events.count, 2, "Observer 2 should have received 2 events")
        XCTAssertEqual(observer2Events[1].id, event2.id, "Observer 2 should have received the second event")

        // Cancel observer 2 (last observer with maxAge: 0)
        observer2Task.cancel()
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds to ensure cleanup

        // Verify that after all observers are cancelled, new events are not received
        // This indirectly confirms that subscriptions are cleaned up properly
        let (event3, _) = try await ndk.publish { builder in
            builder
                .content("Test note 3 - No observers should see this")
                .kind(1)
        }

        // Inject into cache
        try await cache.saveEvent(event3)

        // Wait to ensure no event propagation happens
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Verify no observers received the third event
        XCTAssertEqual(observer1Events.count, 1, "Observer 1 should still have only 1 event")
        XCTAssertEqual(observer2Events.count, 2, "Observer 2 should still have only 2 events")

        // The fact that no observer received event3 confirms that subscriptions were properly closed
    }

    func testMixedMaxAgeObservers() async throws {
        // Create a test keypair and signer
        let signer = try NDKPrivateKeySigner.generate()
        let testPubkey = try await signer.pubkey

        // Initialize NDK with in-memory cache
        let cache = try await NDKTestFactory.createTestCache()
        let ndk = NDK(cache: cache, debugMode: true, outboxEnabled: false)
        ndk.signer = signer

        // Create filter
        let filter = NDKFilter(
            authors: [testPubkey],
            kinds: [1]
        )

        // Create observer with maxAge: 0
        let realtimeObserver = ndk.subscribe(
            filter: filter,
            maxAge: 0 // Real-time updates only
        )

        // Create observer with maxAge > 0
        let cachedObserver = ndk.subscribe(
            filter: filter,
            maxAge: 3600 // 1 hour cache
        )

        var realtimeEvents: [NDKEvent] = []
        var cachedEvents: [NDKEvent] = []

        // Start monitoring realtime observer
        let realtimeTask = Task {
            for await event in realtimeObserver.events {
                realtimeEvents.append(event)
            }
        }

        // Start monitoring cached observer
        let cachedTask = Task {
            for await event in cachedObserver.events {
                cachedEvents.append(event)
            }
        }

        // Give observers time to start
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Create and publish test event
        let (event1, _) = try await ndk.publish { builder in
            builder
                .content("Test note for mixed observers")
                .kind(1)
        }

        // Inject into cache
        try await cache.saveEvent(event1)

        // Wait for event propagation
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Both observers should receive the event
        XCTAssertEqual(realtimeEvents.count, 1, "Realtime observer should have received 1 event")
        XCTAssertEqual(cachedEvents.count, 1, "Cached observer should have received 1 event")

        // Cancel realtime observer
        realtimeTask.cancel()
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Create and publish another event - cached observer should still receive it
        let (event2, _) = try await ndk.publish { builder in
            builder
                .content("Test note 2 - Only cached observer should see this")
                .kind(1)
        }

        // Inject into cache
        try await cache.saveEvent(event2)

        // Wait for event propagation
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Verify only cached observer received the second event
        XCTAssertEqual(realtimeEvents.count, 1, "Realtime observer should still have only 1 event (it was cancelled)")
        XCTAssertEqual(cachedEvents.count, 2, "Cached observer should have received 2 events")

        // Cancel cached observer
        cachedTask.cancel()
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        // Now subscription can be closed (implementation dependent - might stay open for cache)
        // This test just verifies the subscription management doesn't crash
    }
}
