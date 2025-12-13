@testable import NDKSwiftCore
import XCTest

final class TagValidationTests: XCTestCase {
    // MARK: - extractTags tests

    func testExtractTags_returnsMatchingTags() {
        let tags: [[String]] = [
            ["e", "event1", "relay1"],
            ["p", "pubkey1"],
            ["e", "event2"],
            ["t", "topic"],
            ["e", "event3", "relay2", "reply"],
        ]

        let eventTags = tags.extractTags(named: "e")
        XCTAssertEqual(eventTags.count, 3)
        XCTAssertEqual(eventTags[0], ["e", "event1", "relay1"])
        XCTAssertEqual(eventTags[1], ["e", "event2"])
        XCTAssertEqual(eventTags[2], ["e", "event3", "relay2", "reply"])
    }

    func testExtractTags_returnsEmptyForNoMatches() {
        let tags: [[String]] = [
            ["p", "pubkey1"],
            ["t", "topic"],
        ]

        let eventTags = tags.extractTags(named: "e")
        XCTAssertTrue(eventTags.isEmpty)
    }

    func testExtractTags_respectsMinLength() {
        let tags: [[String]] = [
            ["e"], // Too short
            ["e", "event1"], // Valid
            ["e", "event2", "relay"], // Valid
        ]

        let eventTags = tags.extractTags(named: "e", minLength: 2)
        XCTAssertEqual(eventTags.count, 2)
        XCTAssertEqual(eventTags[0], ["e", "event1"])
        XCTAssertEqual(eventTags[1], ["e", "event2", "relay"])
    }

    // MARK: - firstTag tests

    func testFirstTag_returnsFirstMatchingTag() {
        let tags: [[String]] = [
            ["p", "pubkey1"],
            ["e", "event1"],
            ["e", "event2"],
        ]

        let firstEventTag = tags.firstTag(named: "e")
        XCTAssertEqual(firstEventTag, ["e", "event1"])
    }

    func testFirstTag_returnsNilForNoMatch() {
        let tags: [[String]] = [
            ["p", "pubkey1"],
            ["t", "topic"],
        ]

        let firstEventTag = tags.firstTag(named: "e")
        XCTAssertNil(firstEventTag)
    }

    // MARK: - firstTagValue tests

    func testFirstTagValue_returnsSecondElement() {
        let tags: [[String]] = [
            ["e", "event123", "relay"],
            ["p", "pubkey456"],
        ]

        XCTAssertEqual(tags.firstTagValue(named: "e"), "event123")
        XCTAssertEqual(tags.firstTagValue(named: "p"), "pubkey456")
    }

    func testFirstTagValue_returnsNilForSingleElementTag() {
        let tags = [
            ["e"], // No value
        ]

        XCTAssertNil(tags.firstTagValue(named: "e"))
    }

    func testFirstTagValue_returnsNilForNoMatch() {
        let tags: [[String]] = [
            ["p", "pubkey1"],
        ]

        XCTAssertNil(tags.firstTagValue(named: "e"))
    }

    // MARK: - tagValues tests

    func testTagValues_returnsAllValues() {
        let tags: [[String]] = [
            ["e", "event1"],
            ["p", "pubkey1"],
            ["e", "event2", "relay"],
            ["e"], // No value, should be skipped
            ["e", "event3"],
        ]

        let eventValues = tags.tagValues(named: "e")
        XCTAssertEqual(eventValues, ["event1", "event2", "event3"])
    }

    func testTagValues_returnsEmptyForNoMatches() {
        let tags: [[String]] = [
            ["p", "pubkey1"],
        ]

        let eventValues = tags.tagValues(named: "e")
        XCTAssertTrue(eventValues.isEmpty)
    }

    // MARK: - hasTag tests

    func testHasTag_returnsTrueWhenExists() {
        let tags: [[String]] = [
            ["e", "event1"],
            ["p", "pubkey1"],
        ]

        XCTAssertTrue(tags.hasTag(named: "e"))
        XCTAssertTrue(tags.hasTag(named: "p"))
    }

