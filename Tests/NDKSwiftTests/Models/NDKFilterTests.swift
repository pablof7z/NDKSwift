import XCTest
@testable import NDKSwift

final class NDKFilterTests: XCTestCase {
    
    // MARK: - Test Data
    
    private let testEventID = "d7dd5eb3ab747e16f8d0212d53032ea2a7cadef53837e5a6c66d42849fcb9027"
    private let testPubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
    private let testPubkey2 = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
    
    // MARK: - Initialization Tests
    
    func testDefaultInitialization() {
        let filter = NDKFilter()
        
        XCTAssertNil(filter.ids)
        XCTAssertNil(filter.authors)
        XCTAssertNil(filter.kinds)
        XCTAssertNil(filter.events)
        XCTAssertNil(filter.pubkeys)
        XCTAssertNil(filter.since)
        XCTAssertNil(filter.until)
        XCTAssertNil(filter.limit)
        XCTAssertNil(filter.tags)
    }
    
    func testFullInitialization() {
        let filter = NDKFilter(
            ids: [testEventID],
            authors: [testPubkey],
            kinds: [1, 3, 7],
            events: ["event1"],
            pubkeys: [testPubkey2],
            since: 1000,
            until: 2000,
            limit: 50,
            tags: ["p": Set([testPubkey]), "t": Set(["nostr", "bitcoin"])]
        )
        
        XCTAssertEqual(filter.ids, [testEventID])
        XCTAssertEqual(filter.authors, [testPubkey])
        XCTAssertEqual(filter.kinds, [1, 3, 7])
        XCTAssertEqual(filter.events, ["event1"])
        XCTAssertEqual(filter.pubkeys, [testPubkey2])
        XCTAssertEqual(filter.since, 1000)
        XCTAssertEqual(filter.until, 2000)
        XCTAssertEqual(filter.limit, 50)
        XCTAssertEqual(filter.tags?["p"], Set([testPubkey]))
        XCTAssertEqual(filter.tags?["t"], Set(["nostr", "bitcoin"]))
    }
    
    // MARK: - Tag Filter Tests
    
    func testAddTagFilter() {
        var filter = NDKFilter()
        
        filter.addTagFilter("p", values: [testPubkey, testPubkey2])
        filter.addTagFilter("t", values: ["nostr"])
        
        XCTAssertEqual(filter.tagFilter("p"), [testPubkey, testPubkey2])
        XCTAssertEqual(filter.tagFilter("t"), ["nostr"])
        XCTAssertNil(filter.tagFilter("e"))
    }
    
    func testTagsProperty() {
        var filter = NDKFilter()
        
        // Initially nil
        XCTAssertNil(filter.tags)
        
        // Add some tags
        filter.addTagFilter("p", values: [testPubkey])
        filter.addTagFilter("t", values: ["nostr", "bitcoin"])
        
        let tags = filter.tags
        XCTAssertEqual(tags?["p"], Set([testPubkey]))
        XCTAssertEqual(tags?["t"], Set(["nostr", "bitcoin"]))
    }
    
    // MARK: - Replaceable Event Tests
    
    func testIsReplaceableForStandardReplaceableKinds() {
        // Kind 0 (metadata) is replaceable
        let filter1 = NDKFilter(kinds: [0])
        XCTAssertTrue(filter1.isReplaceable)
        
        // Kind 3 (contacts) is replaceable
        let filter2 = NDKFilter(kinds: [3])
        XCTAssertTrue(filter2.isReplaceable)
        
        // Replaceable range 10000-19999
        let filter3 = NDKFilter(kinds: [10002])
        XCTAssertTrue(filter3.isReplaceable)
        
        // Parameterized replaceable range 30000-39999
        let filter4 = NDKFilter(kinds: [30023])
        XCTAssertTrue(filter4.isReplaceable)
    }
    
