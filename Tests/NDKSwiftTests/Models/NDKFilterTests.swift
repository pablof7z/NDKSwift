@testable import NDKSwift
import XCTest

final class NDKFilterTests: XCTestCase {
    func testFilterInitialization() {
        let filter = NDKFilter(
            ids: ["id1", "id2"],
            authors: ["author1", "author2"],
            kinds: [1, 2, 3],
            events: ["event1", "event2"],
            pubkeys: ["pubkey1", "pubkey2"],
            since: 1000,
            until: 2000,
            limit: 100
        )

        XCTAssertEqual(filter.ids, ["id1", "id2"])
        XCTAssertEqual(filter.authors, ["author1", "author2"])
        XCTAssertEqual(filter.kinds, [1, 2, 3])
        XCTAssertEqual(filter.events, ["event1", "event2"])
        XCTAssertEqual(filter.pubkeys, ["pubkey1", "pubkey2"])
        XCTAssertEqual(filter.since, 1000)
        XCTAssertEqual(filter.until, 2000)
        XCTAssertEqual(filter.limit, 100)
    }

    func testFilterCodable() throws {
        let originalFilter = NDKFilter(
            ids: ["id1"],
            authors: ["author1"],
            kinds: [1, 2],
            events: ["event1"],
            pubkeys: ["pubkey1"],
            since: 1000,
            until: 2000,
            limit: 50
        )

        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(originalFilter)
        let json = String(data: data, encoding: .utf8)!

        // Verify JSON structure
        XCTAssertTrue(json.contains("\"ids\":[\"id1\"]"))
        XCTAssertTrue(json.contains("\"authors\":[\"author1\"]"))
        XCTAssertTrue(json.contains("\"kinds\":[1,2]"))
        XCTAssertTrue(json.contains("\"#e\":[\"event1\"]"))
        XCTAssertTrue(json.contains("\"#p\":[\"pubkey1\"]"))
        XCTAssertTrue(json.contains("\"since\":1000"))
        XCTAssertTrue(json.contains("\"until\":2000"))
        XCTAssertTrue(json.contains("\"limit\":50"))

        // Decode
        let decoder = JSONDecoder()
        let decodedFilter = try decoder.decode(NDKFilter.self, from: data)

        XCTAssertEqual(decodedFilter, originalFilter)
    }

    func testFilterTagFilters() {
        var filter = NDKFilter()

        // Add tag filters
        filter.addTagFilter("t", values: ["nostr", "bitcoin"])
        filter.addTagFilter("r", values: ["https://example.com"])

        // Check tag filters
        XCTAssertEqual(filter.tagFilter("t"), ["nostr", "bitcoin"])
        XCTAssertEqual(filter.tagFilter("r"), ["https://example.com"])
        XCTAssertNil(filter.tagFilter("x"))
    }

    func testFilterMatching() {
        let filter = NDKFilter(
            authors: ["author123"],
            kinds: [1, 2],
            since: 1000,
            until: 2000
        )

        // Matching event
        let matchingEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 1500,
            kind: 1,
            content: "Test"
        )
        matchingEvent.id = "event123"
        XCTAssertTrue(filter.matches(event: matchingEvent))

        // Wrong author
        let wrongAuthorEvent = NDKEvent(
            pubkey: "author456",
            createdAt: 1500,
            kind: 1,
            content: "Test"
        )
        wrongAuthorEvent.id = "event456"
        XCTAssertFalse(filter.matches(event: wrongAuthorEvent))

