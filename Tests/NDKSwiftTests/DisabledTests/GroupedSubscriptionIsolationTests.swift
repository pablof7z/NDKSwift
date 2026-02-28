@testable import NDKSwiftCore
import XCTest

/// Tests to ensure subscription grouping doesn't cause cross-contamination of results
/// This is a regression test for ensuring that observers with similar filters
/// don't receive each other's events when subscriptions are grouped for efficiency
final class GroupedSubscriptionIsolationTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        // Reduce logging noise for tests
        NDKLogger.setLogLevel(.error)
    }

    /// Test that two observers with same kind but different authors don't mix results
    func testObserversWithDifferentAuthorsRemainIsolated() async throws {
        // Create NDK with in-memory cache
        let cache = try await NDKTestFactory.createTestCache()
        let ndk = NDK(cache: cache)

        // Define test pubkeys
        let author1 = "aaaa1111222233334444555566667777888899990000aaaabbbbccccddddeeff"
        let author2 = "bbbb1111222233334444555566667777888899990000aaaabbbbccccddddeeff"

        // Create filters for same kind but different authors
        let filter1 = NDKFilter(authors: [author1], kinds: [0])
        let filter2 = NDKFilter(authors: [author2], kinds: [0])

        // Create observers
        let observer1 = ndk.subscribe(filter: filter1, cachePolicy: .networkOnly)
        let observer2 = ndk.subscribe(filter: filter2, cachePolicy: .networkOnly)

        // Track received events
        var observer1Events: [NDKEvent] = []
        var observer2Events: [NDKEvent] = []

        // Start collecting events
        let task1 = Task {
            for await event in observer1.events {
                observer1Events.append(event)
                if observer1Events.count >= 2 {
                    break
                }
            }
        }

        let task2 = Task {
            for await event in observer2.events {
                observer2Events.append(event)
                if observer2Events.count >= 2 {
                    break
                }
            }
        }

        // Give subscriptions time to establish
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Create test events
        let event1a = NDKEvent(
            id: "event1a",
            pubkey: author1,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 0,
            tags: [],
            content: "Profile for author1",
            sig: "sig1a"
        )

        let event1b = NDKEvent(
            id: "event1b",
            pubkey: author1,
            createdAt: Timestamp(Date().timeIntervalSince1970 - 10),
            kind: 0,
            tags: [],
            content: "Older profile for author1",
            sig: "sig1b"
        )

        let event2a = NDKEvent(
            id: "event2a",
            pubkey: author2,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 0,
            tags: [],
            content: "Profile for author2",
            sig: "sig2a"
        )

        let event2b = NDKEvent(
            id: "event2b",
            pubkey: author2,
            createdAt: Timestamp(Date().timeIntervalSince1970 - 10),
            kind: 0,
            tags: [],
            content: "Older profile for author2",
            sig: "sig2b"
        )

        // Simulate events being received by sending them to cache
        await cache.simulateEventReception([event1a, event1b, event2a, event2b])

        // Wait for events to be processed
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Cancel tasks
        task1.cancel()
        task2.cancel()

        // Validate results

        // Check Observer 1 only got author1's events
        XCTAssertGreaterThan(observer1Events.count, 0, "Observer 1 should receive events")
        for event in observer1Events {
            XCTAssertEqual(event.pubkey, author1, "Observer 1 should only receive events from author1")
        }

        // Check Observer 2 only got author2's events
        XCTAssertGreaterThan(observer2Events.count, 0, "Observer 2 should receive events")
        for event in observer2Events {
            XCTAssertEqual(event.pubkey, author2, "Observer 2 should only receive events from author2")
        }

        // Ensure no cross-contamination
        let observer1Authors = Set(observer1Events.map { $0.pubkey })
        let observer2Authors = Set(observer2Events.map { $0.pubkey })

        XCTAssertEqual(observer1Authors, [author1], "Observer 1 should only have events from author1")
        XCTAssertEqual(observer2Authors, [author2], "Observer 2 should only have events from author2")
    }

    /// Test multiple observers with overlapping filters
    func testOverlappingFiltersRemainIsolated() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let ndk = NDK(cache: cache)

        let author1 = "cccc1111222233334444555566667777888899990000aaaabbbbccccddddeeff"
        let author2 = "dddd1111222233334444555566667777888899990000aaaabbbbccccddddeeff"
        let author3 = "eeee1111222233334444555566667777888899990000aaaabbbbccccddddeeff"

        // Create overlapping filters
        let filter1 = NDKFilter(authors: [author1, author2], kinds: [1]) // Both authors
        let filter2 = NDKFilter(authors: [author2], kinds: [1]) // Only author2
        let filter3 = NDKFilter(authors: [author3], kinds: [1]) // Only author3

        let observer1 = ndk.subscribe(filter: filter1, cachePolicy: .networkOnly)
        let observer2 = ndk.subscribe(filter: filter2, cachePolicy: .networkOnly)
        let observer3 = ndk.subscribe(filter: filter3, cachePolicy: .networkOnly)

        var results1: [String] = [] // Track pubkeys
        var results2: [String] = []
        var results3: [String] = []

        let task1 = Task {
            for await event in observer1.events {
                results1.append(event.pubkey)
                if results1.count >= 3 { break }
            }
        }

        let task2 = Task {
            for await event in observer2.events {
                results2.append(event.pubkey)
                if results2.count >= 2 { break }
            }
        }

        let task3 = Task {
            for await event in observer3.events {
                results3.append(event.pubkey)
                if results3.count >= 1 { break }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Create test events
        let events = [
            NDKEvent(id: "e1", pubkey: author1, createdAt: 1000, kind: 1, tags: [], content: "From author1", sig: "s1"),
            NDKEvent(id: "e2", pubkey: author2, createdAt: 1001, kind: 1, tags: [], content: "From author2", sig: "s2"),
            NDKEvent(id: "e3", pubkey: author3, createdAt: 1002, kind: 1, tags: [], content: "From author3", sig: "s3"),
            NDKEvent(id: "e4", pubkey: author1, createdAt: 1003, kind: 1, tags: [], content: "Another from author1", sig: "s4"),
            NDKEvent(id: "e5", pubkey: author2, createdAt: 1004, kind: 1, tags: [], content: "Another from author2", sig: "s5"),
        ]

        await cache.simulateEventReception(events)
        try await Task.sleep(nanoseconds: 500_000_000)

        task1.cancel()
        task2.cancel()
        task3.cancel()

        // Validate results

        // Observer 1 should get events from author1 and author2 only
        let uniqueAuthors1 = Set(results1)
        XCTAssertTrue(uniqueAuthors1.isSubset(of: [author1, author2]),
                      "Observer 1 should only receive events from author1 and author2")
        XCTAssertFalse(results1.contains(author3),
                       "Observer 1 should NOT receive events from author3")

        // Observer 2 should get events from author2 only
        let uniqueAuthors2 = Set(results2)
        XCTAssertEqual(uniqueAuthors2, [author2],
                       "Observer 2 should only receive events from author2")

        // Observer 3 should get events from author3 only
        let uniqueAuthors3 = Set(results3)
        XCTAssertEqual(uniqueAuthors3, [author3],
                       "Observer 3 should only receive events from author3")
    }

    /// Test that tag filters don't cause cross-contamination
    func testTagFiltersRemainIsolated() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let ndk = NDK(cache: cache)

        let pubkey = "ffff1111222233334444555566667777888899990000aaaabbbbccccddddeeff"

        // Create filters with different tags
        let filter1 = NDKFilter(kinds: [1], tags: ["t": ["bitcoin"]])
        let filter2 = NDKFilter(kinds: [1], tags: ["t": ["nostr"]])

        let observer1 = ndk.subscribe(filter: filter1, cachePolicy: .networkOnly)
        let observer2 = ndk.subscribe(filter: filter2, cachePolicy: .networkOnly)

        var bitcoinEvents: [NDKEvent] = []
        var nostrEvents: [NDKEvent] = []

        let task1 = Task {
            for await event in observer1.events {
                bitcoinEvents.append(event)
                if bitcoinEvents.count >= 2 { break }
            }
        }

        let task2 = Task {
            for await event in observer2.events {
                nostrEvents.append(event)
                if nostrEvents.count >= 2 { break }
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Create events with different tags
        let events = [
            NDKEvent(id: "bt1", pubkey: pubkey, createdAt: 1000, kind: 1,
                     tags: [["t", "bitcoin"]], content: "Bitcoin post 1", sig: "sig1"),
            NDKEvent(id: "ns1", pubkey: pubkey, createdAt: 1001, kind: 1,
                     tags: [["t", "nostr"]], content: "Nostr post 1", sig: "sig2"),
            NDKEvent(id: "bt2", pubkey: pubkey, createdAt: 1002, kind: 1,
                     tags: [["t", "bitcoin"]], content: "Bitcoin post 2", sig: "sig3"),
            NDKEvent(id: "ns2", pubkey: pubkey, createdAt: 1003, kind: 1,
                     tags: [["t", "nostr"]], content: "Nostr post 2", sig: "sig4"),
            NDKEvent(id: "both", pubkey: pubkey, createdAt: 1004, kind: 1,
                     tags: [["t", "bitcoin"], ["t", "nostr"]], content: "Both tags", sig: "sig5"),
        ]

        await cache.simulateEventReception(events)
        try await Task.sleep(nanoseconds: 500_000_000)

        task1.cancel()
        task2.cancel()

        // Validate bitcoin events
        XCTAssertGreaterThan(bitcoinEvents.count, 0, "Should receive bitcoin-tagged events")
        for event in bitcoinEvents {
            let hasBitcoinTag = event.tags.contains { tag in
                tag.count >= 2 && tag[0] == "t" && tag[1] == "bitcoin"
            }
            XCTAssertTrue(hasBitcoinTag, "Bitcoin observer should only receive bitcoin-tagged events")
        }

        // Validate nostr events
        XCTAssertGreaterThan(nostrEvents.count, 0, "Should receive nostr-tagged events")
        for event in nostrEvents {
            let hasNostrTag = event.tags.contains { tag in
                tag.count >= 2 && tag[0] == "t" && tag[1] == "nostr"
            }
            XCTAssertTrue(hasNostrTag, "Nostr observer should only receive nostr-tagged events")
        }

        // Check for specific cross-contamination
        let bitcoinOnlyEvents = bitcoinEvents.filter { event in
            !event.tags.contains { $0.count >= 2 && $0[0] == "t" && $0[1] == "nostr" }
        }
        let nostrOnlyEvents = nostrEvents.filter { event in
            !event.tags.contains { $0.count >= 2 && $0[0] == "t" && $0[1] == "bitcoin" }
        }

        // Ensure pure bitcoin events don't appear in nostr observer
        for event in bitcoinOnlyEvents {
            XCTAssertFalse(nostrEvents.contains { $0.id == event.id },
                           "Pure bitcoin events should not appear in nostr observer")
        }

        // Ensure pure nostr events don't appear in bitcoin observer
        for event in nostrOnlyEvents {
            XCTAssertFalse(bitcoinEvents.contains { $0.id == event.id },
                           "Pure nostr events should not appear in bitcoin observer")
        }
    }

    /// Test rapid subscription creation and cancellation
    func testRapidSubscriptionLifecycle() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let ndk = NDK(cache: cache)

        let authors = (0 ..< 5).map { i in
            "author\(i)1111222233334444555566667777888899990000aaaabbbbccccddddeeff"
        }

        // Create and cancel subscriptions rapidly
        for i in 0 ..< 10 {
            let author = authors[i % authors.count]
            let filter = NDKFilter(authors: [author], kinds: [1])
            let observer = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)

            // Start observing
            let task = Task {
                var count = 0
                for await _ in observer.events {
                    count += 1
                    if count >= 1 { break }
                }
            }

            // Send an event for this author
            let event = NDKEvent(
                id: "rapid\(i)",
                pubkey: author,
                createdAt: Timestamp(i),
                kind: 1,
                tags: [],
                content: "Rapid test \(i)",
                sig: "sig\(i)"
            )

            await cache.simulateEventReception([event])

            // Quick cancel
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            task.cancel()
        }

        // Give time for any cleanup
        try await Task.sleep(nanoseconds: 100_000_000)

        // Test passes if no crash or hang occurs
        XCTAssertTrue(true, "Rapid subscription lifecycle completed without issues")
    }
}

// MARK: - Test Helper Extensions

extension MemoryCache {
    /// Test helper: Simulate events being received from the network
    func simulateEventReception(_ events: [NDKEvent]) async {
        for event in events {
            // Process the event through the cache which will notify observers
            try? await processEvent(event, from: "test://relay", subscriptionId: "test-sub")
        }
    }
}