    func testIsReplaceableForNonReplaceableKinds() {
        // Kind 1 (text note) is not replaceable
        let filter1 = NDKFilter(kinds: [1])
        XCTAssertFalse(filter1.isReplaceable)
        
        // Kind 7 (reaction) is not replaceable
        let filter2 = NDKFilter(kinds: [7])
        XCTAssertFalse(filter2.isReplaceable)
        
        // Mixed replaceable and non-replaceable
        let filter3 = NDKFilter(kinds: [0, 1])
        XCTAssertFalse(filter3.isReplaceable)
    }
    
    func testIsReplaceableWithNoKinds() {
        let filter = NDKFilter()
        XCTAssertFalse(filter.isReplaceable)
    }
    
    // MARK: - Event Matching Tests
    
    func testMatchesEventById() {
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test",
            id: testEventID
        )
        
        let matchingFilter = NDKFilter(ids: [testEventID])
        XCTAssertTrue(matchingFilter.matches(event: event))
        
        let nonMatchingFilter = NDKFilter(ids: ["different_id"])
        XCTAssertFalse(nonMatchingFilter.matches(event: event))
    }
    
    func testMatchesEventByAuthor() {
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test",
            pubkey: testPubkey
        )
        
        let matchingFilter = NDKFilter(authors: [testPubkey])
        XCTAssertTrue(matchingFilter.matches(event: event))
        
        let nonMatchingFilter = NDKFilter(authors: [testPubkey2])
        XCTAssertFalse(nonMatchingFilter.matches(event: event))
    }
    
    func testMatchesEventByKind() {
        let event = EventTestFactory.createEvent(kind: 1, content: "Test")
        
        let matchingFilter = NDKFilter(kinds: [1, 3, 7])
        XCTAssertTrue(matchingFilter.matches(event: event))
        
        let nonMatchingFilter = NDKFilter(kinds: [3, 7])
        XCTAssertFalse(nonMatchingFilter.matches(event: event))
    }
    
    func testMatchesEventByTimestamp() {
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test",
            createdAt: 1500
        )
        
        // Event within time range
        let matchingFilter = NDKFilter(since: 1000, until: 2000)
        XCTAssertTrue(matchingFilter.matches(event: event))
        
        // Event before since
        let tooEarlyFilter = NDKFilter(since: 2000)
        XCTAssertFalse(tooEarlyFilter.matches(event: event))
        
        // Event after until
        let tooLateFilter = NDKFilter(until: 1000)
        XCTAssertFalse(tooLateFilter.matches(event: event))
    }
    
    func testMatchesEventByReferencedEvents() {
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test",
            tags: [["e", "referenced_event_1"], ["e", "referenced_event_2"]]
        )
        
        let matchingFilter = NDKFilter(events: ["referenced_event_1", "other_event"])
        XCTAssertTrue(matchingFilter.matches(event: event))
        
        let nonMatchingFilter = NDKFilter(events: ["different_event"])
        XCTAssertFalse(nonMatchingFilter.matches(event: event))
    }
    
    func testMatchesEventByReferencedPubkeys() {
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test",
            tags: [["p", testPubkey], ["p", testPubkey2]]
        )
        
        let matchingFilter = NDKFilter(pubkeys: [testPubkey2])
        XCTAssertTrue(matchingFilter.matches(event: event))
        
        let nonMatchingFilter = NDKFilter(pubkeys: ["different_pubkey"])
        XCTAssertFalse(nonMatchingFilter.matches(event: event))
    }
    
    func testMatchesEventByGenericTags() {
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test",
            tags: [["t", "nostr"], ["t", "bitcoin"], ["g", "geohash123"]]
        )
        
        var matchingFilter = NDKFilter()
        matchingFilter.addTagFilter("t", values: ["nostr", "ethereum"])
        XCTAssertTrue(matchingFilter.matches(event: event))
        
        var nonMatchingFilter = NDKFilter()
        nonMatchingFilter.addTagFilter("t", values: ["ethereum"])
        XCTAssertFalse(nonMatchingFilter.matches(event: event))
        
        var geoFilter = NDKFilter()
        geoFilter.addTagFilter("g", values: ["geohash123"])
        XCTAssertTrue(geoFilter.matches(event: event))
    }
    
    func testMatchesEventWithMultipleCriteria() {
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test",
            tags: [["t", "nostr"]],
            pubkey: testPubkey,
            createdAt: 1500
        )
        
        var filter = NDKFilter(
            authors: [testPubkey],
            kinds: [1],
            since: 1000,
            until: 2000
        )
        filter.addTagFilter("t", values: ["nostr"])
        
        XCTAssertTrue(filter.matches(event: event))
        
        // Change one criterion to not match
        filter.kinds = [3]
        XCTAssertFalse(filter.matches(event: event))
    }
    
    // MARK: - Specificity Tests
    
    func testIsMoreSpecific() {
        let lessSpecific = NDKFilter(kinds: [1])
        let moreSpecific = NDKFilter(
            ids: ["id1"],
            authors: ["author1"],
            kinds: [1]
        )
        
        XCTAssertTrue(moreSpecific.isMoreSpecific(than: lessSpecific))
        XCTAssertFalse(lessSpecific.isMoreSpecific(than: moreSpecific))
    }
    
    func testIsMoreSpecificWithTags() {
        var filter1 = NDKFilter(kinds: [1])
        filter1.addTagFilter("t", values: ["nostr"])
        
        var filter2 = NDKFilter(kinds: [1])
        filter2.addTagFilter("t", values: ["nostr"])
        filter2.addTagFilter("p", values: ["pubkey"])
        
        XCTAssertTrue(filter2.isMoreSpecific(than: filter1))
    }
    
    // MARK: - Merge Tests
    
    func testMergeCompatibleFilters() {
        let filter1 = NDKFilter(
            authors: ["author1", "author2"],
            kinds: [1, 3]
        )
        
        let filter2 = NDKFilter(
            authors: ["author2", "author3"],
            kinds: [1, 7]
        )
        
        let merged = filter1.merged(with: filter2)
        
        XCTAssertNotNil(merged)
        XCTAssertEqual(Set(merged!.authors ?? []), Set(["author2"]))
        XCTAssertEqual(Set(merged!.kinds ?? []), Set([1]))
    }
    
    func testMergeIncompatibleFilters() {
        let filter1 = NDKFilter(kinds: [1, 3])
        let filter2 = NDKFilter(kinds: [7, 9])
        
        let merged = filter1.merged(with: filter2)
        XCTAssertNil(merged) // No common kinds
    }
    
    func testMergeTimestamps() {
        let filter1 = NDKFilter(since: 1000, until: 3000)
        let filter2 = NDKFilter(since: 2000, until: 4000)
        
        let merged = filter1.merged(with: filter2)
        
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged!.since, 2000) // Max of since values
        XCTAssertEqual(merged!.until, 3000) // Min of until values
    }
    
    func testMergeIncompatibleTimestamps() {
        let filter1 = NDKFilter(since: 3000, until: 4000)
        let filter2 = NDKFilter(since: 1000, until: 2000)
        
        let merged = filter1.merged(with: filter2)
        XCTAssertNil(merged) // Time ranges don't overlap
    }
    
    func testMergeLimits() {
        let filter1 = NDKFilter(limit: 100)
        let filter2 = NDKFilter(limit: 50)
        
        let merged = filter1.merged(with: filter2)
        
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged!.limit, 50) // Smaller limit
    }
    
    // MARK: - Union Merge Tests
    
    func testMergeUnionForMetadataFilters() {
        let filter1 = NDKFilter(
            authors: ["author1"],
            kinds: [0],
            limit: 10
        )
        
        let filter2 = NDKFilter(
            authors: ["author2"],
            kinds: [0],
            limit: 20
        )
        
        let merged = filter1.mergedUnion(with: filter2)
        
        XCTAssertNotNil(merged)
        XCTAssertEqual(Set(merged!.authors ?? []), Set(["author1", "author2"]))
        XCTAssertEqual(merged!.kinds, [0])
        XCTAssertEqual(merged!.limit, 30) // Sum of limits
    }
    
    func testMergeUnionIncompatibleKinds() {
        let filter1 = NDKFilter(authors: ["author1"], kinds: [0])
        let filter2 = NDKFilter(authors: ["author2"], kinds: [1])
        
        let merged = filter1.mergedUnion(with: filter2)
        XCTAssertNil(merged) // Different kinds
    }
    
    func testMergeUnionWithTags() {
        var filter1 = NDKFilter(authors: ["author1"], kinds: [0])
        filter1.addTagFilter("t", values: ["nostr"])
        
        let filter2 = NDKFilter(authors: ["author2"], kinds: [0])
        
        let merged = filter1.mergedUnion(with: filter2)
        XCTAssertNil(merged) // Has tag filters
    }
    
    func testMergeUnionDifferentTimestamps() {
        let filter1 = NDKFilter(authors: ["author1"], kinds: [0], since: 1000)
        let filter2 = NDKFilter(authors: ["author2"], kinds: [0], since: 2000)
        
        let merged = filter1.mergedUnion(with: filter2)
        XCTAssertNil(merged) // Different timestamps
    }
    
    // MARK: - Dictionary Representation Tests
    
    func testDictionaryRepresentation() {
        var filter = NDKFilter(
            ids: ["id1"],
            authors: ["author1"],
            kinds: [1, 3],
            events: ["event1"],
            pubkeys: ["pubkey1"],
            since: 1000,
            until: 2000,
            limit: 50
        )
        filter.addTagFilter("t", values: ["nostr"])
        
        let dict = filter.dictionary
        
        XCTAssertEqual(dict["ids"] as? [String], ["id1"])
        XCTAssertEqual(dict["authors"] as? [String], ["author1"])
        XCTAssertEqual(dict["kinds"] as? [Int], [1, 3])
        XCTAssertEqual(dict["#e"] as? [String], ["event1"])
        XCTAssertEqual(dict["#p"] as? [String], ["pubkey1"])
        XCTAssertEqual(dict["since"] as? Timestamp, 1000)
        XCTAssertEqual(dict["until"] as? Timestamp, 2000)
        XCTAssertEqual(dict["limit"] as? Int, 50)
        XCTAssertEqual(dict["#t"] as? [String], ["nostr"])
    }
    
    // MARK: - Codable Tests
    
    func testEncodeDecode() throws {
        var original = NDKFilter(
            ids: ["id1", "id2"],
            authors: ["author1"],
            kinds: [1, 3, 7],
            events: ["event1"],
            pubkeys: ["pubkey1", "pubkey2"],
            since: 1000,
            until: 2000,
            limit: 100
        )
        original.addTagFilter("t", values: ["nostr", "bitcoin"])
        original.addTagFilter("g", values: ["geohash123"])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NDKFilter.self, from: data)
        
        XCTAssertEqual(decoded.ids, original.ids)
        XCTAssertEqual(decoded.authors, original.authors)
        XCTAssertEqual(decoded.kinds, original.kinds)
        XCTAssertEqual(decoded.events, original.events)
        XCTAssertEqual(decoded.pubkeys, original.pubkeys)
        XCTAssertEqual(decoded.since, original.since)
        XCTAssertEqual(decoded.until, original.until)
        XCTAssertEqual(decoded.limit, original.limit)
        XCTAssertEqual(decoded.tagFilter("t"), ["nostr", "bitcoin"])
        XCTAssertEqual(decoded.tagFilter("g"), ["geohash123"])
    }
    
    func testDecodeFromJSON() throws {
        let json = """
        {
            "ids": ["id1"],
            "authors": ["author1"],
            "kinds": [1, 3],
            "#e": ["event1"],
            "#p": ["pubkey1"],
            "#t": ["nostr", "bitcoin"],
            "since": 1000,
            "until": 2000,
            "limit": 50
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let filter = try decoder.decode(NDKFilter.self, from: data)
        
        XCTAssertEqual(filter.ids, ["id1"])
        XCTAssertEqual(filter.authors, ["author1"])
        XCTAssertEqual(filter.kinds, [1, 3])
        XCTAssertEqual(filter.events, ["event1"])
        XCTAssertEqual(filter.pubkeys, ["pubkey1"])
        XCTAssertEqual(filter.tagFilter("t"), ["nostr", "bitcoin"])
        XCTAssertEqual(filter.since, 1000)
        XCTAssertEqual(filter.until, 2000)
        XCTAssertEqual(filter.limit, 50)
    }
    
    // MARK: - Fingerprint Tests
    
    func testFingerprintGeneration() {
        let filter = NDKFilter(
            authors: [testPubkey],
            kinds: [1, 3]
        )
        
        let fingerprint = filter.fingerprint
        
        // The fingerprint should be a hash if it's too long
        // Let's test the basic properties
        XCTAssertFalse(fingerprint.isEmpty)
        XCTAssertNotEqual(fingerprint, "empty-filter")
        
        // Test that fingerprints are stable
        let fingerprint2 = filter.fingerprint
        XCTAssertEqual(fingerprint, fingerprint2)
    }
    
    func testFingerprintForEmptyFilter() {
        let filter = NDKFilter()
        XCTAssertEqual(filter.fingerprint, "empty-filter")
    }
    
    func testFingerprintConsistency() {
        let filter1 = NDKFilter(
            authors: [testPubkey, testPubkey2],
            kinds: [1, 3, 7]
        )
        
        let filter2 = NDKFilter(
            authors: [testPubkey2, testPubkey], // Different order
            kinds: [7, 1, 3] // Different order
        )
        
        // Fingerprints should be the same despite different order
        XCTAssertEqual(filter1.fingerprint, filter2.fingerprint)
    }
    
    func testFingerprintWithLongContent() {
        var filter = NDKFilter()
        
        // Add many authors to create a long fingerprint
        let authors = (0..<20).map { "author\($0)author\($0)author\($0)" }
        filter.authors = authors
        
        let fingerprint = filter.fingerprint
        
        // Should be hashed if too long
        XCTAssertLessThanOrEqual(fingerprint.count, 15)
    }
    
    // MARK: - Description Tests
    
    func testDescription() {
        let filter = NDKFilter(
            authors: [testPubkey],
            kinds: [1, 3],
            since: 1000,
            limit: 50
        )
        
        let description = filter.description
        
        XCTAssertTrue(description.contains("NDKFilter"))
        XCTAssertTrue(description.contains("kinds:1,3"))
        XCTAssertTrue(description.contains("authors:"))
        XCTAssertTrue(description.contains("since:1000"))
        XCTAssertTrue(description.contains("limit:50"))
    }
    
    func testDescriptionWithManyItems() {
        let authors = (0..<10).map { "author\($0)" }
        let filter = NDKFilter(authors: authors)
        
        let description = filter.description
        
        // Should truncate and add ellipsis
        XCTAssertTrue(description.contains("..."))
    }
    
    // MARK: - Equatable Tests
    
    func testEquality() {
        let filter1 = NDKFilter(
            authors: ["author1"],
            kinds: [1, 3]
        )
        
        let filter2 = NDKFilter(
            authors: ["author1"],
            kinds: [1, 3]
        )
        
        let filter3 = NDKFilter(
            authors: ["author2"],
            kinds: [1, 3]
        )
        
        XCTAssertEqual(filter1, filter2)
        XCTAssertNotEqual(filter1, filter3)
    }
    
    func testEqualityWithTags() {
        var filter1 = NDKFilter()
        filter1.addTagFilter("t", values: ["nostr"])
        
        var filter2 = NDKFilter()
        filter2.addTagFilter("t", values: ["nostr"])
        
        var filter3 = NDKFilter()
        filter3.addTagFilter("t", values: ["bitcoin"])
        
        XCTAssertEqual(filter1, filter2)
        XCTAssertNotEqual(filter1, filter3)
    }
}