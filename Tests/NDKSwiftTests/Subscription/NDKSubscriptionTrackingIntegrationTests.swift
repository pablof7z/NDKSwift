import XCTest
@testable import NDKSwift

final class NDKSubscriptionTrackingIntegrationTests: XCTestCase {
    var ndk: NDK!
    var mockRelay1: MockRelay!
    var mockRelay2: MockRelay!
    
    override func setUp() async throws {
        // Create NDK with subscription tracking enabled
        ndk = NDK(
            subscriptionTrackingConfig: NDK.SubscriptionTrackingConfig(
                trackClosedSubscriptions: true,
                maxClosedSubscriptions: 50
            )
        )
        
        // Add mock relays
        mockRelay1 = MockRelay(url: "wss://relay1.test")
        mockRelay2 = MockRelay(url: "wss://relay2.test")
    }
    
    // MARK: - Integration Tests
    
    func testSubscriptionTrackingWithRealSubscription() async throws {
        // Create subscription
        let filter = NDKFilter(kinds: [1], limit: 10)
        let subscription = ndk.subscribe(filters: [filter])
        
        // Wait for tracking to register
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify subscription is tracked
        let activeCount = await ndk.subscriptionTracker.activeSubscriptionCount()
        XCTAssertEqual(activeCount, 1)
        
        let detail = await ndk.subscriptionTracker.getSubscriptionDetail(subscription.id)
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.originalFilter, filter)
    }
    
    func testMultipleSubscriptionsTracking() async throws {
        // Create multiple subscriptions
        let sub1 = ndk.subscribe(filters: [NDKFilter(kinds: [1])])
        let sub2 = ndk.subscribe(filters: [NDKFilter(kinds: [3])])
        let sub3 = ndk.subscribe(filters: [NDKFilter(authors: ["pubkey1", "pubkey2"])])
        
        // Wait for tracking
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify all are tracked
        let activeCount = await ndk.subscriptionTracker.activeSubscriptionCount()
        XCTAssertEqual(activeCount, 3)
        
        let allSubs = await ndk.subscriptionTracker.getAllActiveSubscriptions()
        XCTAssertEqual(allSubs.count, 3)
        
        // Check individual subscriptions
        let detail1 = await ndk.subscriptionTracker.getSubscriptionDetail(sub1.id)
        XCTAssertEqual(detail1?.originalFilter.kinds, [1])
        
        let detail2 = await ndk.subscriptionTracker.getSubscriptionDetail(sub2.id)
        XCTAssertEqual(detail2?.originalFilter.kinds, [3])
        
        let detail3 = await ndk.subscriptionTracker.getSubscriptionDetail(sub3.id)
        XCTAssertEqual(detail3?.originalFilter.authors, ["pubkey1", "pubkey2"])
    }
    
    func testGlobalStatistics() async throws {
        // Create subscriptions and close some
        let sub1 = ndk.subscribe(filters: [NDKFilter(kinds: [1])])
        let sub2 = ndk.subscribe(filters: [NDKFilter(kinds: [3])])
        let sub3 = ndk.subscribe(filters: [NDKFilter(kinds: [4])])
        
        // Wait for tracking
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Close one subscription
        sub2.close()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Get statistics
        let stats = await ndk.subscriptionTracker.getStatistics()
        XCTAssertEqual(stats.activeSubscriptions, 2)
        XCTAssertEqual(stats.totalSubscriptions, 3)
        XCTAssertEqual(stats.closedSubscriptionsTracked, 1)
    }
    
    func testSubscriptionTrackingQueries() async throws {
        // Create subscription
        let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1, 3, 4])])
        
        // Wait for tracking
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Test various queries
        let totalUnique = await ndk.subscriptionTracker.totalUniqueEventsReceived()
        XCTAssertEqual(totalUnique, 0) // No events yet
        
        let metrics = await ndk.subscriptionTracker.getSubscriptionMetrics(subscription.id)
        XCTAssertNotNil(metrics)
        XCTAssertTrue(metrics?.isActive ?? false)
        XCTAssertEqual(metrics?.totalEvents, 0)
    }
    
    func testClosedSubscriptionHistory() async throws {
        // Create and close multiple subscriptions
        for i in 1...5 {
            let sub = ndk.subscribe(
                filters: [NDKFilter(kinds: [i])],
                options: NDKSubscriptionOptions(closeOnEose: true)
            )
            
            // Simulate some activity
            try await Task.sleep(nanoseconds: 50_000_000)
            
            // Close subscription
            sub.close()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        
        // Check closed history
        let closedSubs = await ndk.subscriptionTracker.getClosedSubscriptions()
        XCTAssertEqual(closedSubs.count, 5)
        
        // Verify closed subscription data
        for (index, closedSub) in closedSubs.enumerated() {
            XCTAssertEqual(closedSub.filter.kinds, [index + 1])
            XCTAssertGreaterThan(closedSub.duration, 0)
            XCTAssertNotNil(closedSub.startTime)
            XCTAssertNotNil(closedSub.endTime)
        }
    }
    
    func testExportImportTrackingData() async throws {
        // Create some subscriptions
        let sub1 = ndk.subscribe(filters: [NDKFilter(kinds: [1])])
        let sub2 = ndk.subscribe(filters: [NDKFilter(kinds: [3])])
        
        // Wait and close one
        try await Task.sleep(nanoseconds: 100_000_000)
        sub1.close()
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Export data
        let exportedData = await ndk.subscriptionTracker.exportTrackingData()
        
        // Verify exported data structure
        XCTAssertNotNil(exportedData["activeSubscriptions"])
        XCTAssertNotNil(exportedData["closedSubscriptions"])
        XCTAssertNotNil(exportedData["statistics"])
        
        // Verify content
        if let activeSubs = exportedData["activeSubscriptions"] as? [[String: Any]] {
            XCTAssertEqual(activeSubs.count, 1)
        }
        
        if let closedSubs = exportedData["closedSubscriptions"] as? [[String: Any]] {
            XCTAssertEqual(closedSubs.count, 1)
        }
        
        if let stats = exportedData["statistics"] as? [String: Any] {
            XCTAssertEqual(stats["activeSubscriptions"] as? Int, 1)
            XCTAssertEqual(stats["totalSubscriptions"] as? Int, 2)
        }
    }
    
    func testClearClosedSubscriptionHistory() async throws {
        // Create and close some subscriptions
        for i in 1...3 {
            let sub = ndk.subscribe(filters: [NDKFilter(kinds: [i])])
            try await Task.sleep(nanoseconds: 50_000_000)
            sub.close()
        }
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify history exists
        var closedSubs = await ndk.subscriptionTracker.getClosedSubscriptions()
        XCTAssertEqual(closedSubs.count, 3)
        
        // Clear history
        await ndk.subscriptionTracker.clearClosedSubscriptionHistory()
        
        // Verify history is cleared
        closedSubs = await ndk.subscriptionTracker.getClosedSubscriptions()
        XCTAssertEqual(closedSubs.count, 0)
        
        // Statistics should still show total subscriptions
        let stats = await ndk.subscriptionTracker.getStatistics()
        XCTAssertEqual(stats.totalSubscriptions, 3)
        XCTAssertEqual(stats.closedSubscriptionsTracked, 0)
    }
    
    // MARK: - Performance Tests
    
    func testTrackingPerformanceWithManySubscriptions() async throws {
        let subscriptionCount = 100
        
        let startTime = Date()
        
        // Create many subscriptions
        var subscriptions: [NDKSubscription] = []
        for i in 0..<subscriptionCount {
            let sub = ndk.subscribe(filters: [NDKFilter(kinds: [i])])
            subscriptions.append(sub)
        }
        
        // Wait for all to be tracked
        try await Task.sleep(nanoseconds: 200_000_000)
        
        let creationTime = Date().timeIntervalSince(startTime)
        
        // Query performance
        let queryStart = Date()
        let activeCount = await ndk.subscriptionTracker.activeSubscriptionCount()
        let allSubs = await ndk.subscriptionTracker.getAllActiveSubscriptions()
        let stats = await ndk.subscriptionTracker.getStatistics()
        let queryTime = Date().timeIntervalSince(queryStart)
        
        // Verify correctness
        XCTAssertEqual(activeCount, subscriptionCount)
        XCTAssertEqual(allSubs.count, subscriptionCount)
        XCTAssertEqual(stats.activeSubscriptions, subscriptionCount)
        
        // Performance assertions
        XCTAssertLessThan(creationTime, 5.0, "Creating \(subscriptionCount) subscriptions took too long")
        XCTAssertLessThan(queryTime, 0.1, "Querying tracker took too long")
        
        // Close all
        let closeStart = Date()
        for sub in subscriptions {
            sub.close()
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let closeTime = Date().timeIntervalSince(closeStart)
        
        XCTAssertLessThan(closeTime, 5.0, "Closing \(subscriptionCount) subscriptions took too long")
    }
}

// MARK: - Mock Relay for Testing

private class MockRelay: NDKRelay {
    var isConnectedMock: Bool = true
    
    override var isConnected: Bool {
        return isConnectedMock
    }
    
    override func connect() async throws {
        isConnectedMock = true
    }
    
    override func disconnect() async {
        isConnectedMock = false
    }
    
    override func send(_ message: String) async throws {
        // Mock implementation
    }
}