    func testHasTag_returnsFalseWhenNotExists() {
        let tags: [[String]] = [
            ["p", "pubkey1"],
        ]

        XCTAssertFalse(tags.hasTag(named: "e"))
        XCTAssertFalse(tags.hasTag(named: "t"))
    }

    // MARK: - Convenience property tests

    func testEventTags_returnsAllEventTags() {
        let tags: [[String]] = [
            ["e", "event1"],
            ["p", "pubkey1"],
            ["e", "event2", "relay"],
        ]

        let eventTags = tags.eventTags
        XCTAssertEqual(eventTags.count, 2)
        XCTAssertEqual(eventTags[0], ["e", "event1"])
        XCTAssertEqual(eventTags[1], ["e", "event2", "relay"])
    }

    func testPubkeyTags_returnsAllPubkeyTags() {
        let tags: [[String]] = [
            ["e", "event1"],
            ["p", "pubkey1"],
            ["p", "pubkey2", "relay"],
        ]

        let pubkeyTags = tags.pubkeyTags
        XCTAssertEqual(pubkeyTags.count, 2)
        XCTAssertEqual(pubkeyTags[0], ["p", "pubkey1"])
        XCTAssertEqual(pubkeyTags[1], ["p", "pubkey2", "relay"])
    }

    func testEventIds_returnsAllEventIds() {
        let tags: [[String]] = [
            ["e", "event1"],
            ["e", "event2", "relay"],
            ["e"], // No ID, should be skipped
            ["p", "pubkey1"],
        ]

        let eventIds = tags.eventIds
        XCTAssertEqual(eventIds, ["event1", "event2"])
    }

    func testPubkeys_returnsAllPubkeys() {
        let tags: [[String]] = [
            ["p", "pubkey1"],
            ["p", "pubkey2", "relay"],
            ["p"], // No pubkey, should be skipped
            ["e", "event1"],
        ]

        let pubkeys = tags.pubkeys
        XCTAssertEqual(pubkeys, ["pubkey1", "pubkey2"])
    }

    // MARK: - Edge case tests

    func testEmptyTags_returnsEmptyResults() {
        let tags: [[String]] = []

        XCTAssertTrue(tags.extractTags(named: "e").isEmpty)
        XCTAssertNil(tags.firstTag(named: "e"))
        XCTAssertNil(tags.firstTagValue(named: "e"))
        XCTAssertTrue(tags.tagValues(named: "e").isEmpty)
        XCTAssertFalse(tags.hasTag(named: "e"))
        XCTAssertTrue(tags.eventTags.isEmpty)
        XCTAssertTrue(tags.pubkeyTags.isEmpty)
        XCTAssertTrue(tags.eventIds.isEmpty)
        XCTAssertTrue(tags.pubkeys.isEmpty)
    }

    func testComplexTags_handlesVariousFormats() {
        let tags: [[String]] = [
            ["e", "event1", "wss://relay.example.com", "root"],
            ["e", "event2", "", "reply"], // Empty relay
            ["e", "event3"], // No relay or marker
            ["p", "02a1b2c3d4e5f6", "wss://relay.example.com"],
            ["p", "03f6e5d4c3b2a1"], // No relay
            ["t", "bitcoin"],
            ["a", "30023:author:d-identifier"],
            ["k", "1"],
        ]

        // Test event tags
        let eventTags = tags.eventTags
        XCTAssertEqual(eventTags.count, 3)

        // Test that all event values are extracted
        let eventIds = tags.eventIds
        XCTAssertEqual(eventIds, ["event1", "event2", "event3"])

        // Test pubkey extraction
        let pubkeys = tags.pubkeys
        XCTAssertEqual(pubkeys, ["02a1b2c3d4e5f6", "03f6e5d4c3b2a1"])

        // Test other tag types
        XCTAssertEqual(tags.firstTagValue(named: "t"), "bitcoin")
        XCTAssertEqual(tags.firstTagValue(named: "a"), "30023:author:d-identifier")
        XCTAssertEqual(tags.firstTagValue(named: "k"), "1")
    }
}
