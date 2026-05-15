@testable import NDKSwiftCore
import XCTest

final class NDKNostrDBCacheQueryFilterTests: XCTestCase {
    func testQueryEventsHonorsArbitraryTagFilters() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let targetAddress = "30023:pubkey:target"

        let matchingEvent = EventTestFactory.createEvent(
            kind: EventKind.longFormContent,
            content: "matching",
            tags: [["a", targetAddress]],
            createdAt: Timestamp.now - 10
        )
        let nonMatchingNewerEvent = EventTestFactory.createEvent(
            kind: EventKind.longFormContent,
            content: "newer non-match",
            tags: [["a", "30023:pubkey:other"]],
            createdAt: Timestamp.now
        )
        let untaggedEvent = EventTestFactory.createEvent(
            kind: EventKind.longFormContent,
            content: "untagged",
            createdAt: Timestamp.now - 5
        )

        try await cache.saveEvent(matchingEvent)
        try await cache.saveEvent(nonMatchingNewerEvent)
        try await cache.saveEvent(untaggedEvent)

        let filter = NDKFilter(
            kinds: [EventKind.longFormContent],
            limit: 1,
            tags: ["a": [targetAddress]]
        )

        let results = try await cache.queryEvents(filter)

        XCTAssertEqual(results.map(\.id), [matchingEvent.id])
    }
}
