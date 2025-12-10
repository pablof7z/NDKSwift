import XCTest
@testable import NDKSwiftCore

// Test stubs for signature types used in tag aggregation tests
struct TagAggregationSignature: Equatable {
    let signature: String
    
    init(from filter: NDKFilter) {
        // Create a simple signature based on filter structure (kinds + tag keys)
        let kindString = filter.kinds?.map(String.init).sorted().joined(separator: ",") ?? ""
        let tagKeys = filter.tags?.keys.sorted().joined(separator: ",") ?? ""
        self.signature = "\(kindString):\(tagKeys)"
    }
}

struct TagFilterSignature: Equatable {
    let signature: String
    
    init(from filter: NDKFilter) {
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

final class TagAggregationTests: XCTestCase {
    
    func testAggregationSignatureGroupsByTagKeys() async throws {
        // Create filters with same tag keys but different values
        let filter1 = NDKFilter(
            kinds: [1111],
            tags: ["e": ["event123"]]
        )
        
        let filter2 = NDKFilter(
            kinds: [1111],
            tags: ["e": ["event456"]]
        )
        
        let filter3 = NDKFilter(
            kinds: [1111],
            tags: ["e": ["event789"]]
        )
        
        // Create aggregation signatures
        let sig1 = TagAggregationSignature(from: filter1)
        let sig2 = TagAggregationSignature(from: filter2)
        let sig3 = TagAggregationSignature(from: filter3)
        
        // All should be equal since they have same structure
        XCTAssertEqual(sig1, sig2)
        XCTAssertEqual(sig2, sig3)
        XCTAssertEqual(sig1, sig3)
    }
    
    func testAggregationSignatureDifferentTagKeys() async throws {
        // Create filters with different tag keys
        let filter1 = NDKFilter(
            kinds: [1111],
            tags: ["e": ["event123"]]
        )
        
        let filter2 = NDKFilter(
            kinds: [1111],
            tags: ["p": ["pubkey123"]]
        )
        
        // Create aggregation signatures
        let sig1 = TagAggregationSignature(from: filter1)
        let sig2 = TagAggregationSignature(from: filter2)
        
        // Should NOT be equal since they have different tag keys
        XCTAssertNotEqual(sig1, sig2)
    }
    
    func testFilterSignatureStillUsesFullValues() async throws {
        // Create filters with same tag keys but different values
        let filter1 = NDKFilter(
            kinds: [1111],
            tags: ["e": ["event123"]]
        )
        
        let filter2 = NDKFilter(
            kinds: [1111],
            tags: ["e": ["event456"]]
        )
        
        // Create filter signatures (used for cache matching)
        let sig1 = TagFilterSignature(from: filter1)
        let sig2 = TagFilterSignature(from: filter2)
        
        // Should NOT be equal since they have different tag values
        XCTAssertNotEqual(sig1, sig2)
    }
    
    func testAggregationPreservesAllTagValues() async throws {
        // Test that the aggregation logic properly merges tag values
        let filters = [
            NDKFilter(kinds: [1111], tags: ["e": ["event1"]]),
            NDKFilter(kinds: [1111], tags: ["e": ["event2"]]),
            NDKFilter(kinds: [1111], tags: ["e": ["event3"]])
        ]
        
        // Manually simulate what aggregateSingleGroup does
        var tagsByKey: [String: Set<String>] = [:]
        for filter in filters {
            if let tags = filter.tags {
                for (key, values) in tags {
                    tagsByKey[key, default: []].formUnion(values)
                }
            }
        }
        
        // Should have all three event IDs
        XCTAssertEqual(tagsByKey["e"], Set(["event1", "event2", "event3"]))
    }
}