import XCTest
@testable import NDKSwift

/// Tests demonstrating the improved testability features for subscription grouping
@MainActor
final class SubscriptionGroupingTestabilityTests: XCTestCase {
    
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
    
    // MARK: - NDKSubscriptionCoordinator Inspection Tests
    
    func testSubscriptionCoordinatorInspection() async throws {
        // Create a subscription with specific properties
        let subscription = NDKSubscriptionCoordinator(
            id: "test-sub-123",
            filters: [NDKFilter(kinds: [1], authors: ["alice"])],
            relays: Set(["wss://relay1.com", "wss://relay2.com"]),
            ndk: ndk,
            closeOnEose: true,
            fingerprint: "test-fingerprint",
            isGroupable: true,
            groupableDelay: 0.5,
            groupableDelayType: .atLeast
        )
        
        // Inspect the subscription state
        let inspectionData = await subscription.inspect()
        
        // Verify all properties are accessible
        XCTAssertEqual(inspectionData.id, "test-sub-123")
        XCTAssertTrue(inspectionData.isGroupable)
        XCTAssertEqual(inspectionData.groupableDelay, 0.5)
        XCTAssertEqual(inspectionData.groupableDelayType, .atLeast)
        XCTAssertFalse(inspectionData.isActive) // Not started yet
        XCTAssertTrue(inspectionData.activeRelays.isEmpty)
        XCTAssertEqual(inspectionData.fingerprint, "test-fingerprint")
        XCTAssertTrue(inspectionData.closeOnEose)
        XCTAssertEqual(inspectionData.filterCount, 1)
    }
    
    func testSubscriptionStateChanges() async throws {
        let subscription = NDKSubscriptionCoordinator(
            id: "state-test",
            filters: [NDKFilter(kinds: [1])],
            relays: nil,
            ndk: ndk,
            closeOnEose: false
        )
        
        // Initial state
        var state = await subscription.inspect()
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.activeRelays.isEmpty)
        
        // Start subscription
        await subscription.start()
        
        // Check state after starting
        state = await subscription.inspect()
        XCTAssertTrue(state.isActive)
        
        // Mark relay as active
        await subscription.markRelayAsActive("wss://test.relay.com")
        
        // Check relay is tracked
        state = await subscription.inspect()
        XCTAssertTrue(state.activeRelays.contains("wss://test.relay.com"))
        
        // Close subscription
        await subscription.close()
        
        // Final state
        state = await subscription.inspect()
        XCTAssertFalse(state.isActive)
        XCTAssertTrue(state.activeRelays.isEmpty)
    }
    
    // MARK: - NDKRelaySubscriptionManager Debug Tests
    
    #if DEBUG
    func testDebugGroupingState() async throws {
        let filter1 = NDKFilter(kinds: [1], authors: ["alice"])
        let filter2 = NDKFilter(kinds: [1], authors: ["bob"])
        
        // Create multiple subscriptions
        let sub1 = NDKSubscriptionCoordinator(
            id: "sub1",
            filters: [filter1],
            relays: nil,
            ndk: ndk,
            isGroupable: true
        )
        
        let sub2 = NDKSubscriptionCoordinator(
            id: "sub2",
            filters: [filter1], // Same filter as sub1
            relays: nil,
            ndk: ndk,
            isGroupable: true
        )
        
        let sub3 = NDKSubscriptionCoordinator(
            id: "sub3",
            filters: [filter2], // Different filter
            relays: nil,
            ndk: ndk,
            isGroupable: true
        )
        
        // Add subscriptions to manager
        await manager.addSubscription(sub1, filters: [filter1])
        await manager.addSubscription(sub2, filters: [filter1])
        await manager.addSubscription(sub3, filters: [filter2])
        
        // Get grouping state
        let groupingState = await manager.debugGroupingState()
        
        // Should have 2 groups
        XCTAssertEqual(groupingState.count, 2, "Should have 2 groups (one for each unique filter)")
        
        // Find the group with sub1 and sub2
        let groupWithAlice = groupingState.values.first { $0.contains("sub1") && $0.contains("sub2") }
        XCTAssertNotNil(groupWithAlice, "sub1 and sub2 should be in the same group")
        XCTAssertEqual(groupWithAlice?.count, 2, "Alice group should have exactly 2 subscriptions")
        
        // Find the group with sub3
        let groupWithBob = groupingState.values.first { $0.contains("sub3") }
        XCTAssertNotNil(groupWithBob, "sub3 should be in its own group")
        XCTAssertEqual(groupWithBob?.count, 1, "Bob group should have exactly 1 subscription")
    }
    
    func testDebugGroupCount() async throws {
        // Initially no groups
        var count = await manager.debugGroupCount()
        XCTAssertEqual(count, 0)
        
        // Add subscriptions
        let filter = NDKFilter(kinds: [1])
        let sub1 = NDKSubscriptionCoordinator(
            id: "count-test-1",
            filters: [filter],
            relays: nil,
            ndk: ndk,
            isGroupable: true
        )
        
        await manager.addSubscription(sub1, filters: [filter])
        
        // Should have 1 group
        count = await manager.debugGroupCount()
        XCTAssertEqual(count, 1)
        
        // Add non-groupable subscription
        let sub2 = NDKSubscriptionCoordinator(
            id: "count-test-2",
            filters: [filter],
            relays: nil,
            ndk: ndk,
            isGroupable: false
        )
        
        await manager.addSubscription(sub2, filters: [filter])
        
        // Should have 2 groups (non-groupable creates its own group)
        count = await manager.debugGroupCount()
        XCTAssertEqual(count, 2)
    }
    
    func testFlushPendingGroups() async throws {
        // This test would require a mock relay to capture sent messages
        // For now, just verify the method can be called without error
        
        let filter = NDKFilter(kinds: [1])
        let sub = NDKSubscriptionCoordinator(
            id: "flush-test",
            filters: [filter],
            relays: nil,
            ndk: ndk,
            isGroupable: true,
            groupableDelay: 5.0 // Long delay
        )
        
        await manager.addSubscription(sub, filters: [filter])
        
        // Force immediate execution
        await manager.flushPendingGroups()
        
        // In a real test with mock relay, we would verify REQ was sent immediately
    }
    
    func testDebugInspectGroup() async throws {
        let filter = NDKFilter(kinds: [1], authors: ["alice"])
        let fingerprint = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: false)
        
        // Initially no group
        var groupInfo = await manager.debugInspectGroup(fingerprint: fingerprint)
        XCTAssertNil(groupInfo)
        
        // Add subscription
        let sub = NDKSubscriptionCoordinator(
            id: "inspect-test",
            filters: [filter],
            relays: nil,
            ndk: ndk,
            isGroupable: true
        )
        
        await manager.addSubscription(sub, filters: [filter])
        
        // Now inspect the group
        groupInfo = await manager.debugInspectGroup(fingerprint: fingerprint)
        XCTAssertNotNil(groupInfo)
        XCTAssertEqual(groupInfo?.fingerprint, fingerprint)
        XCTAssertTrue(groupInfo?.isGroupable ?? false)
        XCTAssertEqual(groupInfo?.itemCount, 1)
    }
    #endif
    
    // MARK: - Helper Methods
    
    private func createFilter(kinds: [Int]? = nil, authors: [String]? = nil) -> NDKFilter {
        var filter = NDKFilter()
        filter.kinds = kinds
        filter.authors = authors
        return filter
    }
}