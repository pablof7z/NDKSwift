import XCTest
@testable import NDKSwift

final class SubscriptionGroupingComprehensiveTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK(
            relayUrls: [],
            signer: nil,
            cache: MemoryCache()
        )
    }
    
    override func tearDown() async throws {
        await ndk.disconnect()
        ndk = nil
        try await super.tearDown()
    }
    
    // MARK: - Fingerprint Tests
    
    func testFingerprintGeneration() {
        // Test basic fingerprint structure
        let filter1 = NDKFilter(authors: ["author1"], kinds: [0])
        let filter2 = NDKFilter(authors: ["author2"], kinds: [0])
        
        // Create fingerprints
        let fp1 = NDKFilterFingerprint(filters: [filter1], closeOnEose: false)
        let fp2 = NDKFilterFingerprint(filters: [filter2], closeOnEose: false)
        
        // Same structure should produce same fingerprint
        XCTAssertEqual(fp1.value, fp2.value, "Filters with same structure should have same fingerprint")
        
        // IMPORTANT: Following ndk-core, different kinds values should produce SAME fingerprint
        // Only the presence of "kinds" matters, not the values
        let filter3 = NDKFilter(authors: ["author3"], kinds: [1])
        let fp3 = NDKFilterFingerprint(filters: [filter3], closeOnEose: false)
        XCTAssertEqual(fp1.value, fp3.value, "Filters with different kind values should have same fingerprint (ndk-core behavior)")
        
        // Different structure (missing kinds) should produce different fingerprint
        let filter4 = NDKFilter(authors: ["author4"]) // No kinds
        let fp5 = NDKFilterFingerprint(filters: [filter4], closeOnEose: false)
        XCTAssertNotEqual(fp1.value, fp5.value, "Filters with different structure should have different fingerprints")
        
        // Verify the fingerprints contain the expected structure
        XCTAssertTrue(fp1.value.contains("kinds"), "Fingerprint should contain 'kinds'")
        XCTAssertFalse(fp5.value.contains("kinds"), "Fingerprint without kinds should not contain 'kinds'")
        
        // closeOnEose should affect fingerprint
        let fp6 = NDKFilterFingerprint(filters: [filter1], closeOnEose: true)
        XCTAssertTrue(fp6.value.hasPrefix("+"), "closeOnEose fingerprints should start with +")
        XCTAssertNotEqual(fp1.value, fp6.value, "Different closeOnEose should produce different fingerprints")
    }
    
    func testFingerprintWithTimeConstraints() {
        // Time constraints should be included in fingerprint
        let filter1 = NDKFilter(kinds: [1], since: 1000000)
        let filter2 = NDKFilter(kinds: [1], since: 2000000)
        
        let fp1 = NDKFilterFingerprint(filters: [filter1], closeOnEose: false)
        let fp2 = NDKFilterFingerprint(filters: [filter2], closeOnEose: false)
        
        // Different time values should produce different fingerprints
        XCTAssertNotEqual(fp1.value, fp2.value, "Different time constraints should produce different fingerprints")
        XCTAssertTrue(fp1.value.contains("since:1000000"))
        XCTAssertTrue(fp2.value.contains("since:2000000"))
    }
    
    func testFingerprintWithLimits() {
        let filter1 = NDKFilter(kinds: [1], limit: 10)
        let filter2 = NDKFilter(kinds: [1])
        
        let fp1 = NDKFilterFingerprint(filters: [filter1], closeOnEose: false)
        let fp2 = NDKFilterFingerprint(filters: [filter2], closeOnEose: false)
        
        XCTAssertNotEqual(fp1.value, fp2.value, "Filters with/without limits should have different fingerprints")
        XCTAssertTrue(fp1.value.contains("limit"))
        XCTAssertFalse(fp2.value.contains("limit"))
    }
    
    // MARK: - Filter Merging Tests
    
    func testProfileRequestMerging() {
        // Multiple profile requests should merge
        let filter1 = NDKFilter(authors: ["pubkey1"], kinds: [EventKind.metadata])
        let filter2 = NDKFilter(authors: ["pubkey2"], kinds: [EventKind.metadata])
        let filter3 = NDKFilter(authors: ["pubkey3"], kinds: [EventKind.metadata])
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2]),
            createMockSubscription(filters: [filter3])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        XCTAssertEqual(merged.count, 1, "Profile requests should merge into single filter")
        if let mergedFilter = merged.first {
            XCTAssertEqual(Set(mergedFilter.authors ?? []), Set(["pubkey1", "pubkey2", "pubkey3"]))
            XCTAssertEqual(mergedFilter.kinds, [EventKind.metadata])
        }
    }
    
    func testNoteRequestMerging() {
        // Multiple note requests should merge
        let filter1 = NDKFilter(authors: ["alice"], kinds: [EventKind.textNote])
        let filter2 = NDKFilter(authors: ["bob"], kinds: [EventKind.textNote])
        let filter3 = NDKFilter(authors: ["charlie"], kinds: [EventKind.textNote])
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2]),
            createMockSubscription(filters: [filter3])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        XCTAssertEqual(merged.count, 1, "Note requests should merge into single filter")
        if let mergedFilter = merged.first {
            XCTAssertEqual(Set(mergedFilter.authors ?? []), Set(["alice", "bob", "charlie"]))
            XCTAssertEqual(mergedFilter.kinds, [EventKind.textNote])
        }
    }
    
    func testFiltersWithLimitsNotMerged() {
        // Filters with limits should not merge
        let filter1 = NDKFilter(authors: ["user1"], kinds: [1], limit: 10)
        let filter2 = NDKFilter(authors: ["user2"], kinds: [1], limit: 20)
        let filter3 = NDKFilter(authors: ["user3"], kinds: [1]) // No limit
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2]),
            createMockSubscription(filters: [filter3])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        // Should have 3 filters: 2 with limits (not merged) + 1 without limit
        XCTAssertEqual(merged.count, 3, "Filters with limits should not merge")
        
        // Verify limits are preserved
        let limitsInResult = merged.compactMap { $0.limit }
        XCTAssertTrue(limitsInResult.contains(10))
        XCTAssertTrue(limitsInResult.contains(20))
    }
    
    func testDifferentKindsMerge() {
        // Following ndk-core: Different kind VALUES with same structure WILL merge
        let filter1 = NDKFilter(authors: ["user1"], kinds: [0])    // Profile
        let filter2 = NDKFilter(authors: ["user2"], kinds: [1])    // Notes
        let filter3 = NDKFilter(authors: ["user3"], kinds: [3])    // Contacts
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2]),
            createMockSubscription(filters: [filter3])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        // All should merge into one filter with all authors and all kinds
        XCTAssertEqual(merged.count, 1, "Different kind values should merge (ndk-core behavior)")
        if let mergedFilter = merged.first {
            XCTAssertEqual(Set(mergedFilter.authors ?? []), Set(["user1", "user2", "user3"]))
            XCTAssertEqual(Set(mergedFilter.kinds ?? []), Set([0, 1, 3]))
        }
    }
    
    func testTagFilterMerging() {
        // Same structure tag filters should merge
        let filter1 = NDKFilter(kinds: [1], pubkeys: ["mentioned1"])
        let filter2 = NDKFilter(kinds: [1], pubkeys: ["mentioned2"])
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        XCTAssertEqual(merged.count, 1, "Tag filters with same structure should merge")
        if let mergedFilter = merged.first {
            XCTAssertEqual(Set(mergedFilter.pubkeys ?? []), Set(["mentioned1", "mentioned2"]))
        }
    }
    
    func testEventReferenceMerging() {
        // Event reference filters should merge
        let filter1 = NDKFilter(kinds: [42], events: ["event1"])
        let filter2 = NDKFilter(kinds: [42], events: ["event2"])
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        XCTAssertEqual(merged.count, 1, "Event reference filters should merge")
        if let mergedFilter = merged.first {
            XCTAssertEqual(Set(mergedFilter.events ?? []), Set(["event1", "event2"]))
        }
    }
    
    func testTimeConstraintHandling() {
        // Filters with same time constraints can merge
        let filter1 = NDKFilter(authors: ["user1"], kinds: [1], since: 1000000)
        let filter2 = NDKFilter(authors: ["user2"], kinds: [1], since: 1000000)
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        XCTAssertEqual(merged.count, 1, "Same time constraints should allow merging")
        if let mergedFilter = merged.first {
            XCTAssertEqual(mergedFilter.since, 1000000)
            XCTAssertEqual(Set(mergedFilter.authors ?? []), Set(["user1", "user2"]))
        }
    }
    
    func testComplexMergeScenario() {
        // Mix of mergeable and non-mergeable filters
        let filter1 = NDKFilter(authors: ["user1"], kinds: [1])        // Will merge with filter2 AND filter4
        let filter2 = NDKFilter(authors: ["user2"], kinds: [1])        // Will merge with filter1 AND filter4
        let filter3 = NDKFilter(authors: ["user3"], kinds: [1], limit: 5) // Won't merge (has limit)
        let filter4 = NDKFilter(authors: ["user4"], kinds: [0])        // Will merge with filter1 and filter2 (ndk-core behavior)
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2]),
            createMockSubscription(filters: [filter3]),
            createMockSubscription(filters: [filter4])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        // With ndk-core behavior: Should have 2 filters total:
        // 1. kind:1 with limit:5 (user3) - not merged due to limit
        // 2. Merged filter with all kinds and authors (user1, user2, user4)
        XCTAssertEqual(merged.count, 2, "Should have 2 merged results")
        
        // Find and verify each result
        let limitedFilter = merged.first { $0.limit == 5 }
        XCTAssertNotNil(limitedFilter, "Should have filter with limit 5")
        XCTAssertEqual(limitedFilter?.authors, ["user3"])
        XCTAssertEqual(limitedFilter?.kinds, [1])
        
        // The merged filter should have all authors and all kinds
        let mergedFilter = merged.first { $0.limit == nil }
        XCTAssertNotNil(mergedFilter, "Should have merged filter")
        XCTAssertEqual(Set(mergedFilter?.authors ?? []), Set(["user1", "user2", "user4"]), "Should have all authors")
        XCTAssertEqual(Set(mergedFilter?.kinds ?? []), Set([0, 1]), "Should have all kinds")
    }
    
    func testIDBasedFilterMerging() {
        // ID-based filters should merge
        let filter1 = NDKFilter(ids: ["id1", "id2"])
        let filter2 = NDKFilter(ids: ["id3", "id4"])
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        XCTAssertEqual(merged.count, 1, "ID filters should merge")
        if let mergedFilter = merged.first {
            XCTAssertEqual(Set(mergedFilter.ids ?? []), Set(["id1", "id2", "id3", "id4"]))
        }
    }
    
    func testMultipleKindsSameStructure() {
        // Multiple kinds with same structure should merge
        let filter1 = NDKFilter(authors: ["user1"], kinds: [1, 6, 7])
        let filter2 = NDKFilter(authors: ["user2"], kinds: [1, 6, 7])
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        XCTAssertEqual(merged.count, 1, "Same kind sets should merge")
        if let mergedFilter = merged.first {
            XCTAssertEqual(Set(mergedFilter.authors ?? []), Set(["user1", "user2"]))
            XCTAssertEqual(Set(mergedFilter.kinds ?? []), Set([1, 6, 7]))
        }
    }
    
    func testEmptyFilterHandling() {
        // Test edge case with empty filters
        let filter1 = NDKFilter()
        let filter2 = NDKFilter()
        
        let subscriptions = [
            createMockSubscription(filters: [filter1]),
            createMockSubscription(filters: [filter2])
        ]
        
        let merged = NDKSubscriptionManager.mergeFilters(from: subscriptions)
        
        // Empty filters should merge into one
        XCTAssertEqual(merged.count, 1, "Empty filters should merge")
    }
    
    // MARK: - Helper Methods
    
    private func createMockSubscription(filters: [NDKFilter]) -> NDKSubscription {
        let subscription = NDKSubscription(
            filters: filters,
            options: NDKSubscriptionOptions(),
            ndk: ndk
        )
        return subscription
    }
}

