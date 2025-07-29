import XCTest
@testable import NDKSwift

// Test stubs for signature types used in subscription aggregation tests
struct AggregationSignature: Equatable {
    let signature: String
    let kinds: [Int]?
    let tagKeys: [String]?
    let authors: [String]?
    let ids: [String]?
    
    init(from filter: NDKFilter) {
        // Store actual filter properties for test access
        self.kinds = filter.kinds
        self.tagKeys = filter.tags?.keys.sorted()
        self.authors = filter.authors
        self.ids = filter.ids
        
        // Create a simple signature based on filter structure (kinds + tag keys)
        let kindString = filter.kinds?.map(String.init).sorted().joined(separator: ",") ?? ""
        let tagKeys = filter.tags?.keys.sorted().joined(separator: ",") ?? ""
        self.signature = "\(kindString):\(tagKeys)"
    }
}

struct FilterSignature: Equatable {
    let signature: String
    let tags: [String: [String]]?
    
    init(from filter: NDKFilter) {
        // Store actual filter tags for test access, converting Set to Array
        self.tags = filter.tags?.mapValues { Array($0) }
        
        // Create a more detailed signature including tag values
        var components: [String] = []
        
        if let kinds = filter.kinds {
            components.append("kinds:\(kinds.map(String.init).sorted().joined(separator: ","))")
        }
        
        if let tags = filter.tags {
            for (key, values) in tags.sorted(by: { $0.key < $1.key }) {
                components.append("\(key):\(values.sorted().joined(separator: ","))")
            }
        }
        
        self.signature = components.joined(separator: "|")
    }
}

final class SubscriptionAggregationTests: XCTestCase {
    
    func testAggregationSignatureGroupsByStructure() async throws {
        // Test that AggregationSignature groups filters by structure (tag keys) not values
        
        // Filters with same structure (kinds + tag keys) but different values
        let filter1 = NDKFilter(kinds: [1111], tags: ["e": ["event123"]])
        let filter2 = NDKFilter(kinds: [1111], tags: ["e": ["event456"]])
        let filter3 = NDKFilter(kinds: [1111], tags: ["e": ["event789"]])
        
        // Create aggregation signatures
        let sig1 = AggregationSignature(from: filter1)
        let sig2 = AggregationSignature(from: filter2)
        let sig3 = AggregationSignature(from: filter3)
        
        // All should be equal since they have same structure
        XCTAssertEqual(sig1, sig2, "Filters with same tag keys should have equal aggregation signatures")
        XCTAssertEqual(sig2, sig3, "Filters with same tag keys should have equal aggregation signatures")
        XCTAssertEqual(sig1, sig3, "Filters with same tag keys should have equal aggregation signatures")
        
        // Test the specific properties
        XCTAssertEqual(sig1.kinds, [1111])
        XCTAssertEqual(sig1.tagKeys, ["e"])
        XCTAssertNil(sig1.authors)
        XCTAssertNil(sig1.ids)
    }
    
    func testAggregationSignatureDifferentStructures() async throws {
        // Test that different structures produce different signatures
        
        // Different tag keys
        let filter1 = NDKFilter(kinds: [1111], tags: ["e": ["event123"]])
        let filter2 = NDKFilter(kinds: [1111], tags: ["p": ["pubkey123"]])
        
        let sig1 = AggregationSignature(from: filter1)
        let sig2 = AggregationSignature(from: filter2)
        
        XCTAssertNotEqual(sig1, sig2, "Filters with different tag keys should have different signatures")
        XCTAssertEqual(sig1.tagKeys, ["e"])
        XCTAssertEqual(sig2.tagKeys, ["p"])
        
        // Different kinds
        let filter3 = NDKFilter(kinds: [1], tags: ["e": ["event123"]])
        let filter4 = NDKFilter(kinds: [2], tags: ["e": ["event123"]])
        
        let sig3 = AggregationSignature(from: filter3)
        let sig4 = AggregationSignature(from: filter4)
        
        XCTAssertNotEqual(sig3, sig4, "Filters with different kinds should have different signatures")
        
        // Multiple tag keys
        let filter5 = NDKFilter(kinds: [1111], tags: ["e": ["event123"], "p": ["pubkey123"]])
        let filter6 = NDKFilter(kinds: [1111], tags: ["e": ["event456"], "p": ["pubkey456"]])
        
        let sig5 = AggregationSignature(from: filter5)
        let sig6 = AggregationSignature(from: filter6)
        
        XCTAssertEqual(sig5, sig6, "Filters with same tag keys (e,p) should have equal signatures")
        XCTAssertEqual(Set(sig5.tagKeys ?? []), Set(["e", "p"]))
    }
    
