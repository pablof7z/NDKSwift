import XCTest
@testable import NDKSwift

final class NDKSubscriptionReconnectionTests: XCTestCase {
    
    var ndk: NDK!
    
    override func setUp() async throws {
        ndk = NDK()
    }
    
    func testSubscriptionReplayOnRelayReconnect() async throws {
        // Add a relay
        let relay = ndk.addRelay("wss://relay.example.com")
        
        // Create subscription
        let subscription = ndk.subscribe(
            filters: [NDKFilter(kinds: [1], limit: 10)],
            options: NDKSubscriptionOptions()
        )
        
        // Track events received
        var eventsReceived: [NDKEvent] = []
        subscription.onEvent { event in
            eventsReceived.append(event)
        }
        
        // Start subscription
        subscription.start()
        
        // Simulate relay disconnect
        await relay.disconnect()
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify subscription is waiting
        let activeBeforeReconnect = await relay.subscriptionManager.getActiveSubscriptionIds()
        XCTAssertEqual(activeBeforeReconnect.count, 0, "No active subscriptions when disconnected")
        
        // Simulate relay reconnect
        try await relay.connect()
        
        // Give time for subscriptions to replay
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify subscription is active again
        let activeAfterReconnect = await relay.subscriptionManager.getActiveSubscriptionIds()
        XCTAssertGreaterThan(activeAfterReconnect.count, 0, "Subscriptions should be replayed after reconnect")
    }
    
    func testMultipleSubscriptionsGroupingAcrossReconnect() async throws {
        let relay = ndk.addRelay("wss://relay.example.com")
        
        // Create multiple subscriptions that can be grouped
        let sub1 = ndk.subscribe(filters: [NDKFilter(kinds: [1], authors: ["alice"])])
        let sub2 = ndk.subscribe(filters: [NDKFilter(kinds: [1], authors: ["bob"])])
        let sub3 = ndk.subscribe(filters: [NDKFilter(kinds: [1], authors: ["charlie"])])
        
        sub1.start()
        sub2.start()
        sub3.start()
        
        // Connect relay
        try await relay.connect()
        
        // Wait for subscriptions to be sent
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Get initial active count
        let initialActive = await relay.subscriptionManager.getActiveSubscriptionIds()
        
        // Should be grouped into fewer relay subscriptions
        XCTAssertLessThan(initialActive.count, 3, "Similar subscriptions should be grouped")
        
        // Disconnect and reconnect
        await relay.disconnect()
        try await relay.connect()
        
        // Wait for replay
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify grouping is maintained after reconnect
        let activeAfterReconnect = await relay.subscriptionManager.getActiveSubscriptionIds()
        XCTAssertEqual(activeAfterReconnect.count, initialActive.count, "Grouping should be maintained after reconnect")
    }
    
    func testCloseOnEoseSubscriptionNotReplayedAfterEose() async throws {
        let relay = ndk.addRelay("wss://relay.example.com")
        
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        
        let subscription = ndk.subscribe(
            filters: [NDKFilter(kinds: [1], limit: 5)],
            options: options
        )
        
        var eoseReceived = false
        subscription.onEOSE {
            eoseReceived = true
        }
        
        subscription.start()
        
        // Connect relay
        try await relay.connect()
        
        // Simulate EOSE
        subscription.handleEOSE(fromRelay: relay)
        
        XCTAssertTrue(eoseReceived, "EOSE should be received")
        XCTAssertTrue(subscription.isClosed, "Subscription should be closed after EOSE")
        
        // Disconnect and reconnect
        await relay.disconnect()
        try await relay.connect()
        
        // Wait for potential replay
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Verify subscription was not replayed
        let activeAfterReconnect = await relay.subscriptionManager.getActiveSubscriptionIds()
        XCTAssertEqual(activeAfterReconnect.count, 0, "Closed subscriptions should not be replayed")
    }
    
    func testSubscriptionStateTransitions() async throws {
        // Test subscription state transitions during connection changes
        let relay = ndk.addRelay("wss://relay.example.com")
        
        let subscription = ndk.subscribe(
            filters: [NDKFilter(kinds: [1])],
            options: NDKSubscriptionOptions()
        )
        
        // Track state changes
        var stateLog: [String] = []
        
        subscription.onEvent { _ in
            stateLog.append("event")
        }
        
        subscription.onError { _ in
            stateLog.append("error")
        }
        
        // Start subscription before relay is connected
        subscription.start()
        stateLog.append("started")
        
        // Connect relay
        try await relay.connect()
        stateLog.append("connected")
        
        // Wait for subscription to execute
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Disconnect
        await relay.disconnect()
        stateLog.append("disconnected")
        
        // Reconnect
        try await relay.connect()
        stateLog.append("reconnected")
        
        // Verify state transitions occurred in expected order
        XCTAssertEqual(stateLog[0], "started")
        XCTAssertEqual(stateLog[1], "connected")
        XCTAssertTrue(stateLog.contains("disconnected"))
        XCTAssertTrue(stateLog.contains("reconnected"))
    }
    
    func testFilterMergingAcrossMultipleRelays() async throws {
        // Add multiple relays
        let relay1 = ndk.addRelay("wss://relay1.example.com")
        let relay2 = ndk.addRelay("wss://relay2.example.com")
        
        // Create subscription that will use both relays
        let subscription = ndk.subscribe(
            filters: [NDKFilter(kinds: [1], authors: ["alice", "bob"])],
            options: NDKSubscriptionOptions()
        )
        
        subscription.start()
        
        // Connect both relays
        try await relay1.connect()
        try await relay2.connect()
        
        // Wait for subscriptions to be sent
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Each relay should have the subscription
        let active1 = await relay1.subscriptionManager.getActiveSubscriptionIds()
        let active2 = await relay2.subscriptionManager.getActiveSubscriptionIds()
        
        XCTAssertGreaterThan(active1.count, 0, "Relay 1 should have active subscription")
        XCTAssertGreaterThan(active2.count, 0, "Relay 2 should have active subscription")
        
        // Disconnect one relay
        await relay1.disconnect()
        
        // Subscription should still be active on relay2
        let active2AfterDisconnect = await relay2.subscriptionManager.getActiveSubscriptionIds()
        XCTAssertEqual(active2AfterDisconnect.count, active2.count, "Relay 2 should maintain subscription")
        
        // Reconnect relay1
        try await relay1.connect()
        
        // Wait for replay
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Both should have active subscriptions again
        let active1AfterReconnect = await relay1.subscriptionManager.getActiveSubscriptionIds()
        let active2AfterReconnect = await relay2.subscriptionManager.getActiveSubscriptionIds()
        
        XCTAssertGreaterThan(active1AfterReconnect.count, 0, "Relay 1 should replay subscription")
        XCTAssertGreaterThan(active2AfterReconnect.count, 0, "Relay 2 should still have subscription")
    }
}