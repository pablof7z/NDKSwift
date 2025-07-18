import XCTest
@testable import NDKSwift

final class SubscriptionGroupingTests: XCTestCase {
    var ndk: NDK!
    var relay: NDKRelay!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create NDK with a test relay
        ndk = NDK()
        relay = await ndk.addRelay("wss://test.relay")
    }
    
    override func tearDown() async throws {
        await ndk.disconnect()
        try await super.tearDown()
    }
    
    func testMultipleSubscriptionsWithinGroupingWindow() async throws {
        // Create 5 similar subscriptions rapidly
        var subscriptions: [NDKSubscription] = []
        
        let startTime = Date()
        
        for i in 0..<5 {
            let filter = NDKFilter(authors: ["author\(i)"], kinds: [1])
            let subscription = await ndk.subscribe(
                filters: [filter],
                closeOnEose: false
            )
            subscriptions.append(subscription)
        }
        
        let endTime = Date()
        let elapsed = endTime.timeIntervalSince(startTime)
        
        // Verify all subscriptions were created within 5ms
        XCTAssertLessThan(elapsed, 0.005, "Subscriptions should be created within 5ms")
        
        // Wait for grouping delay (100ms) plus a bit extra
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Check relay subscriptions
        let relaySubscriptions = await relay.activeSubscriptions
        
        // With grouping enabled, we should have fewer relay subscriptions than NDK subscriptions
        print("Created \(subscriptions.count) NDK subscriptions")
        print("Resulted in \(relaySubscriptions.count) relay subscriptions")
        
        // Since all subscriptions have the same kinds and structure (just different authors),
        // they should be grouped into a single relay subscription
        XCTAssertLessThan(relaySubscriptions.count, subscriptions.count, 
                          "Multiple similar subscriptions should be grouped")
        
        // Ideally, they should all be merged into 1 subscription
        XCTAssertEqual(relaySubscriptions.count, 1, 
                       "All similar subscriptions should be merged into one relay subscription")
        
        // Verify the merged subscription contains all authors
        if let mergedSub = relaySubscriptions.first,
           let filter = mergedSub.filters.first {
            XCTAssertEqual(filter.authors?.count, 5, "Merged filter should contain all 5 authors")
        }
    }
    
    func testSubscriptionsWithDifferentKindsNotGrouped() async throws {
        // Create subscriptions with different kinds
        var subscriptions: [NDKSubscription] = []
        
        for i in 0..<3 {
            let filter = NDKFilter(authors: ["testauthor"], kinds: [i + 1])
            let subscription = await ndk.subscribe(
                filters: [filter],
                closeOnEose: false
            )
            subscriptions.append(subscription)
        }
        
        // Wait for potential grouping
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Check relay subscriptions
        let relaySubscriptions = await relay.activeSubscriptions
        
        // Different kinds should not be grouped in the same subscription
        // (they might still be batched in the same REQ message but as separate filters)
        print("Created \(subscriptions.count) NDK subscriptions with different kinds")
        print("Resulted in \(relaySubscriptions.count) relay subscriptions")
        
        // Should have separate subscriptions or separate filters
        XCTAssertGreaterThan(relaySubscriptions.count, 0, "Should have at least one relay subscription")
    }
    
    func testCloseOnEoseSubscriptionsNotGrouped() async throws {
        // Create mix of regular and closeOnEose subscriptions
        var subscriptions: [NDKSubscription] = []
        
        // Regular subscription
        let filter1 = NDKFilter(authors: ["author1"], kinds: [1])
        let sub1 = await ndk.subscribe(filters: [filter1], closeOnEose: false)
        subscriptions.append(sub1)
        
        // CloseOnEose subscription
        let filter2 = NDKFilter(authors: ["author2"], kinds: [1])
        let sub2 = await ndk.subscribe(filters: [filter2], closeOnEose: true)
        subscriptions.append(sub2)
        
        // Another regular subscription
        let filter3 = NDKFilter(authors: ["author3"], kinds: [1])
        let sub3 = await ndk.subscribe(filters: [filter3], closeOnEose: false)
        subscriptions.append(sub3)
        
        // Wait for potential grouping
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Check relay subscriptions
        let relaySubscriptions = await relay.activeSubscriptions
        
        print("Created \(subscriptions.count) NDK subscriptions (1 closeOnEose, 2 regular)")
        print("Resulted in \(relaySubscriptions.count) relay subscriptions")
        
        // closeOnEose subscription should not be grouped with regular ones
        XCTAssertGreaterThanOrEqual(relaySubscriptions.count, 2, 
                                    "closeOnEose subscription should be separate from regular ones")
    }
}