// MARK: - NDKSubscriptionManager Extension for Testing

extension NDKSubscriptionManager {
    /// Static helper to test filter merging logic
    static func mergeFilters(from subscriptions: [NDKSubscription]) -> [NDKFilter] {
        // Following ndk-core approach:
        // 1. Filters with limit are not merged - kept separate
        // 2. Filters without limit are merged using union semantics
        // 3. Limited filters come first in the result
        
        var limitedFilters: [NDKFilter] = []
        var unlimitedFilters: [NDKFilter] = []
        
        // Separate filters by whether they have limits
        for subscription in subscriptions {
            for filter in subscription.filters {
                if filter.limit != nil {
                    limitedFilters.append(filter)
                } else {
                    unlimitedFilters.append(filter)
                }
            }
        }
        
        // Merge unlimited filters using union semantics
        let mergedUnlimited = mergeUnlimitedFiltersIntoArray(unlimitedFilters)
        
        // Combine results: limited filters first, then merged unlimited
        var result = limitedFilters
        result.append(contentsOf: mergedUnlimited)
        
        return result
    }
    
    /// Merge filters without limits using union semantics
    private static func mergeUnlimitedFilters(_ filters: [NDKFilter]) -> NDKFilter? {
        guard !filters.isEmpty else { return nil }
        
        // Group filters by their fingerprint (structure + kinds)
        var groups: [String: [NDKFilter]] = [:]
        
        for filter in filters {
            // Create a fingerprint based on structure only (ndk-core behavior)
            var keys: [String] = []
            if filter.ids != nil { keys.append("ids") }
            if filter.authors != nil { keys.append("authors") }
            if filter.kinds != nil { keys.append("kinds") } // Just "kinds", not values
            if filter.events != nil { keys.append("#e") }
            if filter.pubkeys != nil { keys.append("#p") }
            if let since = filter.since { keys.append("since:\(since)") } // Time includes value
            if let until = filter.until { keys.append("until:\(until)") } // Time includes value
            if let tags = filter.tags {
                for tagName in tags.keys.sorted() {
                    keys.append("#\(tagName)")
                }
            }
            
            let fingerprint = keys.sorted().joined(separator: "-")
            if groups[fingerprint] == nil {
                groups[fingerprint] = []
            }
            groups[fingerprint]?.append(filter)
        }
        
        // Merge each group separately
        var mergedFilters: [NDKFilter] = []
        for (_, groupFilters) in groups {
            if let merged = mergeFilterGroup(groupFilters) {
                mergedFilters.append(merged)
            }
        }
        
        // Return all merged filters for the test
        // In the real implementation, these would be returned as an array
        if mergedFilters.count == 1 {
            return mergedFilters[0]
        } else if mergedFilters.isEmpty {
            return nil
        } else {
            // For tests, we need to handle multiple merged filters differently
            // This is a limitation of the test helper
            return nil
        }
    }
    
