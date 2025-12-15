@testable import NDKSwiftCore
@testable import NDKSwiftSQLite
import XCTest

/// Tests to ensure filtering logic consistency between SQL queries and in-memory checks
final class SQLiteCacheFilteringConsistencyTests: XCTestCase {
    var cache: NDKSQLiteCache!
    var tempDBPath: String!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary database path
        let tempDir = FileManager.default.temporaryDirectory
        tempDBPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db").path

        // Initialize cache with test database
        cache = try await NDKSQLiteCache(path: tempDBPath, debugMode: true)
    }

    override func tearDown() async throws {
        // Clean up temporary database
        try? FileManager.default.removeItem(atPath: tempDBPath)

        try await super.tearDown()
    }

    /// Test that eventMatchesFilter uses the same logic as queryEvents
    func testFilteringConsistency() async throws {
        // Create test events with various attributes
        let events = [
            NDKEvent(
                id: "event1",
                pubkey: "author1",
                createdAt: 1000,
                kind: 1,
                tags: [["t", "nostr"], ["p", "pubkey1"]],
                content: "Test event 1",
                sig: "sig1"
            ),
            NDKEvent(
                id: "event2",
                pubkey: "author2",
                createdAt: 2000,
                kind: 3,
                tags: [["t", "bitcoin"], ["e", "event1"]],
                content: "Test event 2",
                sig: "sig2"
            ),
            NDKEvent(
                id: "event3",
                pubkey: "author1",
                createdAt: 3000,
                kind: 1,
                tags: [["t", "nostr"], ["t", "bitcoin"]],
                content: "Test event 3",
                sig: "sig3"
            ),
        ]

        // Save all events to cache
        for event in events {
            try await cache.saveEvent(event)
        }

        // Test various filters
        var testFilters: [NDKFilter] = [
            NDKFilter(kinds: [1]),
            NDKFilter(authors: ["author1"]),
            NDKFilter(authors: ["author1"], kinds: [1]),
            NDKFilter(since: 1500),
            NDKFilter(until: 2500),
        ]

        // Add tag filters
        var filter1 = NDKFilter()
        filter1.addTagFilter("#t", values: ["nostr"])
        testFilters.append(filter1)

        var filter2 = NDKFilter()
        filter2.addTagFilter("#t", values: ["bitcoin"])
        testFilters.append(filter2)

        var filter3 = NDKFilter(kinds: [1])
        filter3.addTagFilter("#t", values: ["nostr"])
        testFilters.append(filter3)

        for filter in testFilters {
            // Get events using queryEvents (SQL-based)
            let queriedEvents = try await cache.queryEvents(filter)
            let queriedIds = Set(queriedEvents.map { $0.id })

            // Check each saved event using eventMatchesFilter
            var matchedIds = Set<String>()
            for event in events {
                if await cache.eventMatchesFilter(event, filter: filter) {
                    matchedIds.insert(event.id)
                }
            }

            // They should return the same set of events
            XCTAssertEqual(queriedIds, matchedIds,
                           "Filter \(filter.description) returned different results:\n" +
                               "queryEvents: \(queriedIds)\n" +
                               "eventMatchesFilter: \(matchedIds)")
        }
    }

    /// Test that observers receive the same events as direct queries
    func testObserverNotificationConsistency() async throws {
        // Set up filter
        let filter = NDKFilter(authors: ["testauthor"], kinds: [1])

        // Start observing
        let eventStream = await cache.observeEvents(matching: filter, includeExisting: false)

        // Create task to collect events
        var receivedEvents: [NDKEvent] = []
        let collectionTask = Task {
            do {
                for try await events in eventStream {
                    receivedEvents.append(contentsOf: events)
                }
            } catch {
                // Stream ended or error occurred
            }
        }

        // Create and process test event
        let matchingEvent = NDKEvent(
            id: "matching",
            pubkey: "testauthor",
            createdAt: 1000,
            kind: 1,
            tags: [],
            content: "This should match",
            sig: "sig1"
        )

        let nonMatchingEvent = NDKEvent(
            id: "nonmatching",
            pubkey: "otherauthor",
            createdAt: 1000,
            kind: 1,
            tags: [],
            content: "This should not match",
            sig: "sig2"
        )

        // Process events through cache
        try await cache.processEvent(matchingEvent, from: "wss://test", subscriptionId: "test")
        try await cache.processEvent(nonMatchingEvent, from: "wss://test", subscriptionId: "test")

        // Give time for notifications
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Query directly
        let queriedEvents = try await cache.queryEvents(filter)
        let queriedIds = Set(queriedEvents.map { $0.id })

        // Get notified events
        let notifiedIds = Set(receivedEvents.map { $0.id })

        // Should be the same
        XCTAssertEqual(queriedIds, notifiedIds,
                       "Observer received different events than query:\n" +
                           "Query returned: \(queriedIds)\n" +
                           "Observer received: \(notifiedIds)")

        // Clean up
        collectionTask.cancel()
    }

    /// Test edge cases in filtering
    func testFilteringEdgeCases() async throws {
        // Test empty filter (should match all)
        let emptyFilter = NDKFilter()

        let event = NDKEvent(
            id: "test",
            pubkey: "author",
            createdAt: 1000,
            kind: 1,
            tags: [],
            content: "Test",
            sig: "sig"
        )

        try await cache.saveEvent(event)

        // Empty filter should match the event
        let matches = await cache.eventMatchesFilter(event, filter: emptyFilter)
        XCTAssertTrue(matches, "Empty filter should match all events")

        // Query should also return the event
        let queried = try await cache.queryEvents(emptyFilter)
        XCTAssertEqual(queried.count, 1)
        XCTAssertEqual(queried.first?.id, event.id)
    }
}

// Add private extension to access the method for testing
// NOTE: Commented out to avoid redeclaration error - method is already accessible
// extension NDKSQLiteCache {
//     /// Expose eventMatchesFilter for testing
//     func eventMatchesFilter(_ event: NDKEvent, filter: NDKFilter) async -> Bool {
//         // This calls the private eventMatchesFilter method
//         await self.eventMatchesFilter(event, filter: filter)
//     }
// }
