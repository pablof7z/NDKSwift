import XCTest
@testable import NDKSwift

final class FallbackRelaySubscriptionTests: XCTestCase {
    private var ndk: NDK!
    private var pool: NDKPool!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create NDK with outbox disabled for these tests
        pool = NDKPool()
        ndk = NDK(pool: pool, enableOutbox: false)
    }
    
    override func tearDown() async throws {
        await ndk.close()
        try await super.tearDown()
    }
    
    func testSubscriptionUsesFallbackRelaysWhenNoneSpecified() async throws {
        // Add explicit/fallback relays to the pool (but don't connect them yet)
        let relay1URL = "wss://relay1.fallback.example"
        let relay2URL = "wss://relay2.fallback.example"
        
        await pool.addRelayAndConnect(url: relay1URL, origin: .explicit)
        await pool.addRelayAndConnect(url: relay2URL, origin: .explicit)
        
        // Give relays a moment to be added (but not necessarily connected)
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Create a subscription WITHOUT specifying relays
        let filter = NDKFilter(kinds: [1], limit: 10)
        let dataSource = ndk.observe(filter: filter, cachePolicy: .networkOnly)
        
        // Start collecting events
        let task = Task {
            var events: [NDKEvent] = []
            for await event in dataSource {
                events.append(event)
            }
            return events
        }
        
        // Give the subscription time to be established
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify the subscription was created for both fallback relays
        let internalManager = ndk.internalSubscriptionManager
        let relay1Subs = await internalManager.getSubscriptionsForRelay(relay1URL)
        let relay2Subs = await internalManager.getSubscriptionsForRelay(relay2URL)
        
        XCTAssertFalse(relay1Subs.isEmpty, "Subscription should be associated with fallback relay 1")
        XCTAssertFalse(relay2Subs.isEmpty, "Subscription should be associated with fallback relay 2")
        
        // Cancel the subscription
        task.cancel()
        _ = await task.result
    }
    
    func testSubscriptionWithNoFallbackRelaysShowsWarning() async throws {
        // Don't add any relays to the pool
        
        // Capture logs
        var capturedLogs: [String] = []
        let originalLogger = NDKLogger.logHandler
        NDKLogger.logHandler = { level, category, message in
            capturedLogs.append(message)
            originalLogger(level, category, message)
        }
        defer {
            NDKLogger.logHandler = originalLogger
        }
        
        // Create a subscription WITHOUT any relays configured
        let filter = NDKFilter(kinds: [1], limit: 10)
        let dataSource = ndk.observe(filter: filter, cachePolicy: .networkOnly)
        
        // Start collecting events
        let task = Task {
            var events: [NDKEvent] = []
            for await event in dataSource {
                events.append(event)
            }
            return events
        }
        
        // Give the subscription time to be established
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify warning was logged
        let warningLogged = capturedLogs.contains { log in
            log.contains("No relays specified and no explicit/fallback relays configured")
        }
        XCTAssertTrue(warningLogged, "Should log warning when no fallback relays are configured")
        
        // Cancel the subscription
        task.cancel()
        _ = await task.result
    }
    
    func testSubscriptionReplayWhenFallbackRelaysConnectLater() async throws {
        // Add explicit/fallback relays to the pool
        let relay1URL = "wss://relay1.delayed.example"
        let relay2URL = "wss://relay2.delayed.example"
        
        // Add relays but prevent immediate connection
        let relay1 = await pool.addRelay(url: relay1URL, origin: .explicit)
        let relay2 = await pool.addRelay(url: relay2URL, origin: .explicit)
        
        // Ensure relays are not connected yet
        let relay1State = await relay1?.connectionState
        let relay2State = await relay2?.connectionState
        XCTAssertNotEqual(relay1State, .connected, "Relay 1 should not be connected yet")
        XCTAssertNotEqual(relay2State, .connected, "Relay 2 should not be connected yet")
        
        // Create a subscription (should use fallback relay URLs even though not connected)
        let filter = NDKFilter(kinds: [1], limit: 10)
        let dataSource = ndk.observe(filter: filter, cachePolicy: .networkOnly)
        
        // Start collecting events
        let task = Task {
            var events: [NDKEvent] = []
            for await event in dataSource {
                events.append(event)
            }
            return events
        }
        
        // Give the subscription time to be established
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify the subscription was created for both fallback relays (even though not connected)
        let internalManager = ndk.internalSubscriptionManager
        let relay1SubsBefore = await internalManager.getSubscriptionsForRelay(relay1URL)
        let relay2SubsBefore = await internalManager.getSubscriptionsForRelay(relay2URL)
        
        XCTAssertFalse(relay1SubsBefore.isEmpty, "Subscription should be associated with relay 1 even before connection")
        XCTAssertFalse(relay2SubsBefore.isEmpty, "Subscription should be associated with relay 2 even before connection")
        
        // Now connect the relays
        await relay1?.connect()
        await relay2?.connect()
        
        // Give time for connection and subscription replay
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        
        // Verify relays are now connected
        let relay1StateAfter = await relay1?.connectionState
        let relay2StateAfter = await relay2?.connectionState
        XCTAssertEqual(relay1StateAfter, .connected, "Relay 1 should be connected now")
        XCTAssertEqual(relay2StateAfter, .connected, "Relay 2 should be connected now")
        
        // Verify subscriptions are still active (should have been replayed on connection)
        let relay1SubsAfter = await internalManager.getSubscriptionsForRelay(relay1URL)
        let relay2SubsAfter = await internalManager.getSubscriptionsForRelay(relay2URL)
        
        XCTAssertFalse(relay1SubsAfter.isEmpty, "Subscription should still be active on relay 1 after connection")
        XCTAssertFalse(relay2SubsAfter.isEmpty, "Subscription should still be active on relay 2 after connection")
        
        // Cancel the subscription
        task.cancel()
        _ = await task.result
    }
    
    func testExplicitRelaysOverrideFallbackRelays() async throws {
        // Add fallback relays to the pool
        let fallbackRelay1URL = "wss://fallback1.example"
        let fallbackRelay2URL = "wss://fallback2.example"
        await pool.addRelay(url: fallbackRelay1URL, origin: .explicit)
        await pool.addRelay(url: fallbackRelay2URL, origin: .explicit)
        
        // Add explicit relays for the subscription
        let explicitRelay1URL = "wss://explicit1.example"
        let explicitRelay2URL = "wss://explicit2.example"
        await pool.addRelay(url: explicitRelay1URL, origin: .explicit)
        await pool.addRelay(url: explicitRelay2URL, origin: .explicit)
        
        // Create a subscription WITH explicit relays
        let filter = NDKFilter(kinds: [1], limit: 10)
        let dataSource = ndk.observe(
            filter: filter,
            relays: Set([explicitRelay1URL, explicitRelay2URL]),
            cachePolicy: .networkOnly
        )
        
        // Start collecting events
        let task = Task {
            var events: [NDKEvent] = []
            for await event in dataSource {
                events.append(event)
            }
            return events
        }
        
        // Give the subscription time to be established
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify the subscription was created ONLY for explicit relays, NOT fallback relays
        let internalManager = ndk.internalSubscriptionManager
        
        // Check explicit relays (should have subscriptions)
        let explicitRelay1Subs = await internalManager.getSubscriptionsForRelay(explicitRelay1URL)
        let explicitRelay2Subs = await internalManager.getSubscriptionsForRelay(explicitRelay2URL)
        XCTAssertFalse(explicitRelay1Subs.isEmpty, "Subscription should be on explicit relay 1")
        XCTAssertFalse(explicitRelay2Subs.isEmpty, "Subscription should be on explicit relay 2")
        
        // Check fallback relays (should NOT have subscriptions)
        let fallbackRelay1Subs = await internalManager.getSubscriptionsForRelay(fallbackRelay1URL)
        let fallbackRelay2Subs = await internalManager.getSubscriptionsForRelay(fallbackRelay2URL)
        XCTAssertTrue(fallbackRelay1Subs.isEmpty, "Subscription should NOT be on fallback relay 1")
        XCTAssertTrue(fallbackRelay2Subs.isEmpty, "Subscription should NOT be on fallback relay 2")
        
        // Cancel the subscription
        task.cancel()
        _ = await task.result
    }
}

// Add helper method to InternalSubscriptionManager for testing
extension InternalSubscriptionManager {
    func getSubscriptionsForRelay(_ relayURL: RelayURL) async -> Set<InternalSubscription> {
        return relayToSubscriptions[relayURL] ?? Set()
    }
}