    /// Merge filters and return array of merged results
    private static func mergeUnlimitedFiltersIntoArray(_ filters: [NDKFilter]) -> [NDKFilter] {
        guard !filters.isEmpty else { return [] }
        
        // Group filters by their fingerprint (structure + kinds)
        var groups: [String: [NDKFilter]] = [:]
        
        for filter in filters {
            // Create a fingerprint based on structure only (ndk-core behavior)
            var keys: [String] = []
            if filter.ids != nil { keys.append("ids") }
            if filter.authors != nil { keys.append("authors") }
            if filter.kinds != nil { keys.append("kinds") } // Just "kinds", not values
            if filter.events != nil { keys.append("#e") }
            if filter.pubkeys != nil { keys.append("#p") }
            if let since = filter.since { keys.append("since:\(since)") } // Time includes value
            if let until = filter.until { keys.append("until:\(until)") } // Time includes value
            if let tags = filter.tags {
                for tagName in tags.keys.sorted() {
                    keys.append("#\(tagName)")
                }
            }
            
            let fingerprint = keys.sorted().joined(separator: "-")
            if groups[fingerprint] == nil {
                groups[fingerprint] = []
            }
            groups[fingerprint]?.append(filter)
        }
        
        // Merge each group separately
        var mergedFilters: [NDKFilter] = []
        for (_, groupFilters) in groups {
            if let merged = mergeFilterGroup(groupFilters) {
                mergedFilters.append(merged)
            }
        }
        
        return mergedFilters
    }
    
