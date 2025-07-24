import XCTest
@testable import NDKSwift

final class RelayUpdateNotifierTests: XCTestCase {
    
    func testRelayUpdateNotification() async throws {
        // Create NDK instance
        let ndk = NDK()
        
        // Create a filter with unknown authors
        let unknownAuthors = Set(["author1", "author2", "author3"])
        let filter = NDKFilter(
            authors: Array(unknownAuthors),
            kinds: [1]
        )
        
        // Register subscription for updates
        let subscriptionId = "test_subscription"
        await ndk.outbox.registerSubscriptionForUpdates(
            id: subscriptionId,
            filter: filter,
            unknownAuthors: unknownAuthors
        )
        
        // Set up listener for relay updates
        var receivedUpdates: [RelayUpdateEvent] = []
        let updateTask = Task {
            for await update in await ndk.outbox.relayUpdates {
                receivedUpdates.append(update)
            }
        }
        
        // Wait a moment for listener to start
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Simulate relay discovery for author1
        let relayInfo = RelayDiscoveryInfo(
            readRelays: ["wss://relay1.com", "wss://relay2.com"],
            writeRelays: ["wss://relay3.com"]
        )
        
        // Trigger the relay discovery notification
        await ndk.outbox.processRelayListEvent(
            NDKEvent(
                id: "test_event",
                pubkey: "author1",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.relayList,
                tags: [
                    ["r", "wss://relay1.com", "read"],
                    ["r", "wss://relay2.com", "read"],
                    ["r", "wss://relay3.com", "write"]
                ],
                content: "",
                sig: "test_sig"
            )
        )
        
        // Wait for update to be processed
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Cancel update listener
        updateTask.cancel()
        
        // Verify we received the update
        XCTAssertEqual(receivedUpdates.count, 1, "Should receive one relay update")
        if let update = receivedUpdates.first {
            XCTAssertEqual(update.pubkey, "author1")
            XCTAssertEqual(update.relays.readRelays.count, 2)
            XCTAssertEqual(update.relays.writeRelays.count, 1)
            XCTAssertTrue(update.affectedSubscriptionIds.contains(subscriptionId))
        }
        
        // Check stats
        let stats = await ndk.outbox.getRelayUpdateStats()
        XCTAssertEqual(stats.activeSubscriptions, 1)
        XCTAssertEqual(stats.totalUnknownAuthors, 2) // author2 and author3 still unknown
        XCTAssertGreaterThanOrEqual(stats.totalUpdateSubscriptions, 1) // At least one update subscription created
    }
    
    func testMultipleSubscriptionUpdates() async throws {
        let ndk = NDK()
        
        // Create two subscriptions with overlapping authors
        let subscription1Id = "sub1"
        let subscription2Id = "sub2"
        
        let filter1 = NDKFilter(authors: ["author1", "author2"], kinds: [1])
        let filter2 = NDKFilter(authors: ["author2", "author3"], kinds: [1])
        
        await ndk.outbox.registerSubscriptionForUpdates(
            id: subscription1Id,
            filter: filter1,
            unknownAuthors: Set(["author1", "author2"])
        )
        
        await ndk.outbox.registerSubscriptionForUpdates(
            id: subscription2Id,
            filter: filter2,
            unknownAuthors: Set(["author2", "author3"])
        )
        
        // Collect updates
        var updates: [RelayUpdateEvent] = []
        let updateTask = Task {
            for await update in await ndk.outbox.relayUpdates {
                updates.append(update)
            }
        }
        
        // Wait for listener
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        // Discover relays for author2 (affects both subscriptions)
        await ndk.outbox.processRelayListEvent(
            NDKEvent(
                id: "test_event",
                pubkey: "author2",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.relayList,
                tags: [["r", "wss://relay.author2.com", ""]],
                content: "",
                sig: "test_sig"
            )
        )
        
        // Wait for processing
        try? await Task.sleep(nanoseconds: 100_000_000)
        updateTask.cancel()
        
        // Verify both subscriptions were notified
        XCTAssertEqual(updates.count, 1)
        if let update = updates.first {
            XCTAssertEqual(update.pubkey, "author2")
            XCTAssertEqual(update.affectedSubscriptionIds.count, 2)
            XCTAssertTrue(update.affectedSubscriptionIds.contains(subscription1Id))
            XCTAssertTrue(update.affectedSubscriptionIds.contains(subscription2Id))
        }
    }
    
    func testUnregisterSubscription() async throws {
        let ndk = NDK()
        
        let subscriptionId = "test_sub"
        let filter = NDKFilter(authors: ["author1"], kinds: [1])
        
        // Register and then unregister
        await ndk.outbox.registerSubscriptionForUpdates(
            id: subscriptionId,
            filter: filter,
            unknownAuthors: Set(["author1"])
        )
        
        var initialStats = await ndk.outbox.getRelayUpdateStats()
        XCTAssertEqual(initialStats.activeSubscriptions, 1)
        
        await ndk.outbox.unregisterSubscriptionFromUpdates(id: subscriptionId)
        
        let finalStats = await ndk.outbox.getRelayUpdateStats()
        XCTAssertEqual(finalStats.activeSubscriptions, 0)
        
        // Verify no updates are received after unregistering
        var receivedUpdate = false
        let updateTask = Task {
            for await _ in await ndk.outbox.relayUpdates {
                receivedUpdate = true
            }
        }
        
        // Wait for listener
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        // Trigger relay discovery
        await ndk.outbox.processRelayListEvent(
            NDKEvent(
                id: "test_event",
                pubkey: "author1",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: EventKind.relayList,
                tags: [["r", "wss://relay.test", ""]],
                content: "",
                sig: "test_sig"
            )
        )
        
        // Wait briefly
        try? await Task.sleep(nanoseconds: 50_000_000)
        updateTask.cancel()
        
        XCTAssertFalse(receivedUpdate, "Should not receive updates for unregistered subscription")
    }
}