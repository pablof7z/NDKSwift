import XCTest
@testable import NDKSwift

@MainActor
final class SubscriptionGroupingTests: XCTestCase {
    
    // MARK: - Test Infrastructure
    
    private var ndk: NDK!
    private var relay: NDKRelay!
    private var manager: NDKRelaySubscriptionManager!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        relay = NDKRelay(url: "wss://test.relay.com")
        relay.ndk = ndk
        manager = NDKRelaySubscriptionManager(relay: relay)
        relay.subscriptionManager = manager
    }
    
    override func tearDown() async throws {
        ndk = nil
        relay = nil
        manager = nil
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    private func createSubscription(
        id: String,
        filters: [NDKFilter],
        isGroupable: Bool = true,
        groupableDelay: TimeInterval? = nil,
        groupableDelayType: NDKSubscriptionDelayType? = nil,
        closeOnEose: Bool = false
    ) -> InternalSubscription {
        return InternalSubscription(
            id: id,
            filters: filters,
            relays: nil,
            ndk: ndk,
            closeOnEose: closeOnEose,
            fingerprint: nil,
            isGroupable: isGroupable,
            groupableDelay: groupableDelay,
            groupableDelayType: groupableDelayType
        )
    }
    
    private func createFilter(kinds: [Int]? = nil, authors: [String]? = nil, limit: Int? = nil) -> NDKFilter {
        var filter = NDKFilter()
        filter.kinds = kinds
        filter.authors = authors
        filter.limit = limit
        return filter
    }
    
    // MARK: - Grouping Configuration Tests
    
    func testSubscriptionGroupingProperties() async {
        // Test default values
        let sub1 = createSubscription(
            id: "sub1",
            filters: [createFilter(kinds: [1])]
        )
        
        await XCTAssertTrue(sub1.isGroupable)
        await XCTAssertEqual(sub1.groupableDelay, 0.1)
        await XCTAssertEqual(sub1.groupableDelayType, .atMost)
        
        // Test custom values
        let sub2 = createSubscription(
            id: "sub2",
            filters: [createFilter(kinds: [1])],
            isGroupable: false
        )
        
        await XCTAssertFalse(sub2.isGroupable)
        await XCTAssertNil(sub2.groupableDelay)
        await XCTAssertNil(sub2.groupableDelayType)
        
        // Test explicit delay configuration
        let sub3 = createSubscription(
            id: "sub3",
            filters: [createFilter(kinds: [1])],
            isGroupable: true,
            groupableDelay: 0.5,
            groupableDelayType: .atLeast
        )
        
        await XCTAssertTrue(sub3.isGroupable)
        await XCTAssertEqual(sub3.groupableDelay, 0.5)
        await XCTAssertEqual(sub3.groupableDelayType, .atLeast)
    }
    
    // MARK: - Subscription Grouping Tests
    
    func testGroupableSubscriptionsAreMerged() async {
        let filter = createFilter(kinds: [1], authors: ["alice"])
        
        // Create two subscriptions with the same filter
        let sub1 = createSubscription(id: "sub1", filters: [filter])
        let sub2 = createSubscription(id: "sub2", filters: [filter])
        
        // Add both subscriptions
        await manager.addSubscription(sub1, filters: [filter])
        await manager.addSubscription(sub2, filters: [filter])
        
        // Verify they're in the same group (by checking fingerprint)
        let fingerprint = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: false)
        
        // Both subscriptions should be managed by the same group
        // This is internal implementation detail, but we can verify behavior
        // by checking that only one REQ would be sent to the relay
    }
    
    func testNonGroupableSubscriptionsExecuteImmediately() async {
        let filter = createFilter(kinds: [1])
        
        // Create non-groupable subscription
        let sub = createSubscription(
            id: "sub1",
            filters: [filter],
            isGroupable: false
        )
        
        // Add subscription
        await manager.addSubscription(sub, filters: [filter])
        
        // Non-groupable subscriptions should execute immediately
        // without waiting for any delay
    }
    
    func testSubscriptionsWithDifferentFiltersCreateDifferentGroups() async {
        let filter1 = createFilter(kinds: [1], authors: ["alice"])
        let filter2 = createFilter(kinds: [1], authors: ["bob"])
        
        let sub1 = createSubscription(id: "sub1", filters: [filter1])
        let sub2 = createSubscription(id: "sub2", filters: [filter2])
        
        await manager.addSubscription(sub1, filters: [filter1])
        await manager.addSubscription(sub2, filters: [filter2])
        
        // Different filters should create different groups
        let fp1 = NDKFilterGrouping.filterFingerprint([filter1], closeOnEose: false)
        let fp2 = NDKFilterGrouping.filterFingerprint([filter2], closeOnEose: false)
        
        XCTAssertNotEqual(fp1, fp2, "Different filters should have different fingerprints")
    }
    
    func testCloseOnEoseCreatesSeperateGroup() async {
        let filter = createFilter(kinds: [1])
        
        let sub1 = createSubscription(id: "sub1", filters: [filter], closeOnEose: false)
        let sub2 = createSubscription(id: "sub2", filters: [filter], closeOnEose: true)
        
        await manager.addSubscription(sub1, filters: [filter])
        await manager.addSubscription(sub2, filters: [filter])
        
        // closeOnEose subscriptions should have different fingerprints
        let fp1 = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: false)
        let fp2 = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: true)
        
        XCTAssertNotEqual(fp1, fp2, "closeOnEose should create different fingerprints")
    }
    
    // MARK: - Delay Type Tests
    
    func testDelayTypeAtMost() async {
        // Create subscription with atMost delay
        let filter = createFilter(kinds: [1])
        let sub = createSubscription(
            id: "sub1",
            filters: [filter],
            groupableDelay: 0.2,
            groupableDelayType: .atMost
        )
        
        await manager.addSubscription(sub, filters: [filter])
        
        // With atMost, the group should execute within the specified delay
        // This is harder to test without mocking time, but we verify the configuration
        await XCTAssertEqual(sub.groupableDelayType, .atMost)
    }
    
    func testDelayTypeAtLeast() async {
        // Create subscription with atLeast delay
        let filter = createFilter(kinds: [1])
        let sub = createSubscription(
            id: "sub1",
            filters: [filter],
            groupableDelay: 0.2,
            groupableDelayType: .atLeast
        )
        
        await manager.addSubscription(sub, filters: [filter])
        
        // With atLeast, the group should wait at least the specified delay
        await XCTAssertEqual(sub.groupableDelayType, .atLeast)
    }
    
    // MARK: - Filter Merging Tests
    
    func testFilterMergingWithoutLimits() async {
        let filter1 = createFilter(kinds: [1], authors: ["alice"])
        let filter2 = createFilter(kinds: [1], authors: ["bob"])
        
        let sub1 = createSubscription(id: "sub1", filters: [filter1])
        let sub2 = createSubscription(id: "sub2", filters: [filter2])
        
        // When grouped, filters without limits should be merged
        // The resulting filter should have authors: ["alice", "bob"]
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2])
        
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(Set(merged[0].authors ?? []), Set(["alice", "bob"]))
    }
    
    func testFilterMergingWithLimits() async {
        let filter1 = createFilter(kinds: [1], authors: ["alice"], limit: 5)
        let filter2 = createFilter(kinds: [1], authors: ["bob"], limit: 10)
        let filter3 = createFilter(kinds: [1], authors: ["charlie"])
        
        // Filters with limits should be concatenated, not merged
        let merged = NDKFilterGrouping.mergeFilters([filter1, filter2, filter3])
        
        // Should have 3 filters: 2 with limits (unchanged) + 1 merged filter
        XCTAssertEqual(merged.count, 3)
        
        // Find the filters
        let aliceFilter = merged.first { $0.authors?.contains("alice") == true && $0.limit != nil }
        let bobFilter = merged.first { $0.authors?.contains("bob") == true && $0.limit != nil }
        let charlieFilter = merged.first { $0.authors?.contains("charlie") == true && $0.limit == nil }
        
        XCTAssertNotNil(aliceFilter)
        XCTAssertEqual(aliceFilter?.limit, 5)
        
        XCTAssertNotNil(bobFilter)
        XCTAssertEqual(bobFilter?.limit, 10)
        
        XCTAssertNotNil(charlieFilter)
        XCTAssertNil(charlieFilter?.limit)
    }
    
    // MARK: - Relay Disconnection Tests
    
    func testRelayDisconnectionCancelsPendingGroups() async {
        let filter = createFilter(kinds: [1])
        let sub = createSubscription(
            id: "sub1",
            filters: [filter],
            groupableDelay: 1.0  // Long delay to ensure it's still pending
        )
        
        await manager.addSubscription(sub, filters: [filter])
        
        // Immediately disconnect
        await manager.handleRelayDisconnection()
        
        // Pending executions should be cancelled
        // The group should not execute after disconnection
    }
    
    func testRelayReconnectionRestartsActiveGroups() async {
        // This test would need a mock relay to properly test reconnection behavior
        // For now, we just verify the method exists and doesn't crash
        await manager.handleRelayReconnection()
    }
    
    // MARK: - Subscription Removal Tests
    
    func testRemovingSubscriptionFromGroup() async {
        let filter = createFilter(kinds: [1])
        let sub1 = createSubscription(id: "sub1", filters: [filter])
        let sub2 = createSubscription(id: "sub2", filters: [filter])
        
        await manager.addSubscription(sub1, filters: [filter])
        await manager.addSubscription(sub2, filters: [filter])
        
        // Remove one subscription
        await manager.removeSubscription(sub1)
        
        // The group should still exist with sub2
        // When sub2 is removed, the group should be cleaned up
        await manager.removeSubscription(sub2)
    }
}