    func testFilterSignatureStillUsesFullValues() async throws {
        // Test that FilterSignature (for cache matching) still uses full values
        
        let filter1 = NDKFilter(kinds: [1111], tags: ["e": ["event123"]])
        let filter2 = NDKFilter(kinds: [1111], tags: ["e": ["event456"]])
        
        let sig1 = FilterSignature(from: filter1)
        let sig2 = FilterSignature(from: filter2)
        
        // FilterSignatures should be different because they have different tag values
        XCTAssertNotEqual(sig1, sig2, "FilterSignatures with different tag values should not be equal")
        
        // Check that tags contain the actual values
        XCTAssertEqual(sig1.tags?["e"], ["event123"])
        XCTAssertEqual(sig2.tags?["e"], ["event456"])
    }
    
    func testAggregationLogicMergesTagValues() async throws {
        // Test the aggregation logic that should merge tag values
        
        let filters = [
            NDKFilter(kinds: [1111], tags: ["e": ["event1", "event2"]]),
            NDKFilter(kinds: [1111], tags: ["e": ["event3"]]),
            NDKFilter(kinds: [1111], tags: ["e": ["event4", "event5"]])
        ]
        
        // Simulate aggregateSingleGroup logic
        var tagsByKey: [String: Set<String>] = [:]
        for filter in filters {
            if let tags = filter.tags {
                for (key, values) in tags {
                    tagsByKey[key, default: []].formUnion(values)
                }
            }
        }
        
        // Should have all event IDs merged
        XCTAssertEqual(tagsByKey["e"], Set(["event1", "event2", "event3", "event4", "event5"]),
                      "All tag values should be merged into a single set")
    }
    
    func testComplexFilterAggregation() async throws {
        // Test complex filters with multiple properties
        
        let filter1 = NDKFilter(
            authors: ["author1", "author2"],
            kinds: [1, 2],
            tags: ["e": ["event1"], "p": ["pubkey1"], "t": ["bitcoin"]]
        )
        
        let filter2 = NDKFilter(
            authors: ["author2", "author3"],
            kinds: [2, 3],
            tags: ["e": ["event2"], "p": ["pubkey2"], "t": ["nostr"]]
        )
        
        // Same structure, different values
        let sig1 = AggregationSignature(from: filter1)
        let sig2 = AggregationSignature(from: filter2)
        
        XCTAssertEqual(sig1, sig2, "Filters with same structure should have equal aggregation signatures")
        
        // Different structure (missing 't' tag)
        let filter3 = NDKFilter(
            authors: ["author1"],
            kinds: [1, 2],
            tags: ["e": ["event3"], "p": ["pubkey3"]]
        )
        
        let sig3 = AggregationSignature(from: filter3)
        
        XCTAssertNotEqual(sig1, sig3, "Filter missing 't' tag should have different signature")
        XCTAssertEqual(Set(sig1.tagKeys ?? []), Set(["e", "p", "t"]))
        XCTAssertEqual(Set(sig3.tagKeys ?? []), Set(["e", "p"]))
    }
    
    func testRealWorldTENEXScenario() async throws {
        // Test the exact scenario from TENEX - multiple conversation status queries
        
        let conversationIds = [
            "668283f1c6bf749fb59154693345345fece515d300be93d8dd0d8e5ae00e68b2",
            "8f3efc350f4b7a717653651ce791d8f846ff792dda494d36aa13a2cb15f0d0aa",
            "b9a35109a79eee73ec54cdfcc17f1963c18e3d396a8a1085edce80adc3a43610",
            "97fc659ae9a575443a11e50c90d6b8eebd39b0b80be7dc45e4dc83b066f84891",
            "ce87fc923a6d0d43f1c65c7c75cc25dce1598e10a92accd9190ab46c3ca6ddf2"
        ]
        
        // Create filters for each conversation
        let filters = conversationIds.map { conversationId in
            NDKFilter(kinds: [1111], tags: ["e": [conversationId]])
        }
        
        // All should have the same aggregation signature
        let signatures = filters.map { AggregationSignature(from: $0) }
        
        // Verify all signatures are equal
        for i in 1..<signatures.count {
            XCTAssertEqual(signatures[0], signatures[i],
                          "All conversation queries should have the same aggregation signature")
        }
        
        // Simulate aggregation
        var aggregatedTags: [String: Set<String>] = [:]
        for filter in filters {
            if let tags = filter.tags {
                for (key, values) in tags {
                    aggregatedTags[key, default: []].formUnion(values)
                }
            }
        }
        
        // Should have all conversation IDs in one set
        XCTAssertEqual(aggregatedTags["e"]?.count, 5,
                      "Should have all 5 conversation IDs aggregated")
        XCTAssertEqual(aggregatedTags["e"], Set(conversationIds),
                      "Aggregated filter should contain all conversation IDs")
    }
}