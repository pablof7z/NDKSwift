@testable import NDKSwiftCore
@testable import NDKSwiftSQLite
import XCTest

/// Performance tests for SQLite cache filtering optimization
final class SQLiteCachePerformanceTests: XCTestCase {
    var cache: NDKSQLiteCache!
    var tempDBPath: String!

    override func setUp() async throws {
        try await super.setUp()

        // Create temporary database path
        let tempDir = FileManager.default.temporaryDirectory
        tempDBPath = tempDir.appendingPathComponent("perf_test_\(UUID().uuidString).db").path

        // Initialize cache with test database
        cache = try await NDKSQLiteCache(path: tempDBPath, debugMode: false)
    }

    override func tearDown() async throws {
        // Clean up temporary database
        try? FileManager.default.removeItem(atPath: tempDBPath)

        try await super.tearDown()
    }

    /// Test performance of eventMatchesFilter with simple filters (no tags)
    func testSimpleFilterPerformance() async throws {
        // Create and save test events
        let events = (0 ..< 100).map { i in
            NDKEvent(
                id: "event\(i)",
                pubkey: "author\(i % 10)",
                createdAt: Timestamp(1000 + i),
                kind: i % 5,
                tags: [],
                content: "Test event \(i)",
                sig: "sig\(i)"
            )
        }

        for event in events {
            try await cache.saveEvent(event)
        }

        // Create simple filters (no tags - should be fast)
        let simpleFilters = [
            NDKFilter(kinds: [1, 2, 3]),
            NDKFilter(authors: ["author1", "author2", "author3"]),
            NDKFilter(since: 1050),
            NDKFilter(until: 1080),
            NDKFilter(authors: ["author5"], kinds: [2]),
        ]

        // Measure performance
        let startTime = CFAbsoluteTimeGetCurrent()
        var matchCount = 0

        // Check each event against each filter
        for event in events {
            for filter in simpleFilters {
                if await cache.eventMatchesFilter(event, filter: filter) {
                    matchCount += 1
                }
            }
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime

        print("Simple filter performance: \(duration)s for \(events.count * simpleFilters.count) checks")
        print("Matches found: \(matchCount)")

        // With the optimization, this should be very fast (< 0.1s)
        XCTAssertLessThan(duration, 0.1, "Simple filter checks should be very fast")
    }

    /// Test that complex filters still work correctly (with tags)
    func testComplexFilterCorrectness() async throws {
        // Create events with tags
        let taggedEvents = [
            NDKEvent(
                id: "tagged1",
                pubkey: "author1",
                createdAt: 1000,
                kind: 1,
                tags: [["t", "nostr"], ["p", "pubkey1"]],
                content: "Tagged event 1",
                sig: "sig1"
            ),
            NDKEvent(
                id: "tagged2",
                pubkey: "author2",
                createdAt: 2000,
                kind: 1,
                tags: [["t", "bitcoin"], ["e", "event1"]],
                content: "Tagged event 2",
                sig: "sig2"
            ),
        ]

        for event in taggedEvents {
            try await cache.saveEvent(event)
        }

        // Create complex filter with tags
        var complexFilter = NDKFilter(kinds: [1])
        complexFilter.addTagFilter("t", values: ["nostr"])

        // Test that the optimization still correctly handles tag filters
        let match1 = await cache.eventMatchesFilter(taggedEvents[0], filter: complexFilter)
        let match2 = await cache.eventMatchesFilter(taggedEvents[1], filter: complexFilter)

        XCTAssertTrue(match1, "Event with 'nostr' tag should match")
        XCTAssertFalse(match2, "Event without 'nostr' tag should not match")
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