    private static func mergeFilterGroup(_ filters: [NDKFilter]) -> NDKFilter? {
        guard !filters.isEmpty else { return nil }
        
        // Start with empty sets
        var mergedIds = Set<EventID>()
        var mergedAuthors = Set<PublicKey>()
        var mergedKinds = Set<Kind>()
        var mergedEvents = Set<EventID>()
        var mergedPubkeys = Set<PublicKey>()
        var mergedTags: [String: Set<String>] = [:]
        
        // Use most inclusive time range
        var mergedSince: Timestamp?
        var mergedUntil: Timestamp?
        
        // Union all filter values
        for filter in filters {
            if let ids = filter.ids { mergedIds.formUnion(ids) }
            if let authors = filter.authors { mergedAuthors.formUnion(authors) }
            if let kinds = filter.kinds { mergedKinds.formUnion(kinds) }
            if let events = filter.events { mergedEvents.formUnion(events) }
            if let pubkeys = filter.pubkeys { mergedPubkeys.formUnion(pubkeys) }
            
            // For time constraints, use most inclusive range
            if let since = filter.since {
                mergedSince = mergedSince != nil ? min(mergedSince!, since) : since
            }
            if let until = filter.until {
                mergedUntil = mergedUntil != nil ? max(mergedUntil!, until) : until
            }
            
            // Merge tag filters
            if let tags = filter.tags {
                for (tagName, values) in tags {
                    if mergedTags[tagName] == nil {
                        mergedTags[tagName] = Set<String>()
                    }
                    mergedTags[tagName]?.formUnion(values)
                }
            }
        }
        
        // Create merged filter
        return NDKFilter(
            ids: mergedIds.isEmpty ? nil : Array(mergedIds),
            authors: mergedAuthors.isEmpty ? nil : Array(mergedAuthors),
            kinds: mergedKinds.isEmpty ? nil : Array(mergedKinds),
            events: mergedEvents.isEmpty ? nil : Array(mergedEvents),
            pubkeys: mergedPubkeys.isEmpty ? nil : Array(mergedPubkeys),
            since: mergedSince,
            until: mergedUntil,
            limit: nil, // Unlimited filters only
            tags: mergedTags.isEmpty ? nil : mergedTags
        )
    }
}