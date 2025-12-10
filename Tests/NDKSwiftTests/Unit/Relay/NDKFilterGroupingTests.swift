import XCTest
@testable import NDKSwiftCore

final class NDKFilterGroupingTests: XCTestCase {
    
    // MARK: - Filter Fingerprint Tests
    
    func testFilterFingerprintWithBasicFilters() {
        // Given
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(authors: ["author1"])
        let filter3 = NDKFilter(ids: ["id1", "id2"])
        
        // When
        let fp1 = NDKFilterGrouping.filterFingerprint([filter1], closeOnEose: false)
        let fp2 = NDKFilterGrouping.filterFingerprint([filter2], closeOnEose: false)
        let fp3 = NDKFilterGrouping.filterFingerprint([filter3], closeOnEose: false)
        
        // Then
        XCTAssertEqual(fp1, "kinds")
        XCTAssertEqual(fp2, "authors")
        XCTAssertEqual(fp3, "ids")
    }
    
    func testFilterFingerprintWithCloseOnEose() {
        // Given
        let filter = NDKFilter(kinds: [1])
        
        // When
        let fpWithoutClose = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: false)
        let fpWithClose = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: true)
        
        // Then
        XCTAssertEqual(fpWithoutClose, "kinds")
        XCTAssertEqual(fpWithClose, "+kinds")
    }
    
    func testFilterFingerprintWithTimeConstraints() {
        // Given
        let filter1 = NDKFilter(kinds: [1], since: 1000)
        let filter2 = NDKFilter(kinds: [1], until: 2000)
        let filter3 = NDKFilter(kinds: [1], since: 1000, until: 2000)
        
        // When
        let fp1 = NDKFilterGrouping.filterFingerprint([filter1], closeOnEose: false)
        let fp2 = NDKFilterGrouping.filterFingerprint([filter2], closeOnEose: false)
        let fp3 = NDKFilterGrouping.filterFingerprint([filter3], closeOnEose: false)
        
        // Then
        XCTAssertEqual(fp1, "kinds-since:1000")
        XCTAssertEqual(fp2, "kinds-until:2000")
        XCTAssertEqual(fp3, "kinds-since:1000-until:2000")
    }
    
    func testFilterFingerprintWithTags() {
        // Given
        var filter = NDKFilter(kinds: [1])
        filter.addTagFilter("p", values: ["pubkey1"])
        filter.addTagFilter("e", values: ["event1"])
        
        // When
        let fp = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: false)
        
        // Then
        XCTAssertEqual(fp, "#e-#p-kinds")
    }
    
    func testFilterFingerprintWithMultipleFilters() {
        // Given
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(authors: ["author1"])
        
        // When
        let fp = NDKFilterGrouping.filterFingerprint([filter1, filter2], closeOnEose: false)
        
        // Then
        XCTAssertEqual(fp, "kinds|authors")
    }
    
    func testFilterFingerprintWithComplexFilter() {
        // Given
        var filter = NDKFilter(
            ids: ["id1"],
            authors: ["author1"],
            kinds: [1, 7],
            since: 1000,
            until: 2000,
            limit: 10
        )
        filter.events = ["event1"]
        filter.pubkeys = ["pubkey1"]
        filter.addTagFilter("t", values: ["bitcoin"])
        
        // When
        let fp = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: false)
        
        // Then
        // Should include all fields except values, sorted alphabetically
        XCTAssertEqual(fp, "#e-#p-#t-authors-ids-kinds-limit-since:1000-until:2000")
    }
    
    func testFilterFingerprintDeterministic() {
        // Given - Create two filters with same fields but different insertion order
        var filter1 = NDKFilter()
        filter1.addTagFilter("z", values: ["value1"])
        filter1.addTagFilter("a", values: ["value2"])
        filter1.kinds = [1]
        filter1.authors = ["author1"]
        
        var filter2 = NDKFilter()
        filter2.authors = ["author1"]
        filter2.kinds = [1]
        filter2.addTagFilter("a", values: ["value2"])
        filter2.addTagFilter("z", values: ["value3"]) // Different value but same tag
        
        // When
        let fp1 = NDKFilterGrouping.filterFingerprint([filter1], closeOnEose: false)
        let fp2 = NDKFilterGrouping.filterFingerprint([filter2], closeOnEose: false)
        
        // Then - Should produce same fingerprint
        XCTAssertEqual(fp1, fp2)
        XCTAssertEqual(fp1, "#a-#z-authors-kinds")
    }
    
    // MARK: - Filter Merging Tests
    
    func testMergeFiltersBasic() {
        // Given
        let filter1 = NDKFilter(authors: ["author1"], kinds: [1])
        let filter2 = NDKFilter(authors: ["author2"], kinds: [1])
        let filter3 = NDKFilter(authors: ["author3"], kinds: [1, 6])
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2, filter3])
        
        // Then
        XCTAssertEqual(merged.count, 1)
        let result = merged[0]
        XCTAssertEqual(Set(result.authors ?? []), Set(["author1", "author2", "author3"]))
        XCTAssertEqual(Set(result.kinds ?? []), Set([1, 6]))
    }
    
    func testMergeFiltersWithLimits() {
        // Given
        let filter1 = NDKFilter(kinds: [1], limit: 10)
        let filter2 = NDKFilter(kinds: [1], limit: 20)
        let filter3 = NDKFilter(kinds: [1]) // No limit
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2, filter3])
        
        // Then
        XCTAssertEqual(merged.count, 3) // 2 with limits + 1 merged
        
        // Filters with limits should be included unchanged
        let limits = merged.compactMap { $0.limit }
        XCTAssertEqual(Set(limits), Set([10, 20]))
        
        // Filter without limit should be merged
        let mergedFilter = merged.first { $0.limit == nil }
        XCTAssertNotNil(mergedFilter)
        XCTAssertEqual(mergedFilter?.kinds, [1])
    }
    
    func testMergeFiltersWithTags() {
        // Given
        var filter1 = NDKFilter()
        filter1.addTagFilter("p", values: ["pubkey1", "pubkey2"])
        
        var filter2 = NDKFilter()
        filter2.addTagFilter("p", values: ["pubkey2", "pubkey3"])
        filter2.addTagFilter("e", values: ["event1"])
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2])
        
        // Then
        XCTAssertEqual(merged.count, 1)
        let result = merged[0]
        
        let pTags = result.tags?["p"] ?? []
        XCTAssertEqual(Set(pTags), Set(["pubkey1", "pubkey2", "pubkey3"]))
        
        let eTags = result.tags?["e"] ?? []
        XCTAssertEqual(Set(eTags), Set(["event1"]))
    }
    
    func testMergeFiltersPreservesTimeConstraints() {
        // Given
        let filter1 = NDKFilter(kinds: [1], since: 1000, until: 2000)
        let filter2 = NDKFilter(kinds: [6])
        let filter3 = NDKFilter(kinds: [7])
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2, filter3])
        
        // Then
        XCTAssertEqual(merged.count, 1)
        let result = merged[0]
        XCTAssertEqual(result.since, 1000)
        XCTAssertEqual(result.until, 2000)
        XCTAssertEqual(Set(result.kinds ?? []), Set([1, 6, 7]))
    }
    
    func testMergeEmptyFilters() {
        // When
        let merged = NDKFilterGrouping.mergeFilters([])
        
        // Then
        XCTAssertEqual(merged.count, 0)
    }
    
    func testMergeFiltersWithAllFields() {
        // Given
        var filter1 = NDKFilter(
            ids: ["id1", "id2"],
            authors: ["author1"],
            kinds: [1, 7]
        )
        filter1.events = ["event1"]
        filter1.pubkeys = ["pubkey1"]
        filter1.addTagFilter("t", values: ["bitcoin"])
        
        var filter2 = NDKFilter(
            ids: ["id2", "id3"],
            authors: ["author2"],
            kinds: [1, 4]
        )
        filter2.events = ["event2"]
        filter2.pubkeys = ["pubkey2"]
        filter2.addTagFilter("t", values: ["nostr"])
        filter2.addTagFilter("g", values: ["general"])
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2])
        
        // Then
        XCTAssertEqual(merged.count, 1)
        let result = merged[0]
        
        XCTAssertEqual(Set(result.ids ?? []), Set(["id1", "id2", "id3"]))
        XCTAssertEqual(Set(result.authors ?? []), Set(["author1", "author2"]))
        XCTAssertEqual(Set(result.kinds ?? []), Set([1, 4, 7]))
        XCTAssertEqual(Set(result.events ?? []), Set(["event1", "event2"]))
        XCTAssertEqual(Set(result.pubkeys ?? []), Set(["pubkey1", "pubkey2"]))
        
        let tTags = result.tags?["t"] ?? []
        XCTAssertEqual(Set(tTags), Set(["bitcoin", "nostr"]))
        
        let gTags = result.tags?["g"] ?? []
        XCTAssertEqual(Set(gTags), Set(["general"]))
    }
    
    func testMergeFiltersOnlyLimits() {
        // Given - Only filters with limits
        let filter1 = NDKFilter(kinds: [1], limit: 10)
        let filter2 = NDKFilter(kinds: [7], limit: 20)
        let filter3 = NDKFilter(authors: ["author1"], limit: 5)
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2, filter3])
        
        // Then - All should be concatenated, none merged
        XCTAssertEqual(merged.count, 3)
        
        // Verify all filters are preserved
        let limits = merged.compactMap { $0.limit }
        XCTAssertEqual(Set(limits), Set([10, 20, 5]))
    }
    
    func testMergeFiltersMixedLimits() {
        // Given - Mix of filters with and without limits
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(kinds: [1], limit: 10)
        let filter3 = NDKFilter(kinds: [7])
        let filter4 = NDKFilter(kinds: [7], limit: 20)
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2, filter3, filter4])
        
        // Then
        XCTAssertEqual(merged.count, 3) // 1 merged + 2 with limits
        
        // Find the merged filter (no limit)
        let mergedFilter = merged.first { $0.limit == nil }
        XCTAssertNotNil(mergedFilter)
        XCTAssertEqual(Set(mergedFilter?.kinds ?? []), Set([1, 7]))
        
        // Verify filters with limits are preserved
        let limitedFilters = merged.filter { $0.limit != nil }
        XCTAssertEqual(limitedFilters.count, 2)
        let limits = limitedFilters.compactMap { $0.limit }
        XCTAssertEqual(Set(limits), Set([10, 20]))
    }
    
    func testMergeFiltersSingleFilter() {
        // Given
        let filter = NDKFilter(authors: ["author1"], kinds: [1, 7])
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter])
        
        // Then
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(Set(merged[0].kinds ?? []), Set([1, 7]))
        XCTAssertEqual(merged[0].authors, ["author1"])
    }
    
    // MARK: - Edge Cases
    
    func testFilterFingerprintEmptyFilter() {
        // Given
        let filter = NDKFilter()
        
        // When
        let fp = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: false)
        
        // Then
        XCTAssertEqual(fp, "") // Empty filter produces empty fingerprint
    }
    
    func testFilterFingerprintEmptyArray() {
        // When
        let fp = NDKFilterGrouping.filterFingerprint([], closeOnEose: false)
        
        // Then
        XCTAssertEqual(fp, "") // No filters produces empty fingerprint
    }
    
    func testMergeFiltersEmptyFilters() {
        // Given
        let filter1 = NDKFilter()
        let filter2 = NDKFilter()
        
        // When
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2])
        
        // Then
        XCTAssertEqual(merged.count, 1)
        // Empty filters should still produce one merged result
    }
}