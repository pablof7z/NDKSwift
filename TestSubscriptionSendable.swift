#!/usr/bin/env swift

import Foundation
@testable import NDKSwift

// Test that NDKSubscription is properly Sendable
func testSubscriptionSendable() async {
    print("Testing NDKSubscription Sendable conformance...")
    
    // Create a subscription
    let filter = NDKFilter()
    filter.kinds = [1]
    filter.limit = 10
    
    let options = NDKSubscriptionOptions()
    let subscription = NDKSubscription(
        id: "test-sub",
        filters: [filter],
        options: options,
        ndk: nil
    )
    
    // Test that we can access properties asynchronously
    print("Subscription ID: \(subscription.id)")
    print("Is Active: \(await subscription.isActive)")
    print("Is Closed: \(await subscription.isClosed)")
    print("State: \(await subscription.state)")
    
    // Test that we can pass subscription across actor boundaries
    actor TestActor {
        func processSubscription(_ subscription: NDKSubscription) async {
            print("Processing subscription in actor...")
            print("  - ID: \(subscription.id)")
            print("  - State: \(await subscription.state)")
            print("  - Options closeOnEose: \(await subscription.options.closeOnEose)")
        }
    }
    
    let testActor = TestActor()
    await testActor.processSubscription(subscription)
    
    // Test concurrent access
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<5 {
            group.addTask {
                print("Task \(i) - State: \(await subscription.state)")
            }
        }
    }
    
    print("\n✅ NDKSubscription is properly Sendable!")
}

// Run the test
await testSubscriptionSendable()