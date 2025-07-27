import XCTest
@testable import NDKSwift

final class NDKFilterFingerprintTests: XCTestCase {
    
    // MARK: - Single Filter Fingerprint Tests
    
    func testEmptyFilterFingerprint() {
        let filter = NDKFilter()
        XCTAssertEqual(filter.toFingerprint(), "")
    }
    
    func testFilterWithSingleProperty() {
        // Only kinds
        let filter1 = NDKFilter(kinds: [1, 3])
        XCTAssertEqual(filter1.toFingerprint(), "kinds")
        
        // Only authors
        let filter2 = NDKFilter(authors: ["pubkey1", "pubkey2"])
        XCTAssertEqual(filter2.toFingerprint(), "authors")
        
        // Only ids
        let filter3 = NDKFilter(ids: ["id1", "id2"])
        XCTAssertEqual(filter3.toFingerprint(), "ids")
    }
    
    func testFilterWithMultipleProperties() {
        let filter = NDKFilter(
            authors: ["pubkey1"],
            kinds: [1, 3, 7]
        )
        // Properties should be sorted alphabetically
        XCTAssertEqual(filter.toFingerprint(), "authors-kinds")
    }
    
    func testFilterWithAllProperties() {
        let filter = NDKFilter(
            ids: ["id1"],
            authors: ["pubkey1"],
            kinds: [1],
            since: 1000,
            until: 2000,
            tags: ["p": Set(["pubkey2"])],
            limit: 100
        )
        // Properties sorted alphabetically, with since/until including values
        XCTAssertEqual(filter.toFingerprint(), "authors-ids-kinds-limit-since:1000-tags-until:2000")
    }
    
    func testTimeConstraintsIncludeValues() {
        // Only since
        let filter1 = NDKFilter(since: 12345)
        XCTAssertEqual(filter1.toFingerprint(), "since:12345")
        
        // Only until
        let filter2 = NDKFilter(until: 67890)
        XCTAssertEqual(filter2.toFingerprint(), "until:67890")
        
        // Both since and until
        let filter3 = NDKFilter(since: 1000, until: 2000)
        XCTAssertEqual(filter3.toFingerprint(), "since:1000-until:2000")
    }
    
    func testFilterWithTags() {
        let filter = NDKFilter(
            kinds: [1],
            tags: [
                "p": Set(["pubkey1", "pubkey2"]),
                "e": Set(["event1"])
            ]
        )
        // Tags presence is indicated but values are not included
        XCTAssertEqual(filter.toFingerprint(), "kinds-tags")
    }
    
    func testFingerprintConsistency() {
        // Same filters should produce same fingerprint
        let filter1 = NDKFilter(
            authors: ["pubkey1", "pubkey2"],
            kinds: [1, 3, 7],
            limit: 50
        )
        
        let filter2 = NDKFilter(
            authors: ["pubkey2", "pubkey1"], // Different order
            kinds: [7, 1, 3], // Different order
            limit: 50
        )
        
        XCTAssertEqual(filter1.toFingerprint(), filter2.toFingerprint())
    }
    
    // MARK: - Array of Filters Fingerprint Tests
    
    func testEmptyArrayFingerprint() {
        let filters: [NDKFilter] = []
        XCTAssertEqual(filters.toFingerprint(closeOnEose: false), "")
        XCTAssertEqual(filters.toFingerprint(closeOnEose: true), "+")
    }
    
    func testSingleFilterArrayFingerprint() {
        let filter = NDKFilter(kinds: [1])
        let filters = [filter]
        
        XCTAssertEqual(filters.toFingerprint(closeOnEose: false), "kinds")
        XCTAssertEqual(filters.toFingerprint(closeOnEose: true), "+kinds")
    }
    
    func testMultipleFiltersArrayFingerprint() {
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(authors: ["pubkey1"])
        let filter3 = NDKFilter(kinds: [3], authors: ["pubkey2"])
        
        let filters = [filter1, filter2, filter3]
        
        XCTAssertEqual(filters.toFingerprint(closeOnEose: false), "kinds|authors|authors-kinds")
        XCTAssertEqual(filters.toFingerprint(closeOnEose: true), "+kinds|authors|authors-kinds")
    }
    
