import XCTest
@testable import NDKSwift

/// Tests for subscription grouping metrics collection
@MainActor
final class SubscriptionGroupingMetricsTests: XCTestCase {
    
    private var ndk: NDK!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        // Reset metrics before each test
        await NDKSubscriptionMetrics.reset()
    }
    
    override func tearDown() async throws {
        ndk = nil
        try await super.tearDown()
    }
    
    func testBasicMetricsCollection() async throws {
        // Get initial metrics
        var metrics = await ndk.getSubscriptionMetrics()
        XCTAssertEqual(metrics.totalSubscriptions, 0)
        XCTAssertEqual(metrics.groupedSubscriptions, 0)
        XCTAssertEqual(metrics.totalReqMessages, 0)
        
        // Create some subscriptions
        let filter = NDKFilter(kinds: [1])
        
        // Create groupable subscriptions
        let sub1 = ndk.subscribe(filter: filter)
        let sub2 = ndk.subscribe(filter: filter)
        let sub3 = ndk.subscribe(filter: filter)
        
        // Wait a bit for subscriptions to be processed
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Check metrics
        metrics = await ndk.getSubscriptionMetrics()
        XCTAssertEqual(metrics.totalSubscriptions, 3)
        // At least some should be grouped (exact count depends on timing)
        XCTAssertGreaterThan(metrics.groupedSubscriptions, 0)
    }
    
    func testNonGroupableSubscriptions() async throws {
        let filter = NDKFilter(kinds: [1])
        let options = NDKSubscriptionOptions()
        options.groupable = false
        
        // Create non-groupable subscriptions
        let sub1 = ndk.subscribe(filter: filter, options: options)
        let sub2 = ndk.subscribe(filter: filter, options: options)
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Check metrics
        let metrics = await ndk.getSubscriptionMetrics()
        XCTAssertEqual(metrics.totalSubscriptions, 2)
        XCTAssertEqual(metrics.nonGroupableSubscriptions, 2)
        XCTAssertEqual(metrics.groupedSubscriptions, 0)
    }
    
    func testMetricsSummary() async throws {
        // Create some test data
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: true)
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: true)
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: false)
        
        await NDKSubscriptionMetrics.recordGroupedSubscription()
        
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 3, relay: "wss://relay1.com")
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 1, relay: "wss://relay2.com")
        
        // Get metrics
        let metrics = await ndk.getSubscriptionMetrics()
        
        // Check summary format
        let summary = metrics.summary
        XCTAssertTrue(summary.contains("Total Subscriptions: 3"))
        XCTAssertTrue(summary.contains("Grouped Subscriptions: 1"))
        XCTAssertTrue(summary.contains("Non-Groupable: 1"))
        XCTAssertTrue(summary.contains("REQ Messages Sent: 2"))
        XCTAssertTrue(summary.contains("REQ Messages Saved: 2"))
        XCTAssertTrue(summary.contains("Average Group Size: 2.00"))
    }
    
    func testDelayStatistics() async throws {
        // Record some delays
        await NDKSubscriptionMetrics.recordDelay(
            actualDelay: 0.105,
            configuredDelay: 0.1,
            delayType: .atLeast
        )
        
        await NDKSubscriptionMetrics.recordDelay(
            actualDelay: 0.095,
            configuredDelay: 0.1,
            delayType: .atMost
        )
        
        await NDKSubscriptionMetrics.recordDelay(
            actualDelay: 0.110,
            configuredDelay: 0.1,
            delayType: .atLeast
        )
        
        let metrics = await ndk.getSubscriptionMetrics()
        
        XCTAssertEqual(metrics.delayStatistics.totalDelays, 3)
        XCTAssertEqual(metrics.delayStatistics.atLeastCount, 2)
        XCTAssertEqual(metrics.delayStatistics.atMostCount, 1)
        XCTAssertEqual(metrics.delayStatistics.averageActualDelay, 0.103, accuracy: 0.001)
        XCTAssertEqual(metrics.delayStatistics.averageConfiguredDelay, 0.1, accuracy: 0.001)
    }
    
    func testRelaySpecificMetrics() async throws {
        // Record metrics for different relays
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 5, relay: "wss://relay1.com")
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 3, relay: "wss://relay1.com")
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 2, relay: "wss://relay2.com")
        
        let metrics = await ndk.getSubscriptionMetrics()
        
        // Check relay-specific metrics
        XCTAssertEqual(metrics.relayMetrics.count, 2)
        
        let relay1Metrics = metrics.relayMetrics["wss://relay1.com"]
        XCTAssertNotNil(relay1Metrics)
        XCTAssertEqual(relay1Metrics?.totalReqMessages, 2)
        XCTAssertEqual(relay1Metrics?.averageGroupSize, 4.0, accuracy: 0.01)
        
        let relay2Metrics = metrics.relayMetrics["wss://relay2.com"]
        XCTAssertNotNil(relay2Metrics)
        XCTAssertEqual(relay2Metrics?.totalReqMessages, 1)
        XCTAssertEqual(relay2Metrics?.averageGroupSize, 2.0, accuracy: 0.01)
    }
    
    func testMetricsReset() async throws {
        // Add some data
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: true)
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 3, relay: "wss://relay.com")
        
        // Verify data exists
        var metrics = await ndk.getSubscriptionMetrics()
        XCTAssertGreaterThan(metrics.totalSubscriptions, 0)
        
        // Reset
        await ndk.resetSubscriptionMetrics()
        
        // Verify all cleared
        metrics = await ndk.getSubscriptionMetrics()
        XCTAssertEqual(metrics.totalSubscriptions, 0)
        XCTAssertEqual(metrics.totalReqMessages, 0)
        XCTAssertEqual(metrics.relayMetrics.count, 0)
    }
    
    func testGroupingEfficiencyCalculation() async throws {
        // Create scenario with known efficiency
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: true)
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: true)
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: true)
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: false)
        
        // Two subscriptions were grouped
        await NDKSubscriptionMetrics.recordGroupedSubscription()
        await NDKSubscriptionMetrics.recordGroupedSubscription()
        
        let metrics = await ndk.getSubscriptionMetrics()
        
        // Efficiency should be 2/4 = 50%
        XCTAssertEqual(metrics.groupingEfficiency, 0.5, accuracy: 0.01)
    }
    
    func testMessageReductionCalculation() async throws {
        // Send 3 messages: one group of 5, one group of 3, one single
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 5, relay: "wss://relay.com")
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 3, relay: "wss://relay.com")
        await NDKSubscriptionMetrics.recordReqMessage(groupSize: 1, relay: "wss://relay.com")
        
        let metrics = await ndk.getSubscriptionMetrics()
        
        // Total messages sent: 3
        // Messages saved: (5-1) + (3-1) + (1-1) = 4 + 2 + 0 = 6
        // Message reduction: 6 / (3 + 6) = 6/9 = 66.7%
        XCTAssertEqual(metrics.totalReqMessages, 3)
        XCTAssertEqual(metrics.reqMessagesSaved, 6)
        XCTAssertEqual(metrics.messageReduction, 2.0/3.0, accuracy: 0.01)
    }
}