        // Wrong kind
        let wrongKindEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 1500,
            kind: 3,
            content: "Test"
        )
        wrongKindEvent.id = "event789"
        XCTAssertFalse(filter.matches(event: wrongKindEvent))

        // Too early
        let tooEarlyEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 999,
            kind: 1,
            content: "Test"
        )
        tooEarlyEvent.id = "eventabc"
        XCTAssertFalse(filter.matches(event: tooEarlyEvent))

        // Too late
        let tooLateEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 2001,
            kind: 1,
            content: "Test"
        )
        tooLateEvent.id = "eventdef"
        XCTAssertFalse(filter.matches(event: tooLateEvent))
    }

    func testFilterMatchingWithTags() {
        var filter = NDKFilter()
        filter.events = ["referenced123"]
        filter.pubkeys = ["mentioned456"]

        // Event with matching tags
        let matchingEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 1500,
            kind: 1,
            tags: [
                ["e", "referenced123"],
                ["p", "mentioned456"],
            ],
            content: "Test"
        )
        XCTAssertTrue(filter.matches(event: matchingEvent))

        // Event with only one matching tag
        let partialMatchEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 1500,
            kind: 1,
            tags: [
                ["e", "referenced123"],
                ["p", "different789"],
            ],
            content: "Test"
        )
        XCTAssertFalse(filter.matches(event: partialMatchEvent))

        // Event with no matching tags
        let noMatchEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 1500,
            kind: 1,
            tags: [
                ["e", "different111"],
                ["p", "different222"],
            ],
            content: "Test"
        )
        XCTAssertFalse(filter.matches(event: noMatchEvent))
    }

    func testFilterMatchingWithGenericTags() {
        var filter = NDKFilter()
        filter.addTagFilter("t", values: ["nostr", "bitcoin"])

        // Event with matching tag
        let matchingEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 1500,
            kind: 1,
            tags: [
                ["t", "nostr"],
                ["t", "test"],
            ],
            content: "Test"
        )
        XCTAssertTrue(filter.matches(event: matchingEvent))

        // Event with different matching tag
        let matchingEvent2 = NDKEvent(
            pubkey: "author123",
            createdAt: 1500,
            kind: 1,
            tags: [
                ["t", "bitcoin"],
            ],
            content: "Test"
        )
        XCTAssertTrue(filter.matches(event: matchingEvent2))

        // Event with no matching tags
        let noMatchEvent = NDKEvent(
            pubkey: "author123",
            createdAt: 1500,
            kind: 1,
            tags: [
                ["t", "ethereum"],
                ["t", "defi"],
            ],
            content: "Test"
        )
        XCTAssertFalse(filter.matches(event: noMatchEvent))
    }

    func testFilterSpecificity() {
        let generalFilter = NDKFilter(
            kinds: [1]
        )

        let specificFilter = NDKFilter(
            ids: ["id1"],
            authors: ["author1"],
            kinds: [1],
            since: 1000,
            until: 2000,
            limit: 10
        )

        let mediumFilter = NDKFilter(
            authors: ["author1"],
            kinds: [1],
            limit: 100
        )

        XCTAssertTrue(specificFilter.isMoreSpecific(than: generalFilter))
        XCTAssertTrue(specificFilter.isMoreSpecific(than: mediumFilter))
        XCTAssertTrue(mediumFilter.isMoreSpecific(than: generalFilter))
        XCTAssertFalse(generalFilter.isMoreSpecific(than: specificFilter))
    }

    func testFilterMerging() {
        let filter1 = NDKFilter(
            authors: ["author1", "author2"],
            kinds: [1, 2, 3],
            since: 1000,
            until: 3000
        )

        let filter2 = NDKFilter(
            authors: ["author2", "author3"],
            kinds: [2, 3, 4],
            since: 2000,
            until: 4000
        )

        let merged = filter1.merged(with: filter2)

        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.authors, ["author2"]) // Intersection
        XCTAssertEqual(Set(merged?.kinds ?? []), Set([2, 3])) // Intersection
        XCTAssertEqual(merged?.since, 2000) // Max of since values
        XCTAssertEqual(merged?.until, 3000) // Min of until values

        // Test incompatible merge (no common authors)
        let filter3 = NDKFilter(
            authors: ["author4", "author5"],
            kinds: [1, 2]
        )

        let incompatibleMerge = filter1.merged(with: filter3)
        XCTAssertNil(incompatibleMerge)

        // Test time range incompatibility
        let filter4 = NDKFilter(
            since: 4000,
            until: 5000
        )

        let filter5 = NDKFilter(
            since: 1000,
            until: 2000
        )

        let timeMerge = filter4.merged(with: filter5)
        XCTAssertNil(timeMerge) // since > until after merge
    }

    func testEmptyFilter() {
        let emptyFilter = NDKFilter()

        // Empty filter should match any event
        let event = NDKEvent(
            pubkey: "any",
            createdAt: 12345,
            kind: 999,
            content: "Any content"
        )

        XCTAssertTrue(emptyFilter.matches(event: event))
    }
}
