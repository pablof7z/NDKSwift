import XCTest
@testable import NDKSwift

final class NDKSubscriptionTrackerTests: XCTestCase {
    var tracker: NDKSubscriptionTracker!
    
    override func setUp() async throws {
        tracker = NDKSubscriptionTracker(
            trackClosedSubscriptions: true,
            maxClosedSubscriptions: 10
        )
    }
    
    // MARK: - Subscription Lifecycle Tests
    
    func testTrackSubscription() async throws {
        // Create test subscription
        let subscription = createTestSubscription()
        let filter = NDKFilter(kinds: [1])
        let relayUrls = ["wss://relay1.example.com", "wss://relay2.example.com"]
        
        // Track subscription
        await tracker.trackSubscription(subscription, filter: filter, relayUrls: relayUrls)
        
        // Verify tracking
        let count = await tracker.activeSubscriptionCount()
        XCTAssertEqual(count, 1)
        
        let detail = await tracker.getSubscriptionDetail(subscription.id)
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.subscriptionId, subscription.id)
        XCTAssertEqual(detail?.originalFilter, filter)
    }
    
    func testTrackSubscriptionSentToRelay() async throws {
        // Setup
        let subscription = createTestSubscription()
        let filter = NDKFilter(kinds: [1])
        await tracker.trackSubscription(subscription, filter: filter, relayUrls: ["wss://relay1.example.com"])
        
        let appliedFilter = NDKFilter(kinds: [1], limit: 100)
        
        // Track subscription sent to relay
        await tracker.trackSubscriptionSentToRelay(
            subscriptionId: subscription.id,
            relayUrl: "wss://relay1.example.com",
            appliedFilter: appliedFilter
        )
        
        // Verify
        let relayMetrics = await tracker.getRelayMetrics(
            subscriptionId: subscription.id,
            relayUrl: "wss://relay1.example.com"
        )
        XCTAssertNotNil(relayMetrics)
        XCTAssertEqual(relayMetrics?.appliedFilter, appliedFilter)
        XCTAssertEqual(relayMetrics?.eventsReceived, 0)
    }
    
    func testTrackEventReceived() async throws {
        // Setup
        let subscription = createTestSubscription()
        let filter = NDKFilter(kinds: [1])
        let relayUrl = "wss://relay1.example.com"
        
        await tracker.trackSubscription(subscription, filter: filter, relayUrls: [relayUrl])
        await tracker.trackSubscriptionSentToRelay(
            subscriptionId: subscription.id,
            relayUrl: relayUrl,
            appliedFilter: filter
        )
        
        // Track events
        await tracker.trackEventReceived(
            subscriptionId: subscription.id,
            eventId: "event1",
            relayUrl: relayUrl,
            isUnique: true
        )
        
        await tracker.trackEventReceived(
            subscriptionId: subscription.id,
            eventId: "event2",
            relayUrl: relayUrl,
            isUnique: true
        )
        
        await tracker.trackEventReceived(
            subscriptionId: subscription.id,
            eventId: "event1",
            relayUrl: relayUrl,
            isUnique: false // Duplicate
        )
        
        // Verify metrics
        let detail = await tracker.getSubscriptionDetail(subscription.id)
        XCTAssertEqual(detail?.metrics.totalUniqueEvents, 2)
        XCTAssertEqual(detail?.metrics.totalEvents, 3)
        
        let relayMetrics = await tracker.getRelayMetrics(
            subscriptionId: subscription.id,
            relayUrl: relayUrl
        )
        XCTAssertEqual(relayMetrics?.eventsReceived, 3)
    }
    
    func testTrackEoseReceived() async throws {
        // Setup
        let subscription = createTestSubscription()
        let filter = NDKFilter(kinds: [1])
        let relayUrl = "wss://relay1.example.com"
        
        await tracker.trackSubscription(subscription, filter: filter, relayUrls: [relayUrl])
        await tracker.trackSubscriptionSentToRelay(
            subscriptionId: subscription.id,
            relayUrl: relayUrl,
            appliedFilter: filter
        )
        
        // Track EOSE
        await tracker.trackEoseReceived(
            subscriptionId: subscription.id,
            relayUrl: relayUrl
        )
        
        // Verify
        let relayMetrics = await tracker.getRelayMetrics(
            subscriptionId: subscription.id,
            relayUrl: relayUrl
        )
        XCTAssertTrue(relayMetrics?.eoseReceived ?? false)
        XCTAssertNotNil(relayMetrics?.eoseTime)
        XCTAssertNotNil(relayMetrics?.timeToEose)
    }
    
    func testCloseSubscription() async throws {
        // Setup
        let subscription = createTestSubscription()
        let filter = NDKFilter(kinds: [1])
        
        await tracker.trackSubscription(subscription, filter: filter, relayUrls: ["wss://relay1.example.com"])
        
        // Close subscription
        await tracker.closeSubscription(subscription.id)
        
        // Verify
        let activeCount = await tracker.activeSubscriptionCount()
        XCTAssertEqual(activeCount, 0)
        
        let detail = await tracker.getSubscriptionDetail(subscription.id)
        XCTAssertNil(detail)
        
        // Check closed history
        let closedSubs = await tracker.getClosedSubscriptions()
        XCTAssertEqual(closedSubs.count, 1)
        XCTAssertEqual(closedSubs.first?.subscriptionId, subscription.id)
    }
    
    // MARK: - Query Method Tests
    
    func testGetAllActiveSubscriptions() async throws {
        // Create multiple subscriptions
        let sub1 = createTestSubscription(id: "sub1")
        let sub2 = createTestSubscription(id: "sub2")
        let sub3 = createTestSubscription(id: "sub3")
        
        await tracker.trackSubscription(sub1, filter: NDKFilter(kinds: [1]), relayUrls: ["wss://relay1.example.com"])
        await tracker.trackSubscription(sub2, filter: NDKFilter(kinds: [2]), relayUrls: ["wss://relay2.example.com"])
        await tracker.trackSubscription(sub3, filter: NDKFilter(kinds: [3]), relayUrls: ["wss://relay3.example.com"])
        
        // Get all active
        let active = await tracker.getAllActiveSubscriptions()
        XCTAssertEqual(active.count, 3)
        
        // Close one
        await tracker.closeSubscription("sub2")
        
        let activeAfterClose = await tracker.getAllActiveSubscriptions()
        XCTAssertEqual(activeAfterClose.count, 2)
    }
    
    func testGetStatistics() async throws {
        // Create subscriptions
        let sub1 = createTestSubscription(id: "sub1")
        let sub2 = createTestSubscription(id: "sub2")
        
        await tracker.trackSubscription(sub1, filter: NDKFilter(kinds: [1]), relayUrls: ["wss://relay1.example.com"])
        await tracker.trackSubscription(sub2, filter: NDKFilter(kinds: [2]), relayUrls: ["wss://relay2.example.com"])
        
        // Add events
        await tracker.trackEventReceived(subscriptionId: "sub1", eventId: "e1", relayUrl: "wss://relay1.example.com", isUnique: true)
        await tracker.trackEventReceived(subscriptionId: "sub1", eventId: "e2", relayUrl: "wss://relay1.example.com", isUnique: true)
        await tracker.trackEventReceived(subscriptionId: "sub2", eventId: "e3", relayUrl: "wss://relay2.example.com", isUnique: true)
        
        // Close one subscription
        await tracker.closeSubscription("sub2")
        
        // Get statistics
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.activeSubscriptions, 1)
        XCTAssertEqual(stats.totalSubscriptions, 2)
        XCTAssertEqual(stats.totalUniqueEvents, 3)
        XCTAssertEqual(stats.closedSubscriptionsTracked, 1)
        XCTAssertGreaterThan(stats.averageEventsPerSubscription, 0)
    }
    
    // MARK: - Closed Subscription History Tests
    
    func testClosedSubscriptionHistory() async throws {
        // Create tracker with small history
        let historyTracker = NDKSubscriptionTracker(
            trackClosedSubscriptions: true,
            maxClosedSubscriptions: 3
        )
        
        // Create and close multiple subscriptions
        for i in 1...5 {
            let sub = createTestSubscription(id: "sub\(i)")
            await historyTracker.trackSubscription(sub, filter: NDKFilter(kinds: [1]), relayUrls: ["wss://relay.example.com"])
            await historyTracker.trackEventReceived(subscriptionId: sub.id, eventId: "event\(i)", relayUrl: "wss://relay.example.com", isUnique: true)
            await historyTracker.closeSubscription(sub.id)
        }
        
        // Verify only last 3 are kept
        let closedSubs = await historyTracker.getClosedSubscriptions()
        XCTAssertEqual(closedSubs.count, 3)
        XCTAssertEqual(closedSubs.map { $0.subscriptionId }, ["sub3", "sub4", "sub5"])
    }
    
    func testNoClosedSubscriptionTracking() async throws {
        // Create tracker without history
        let noHistoryTracker = NDKSubscriptionTracker(
            trackClosedSubscriptions: false,
            maxClosedSubscriptions: 100
        )
        
        // Create and close subscription
        let sub = createTestSubscription()
        await noHistoryTracker.trackSubscription(sub, filter: NDKFilter(kinds: [1]), relayUrls: ["wss://relay.example.com"])
        await noHistoryTracker.closeSubscription(sub.id)
        
        // Verify no history kept
        let closedSubs = await noHistoryTracker.getClosedSubscriptions()
        XCTAssertEqual(closedSubs.count, 0)
    }
    
    // MARK: - Export Tests
    
    func testExportTrackingData() async throws {
        // Setup data
        let sub = createTestSubscription()
        await tracker.trackSubscription(sub, filter: NDKFilter(kinds: [1]), relayUrls: ["wss://relay.example.com"])
        await tracker.trackEventReceived(subscriptionId: sub.id, eventId: "e1", relayUrl: "wss://relay.example.com", isUnique: true)
        await tracker.trackEoseReceived(subscriptionId: sub.id, relayUrl: "wss://relay.example.com")
        
        // Export
        let data = await tracker.exportTrackingData()
        
        // Verify structure
        XCTAssertNotNil(data["activeSubscriptions"])
        XCTAssertNotNil(data["closedSubscriptions"])
        XCTAssertNotNil(data["statistics"])
        
        // Verify content
        if let activeSubs = data["activeSubscriptions"] as? [[String: Any]] {
            XCTAssertEqual(activeSubs.count, 1)
            XCTAssertEqual(activeSubs.first?["subscriptionId"] as? String, sub.id)
        }
        
        if let stats = data["statistics"] as? [String: Any] {
            XCTAssertEqual(stats["activeSubscriptions"] as? Int, 1)
            XCTAssertEqual(stats["totalUniqueEvents"] as? Int, 1)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestSubscription(id: String = UUID().uuidString) -> NDKSubscription {
        let filters = [NDKFilter(kinds: [1])]
        let options = NDKSubscriptionOptions()
        let ndk = NDK()
        return NDKSubscription(filters: filters, options: options, ndk: ndk, id: id)
    }
}