    func testCloseOnEosePrefix() {
        let filter = NDKFilter(kinds: [1], authors: ["pubkey1"])
        let filters = [filter]
        
        let withoutClose = filters.toFingerprint(closeOnEose: false)
        let withClose = filters.toFingerprint(closeOnEose: true)
        
        XCTAssertEqual(withClose, "+" + withoutClose)
    }
    
    // MARK: - Subscription ID Generator Tests
    
    func testGenerateRelayIDWithinLimit() {
        let shortFingerprint = "kinds-authors"
        let id = NDKSubscriptionIDGenerator.generateRelayID(from: shortFingerprint)
        
        XCTAssertEqual(id, shortFingerprint)
        XCTAssertLessThanOrEqual(id.count, NDKSubscriptionIDGenerator.maxSubscriptionIDLength)
    }
    
    func testGenerateRelayIDExceedsLimit() {
        let longFingerprint = String(repeating: "a", count: 50)
        let id = NDKSubscriptionIDGenerator.generateRelayID(from: longFingerprint)
        
        XCTAssertEqual(id.count, NDKSubscriptionIDGenerator.maxSubscriptionIDLength)
        XCTAssertEqual(id, String(longFingerprint.prefix(NDKSubscriptionIDGenerator.maxSubscriptionIDLength)))
    }
    
    func testGenerateRelayIDWithSuffix() {
        let fingerprint = "kinds-authors"
        let suffix = "relay1"
        let id = NDKSubscriptionIDGenerator.generateRelayID(from: fingerprint, suffix: suffix)
        
        XCTAssertEqual(id, "kinds-authors_relay1")
        XCTAssertLessThanOrEqual(id.count, NDKSubscriptionIDGenerator.maxSubscriptionIDLength)
    }
    
    func testGenerateRelayIDWithLongFingerprintAndSuffix() {
        let longFingerprint = String(repeating: "a", count: 30)
        let suffix = "relay1"
        let id = NDKSubscriptionIDGenerator.generateRelayID(from: longFingerprint, suffix: suffix)
        
        // Should truncate fingerprint to make room for suffix
        XCTAssertLessThanOrEqual(id.count, NDKSubscriptionIDGenerator.maxSubscriptionIDLength)
        XCTAssertTrue(id.hasSuffix("_relay1"))
    }
    
    func testGenerateRelayIDWithVeryLongSuffix() {
        let fingerprint = "kinds"
        let longSuffix = String(repeating: "b", count: 30)
        let id = NDKSubscriptionIDGenerator.generateRelayID(from: fingerprint, suffix: longSuffix)
        
        // Should still respect the max length
        XCTAssertEqual(id.count, NDKSubscriptionIDGenerator.maxSubscriptionIDLength)
    }
    
    // MARK: - Edge Cases
    
    func testFilterWithNilValues() {
        let filter = NDKFilter()
        filter.ids = nil
        filter.authors = nil
        filter.kinds = nil
        filter.since = nil
        filter.until = nil
        filter.tags = nil
        filter.limit = nil
        
        XCTAssertEqual(filter.toFingerprint(), "")
    }
    
    func testFilterWithEmptyCollections() {
        let filter = NDKFilter(
            ids: [],
            authors: [],
            kinds: []
        )
        // Empty collections should still count as present
        XCTAssertEqual(filter.toFingerprint(), "authors-ids-kinds")
    }
    
    func testComplexTagsFingerprint() {
        let filter = NDKFilter(
            tags: [
                "p": Set(["pubkey1", "pubkey2", "pubkey3"]),
                "e": Set(["event1", "event2"]),
                "t": Set(["nostr", "bitcoin"]),
                "g": Set(["geohash1"])
            ]
        )
        // Only "tags" should appear, not individual tag types or values
        XCTAssertEqual(filter.toFingerprint(), "tags")
    }
    
    func testLargeTimestampValues() {
        let filter = NDKFilter(
            since: 1234567890123,
            until: 9876543210987
        )
        XCTAssertEqual(filter.toFingerprint(), "since:1234567890123-until:9876543210987")
    }
}