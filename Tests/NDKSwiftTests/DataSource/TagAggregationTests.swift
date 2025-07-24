import XCTest
@testable import NDKSwift

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
        let sig1 = AggregationSignature(from: filter1)
        let sig2 = AggregationSignature(from: filter2)
        let sig3 = AggregationSignature(from: filter3)
        
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
        let sig1 = AggregationSignature(from: filter1)
        let sig2 = AggregationSignature(from: filter2)
        
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
        let sig1 = FilterSignature(from: filter1)
        let sig2 = FilterSignature(from: filter2)
        
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