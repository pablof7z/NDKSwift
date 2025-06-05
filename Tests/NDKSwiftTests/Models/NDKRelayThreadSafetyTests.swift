import XCTest
@testable import NDKSwift

final class NDKRelayThreadSafetyTests: XCTestCase {
    
    func testConcurrentSubscriptionAdditionDoesNotCrash() async throws {
        // Create a relay
        let relay = NDKRelay(url: "wss://relay.damus.io")
        
        // Create multiple subscriptions
        let subscriptionCount = 100
        var subscriptions: [NDKSubscription] = []
        
        for i in 0..<subscriptionCount {
            let filter = NDKFilter(
                authors: ["test_author_\(i)"],
                kinds: [0],
                limit: 1
            )
            let subscription = NDKSubscription(
                id: "test_subscription_\(i)",
                filters: [filter]
            )
            subscriptions.append(subscription)
        }
        
        // Add subscriptions concurrently from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for subscription in subscriptions {
                group.addTask {
                    // Add subscription multiple times to increase chance of race condition
                    for _ in 0..<10 {
                        relay.addSubscription(subscription)
                        // Small delay to allow interleaving
                        try? await Task.sleep(nanoseconds: 1_000)
                    }
                }
            }
            
            // Also remove subscriptions concurrently
            for subscription in subscriptions {
                group.addTask {
                    for _ in 0..<5 {
                        relay.removeSubscription(subscription)
                        try? await Task.sleep(nanoseconds: 1_000)
                    }
                }
            }
            
            // And read active subscriptions concurrently
            for _ in 0..<50 {
                group.addTask {
                    _ = relay.activeSubscriptions
                    try? await Task.sleep(nanoseconds: 1_000)
                }
            }
        }
        
        // Verify we can still access subscriptions without crash
        let activeSubscriptions = relay.activeSubscriptions
        XCTAssertNotNil(activeSubscriptions)
    }
    
    func testSubscriptionIDIsString() {
        // This test verifies that subscription IDs are properly typed as String
        let filter = NDKFilter(authors: ["test"], kinds: [0])
        let subscription = NDKSubscription(filters: [filter])
        
        // Verify the ID is a String and can be used as dictionary key
        let testDict: [String: Any] = [subscription.id: subscription]
        XCTAssertNotNil(testDict[subscription.id])
        
        // Verify the ID is not empty
        XCTAssertFalse(subscription.id.isEmpty)
        
        // Verify we can create multiple subscriptions with unique IDs
        let subscription2 = NDKSubscription(filters: [filter])
        XCTAssertNotEqual(subscription.id, subscription2.id)
    }
    
    func testRelaySubscriptionManagement() async throws {
        let relay = NDKRelay(url: "wss://relay.test.com")
        
        // Create a subscription with metadata filter
        let filter = NDKFilter(
            authors: ["9c5d04b8769ef8ee686ae5e64c5d2a498c6a5a2e2a4966e0a6782c1e6c084e47"],
            kinds: [0],
            limit: 1
        )
        
        let subscription = NDKSubscription(
            id: "metadata_subscription_test",
            filters: [filter]
        )
        
        // Add subscription
        relay.addSubscription(subscription)
        
        // Verify it was added
        let activeSubscriptions = relay.activeSubscriptions
        XCTAssertEqual(activeSubscriptions.count, 1)
        XCTAssertEqual(activeSubscriptions.first?.id, subscription.id)
        
        // Remove subscription
        relay.removeSubscription(subscription)
        
        // Verify it was removed
        let activeSubscriptionsAfterRemoval = relay.activeSubscriptions
        XCTAssertEqual(activeSubscriptionsAfterRemoval.count, 0)
    }
}