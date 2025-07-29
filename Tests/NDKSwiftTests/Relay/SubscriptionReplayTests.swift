import XCTest
@testable import NDKSwift
import Combine

final class SubscriptionReplayTests: XCTestCase {
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
    
    func testSubscriptionReplayOnReconnect() async throws {
        // Create a test relay URL
        let relayURL = "wss://test.relay.example"
        
        // Add relay to pool
        let mockRelay = MockRelay(url: relayURL)
        await pool.addRelay(relay: mockRelay as any NDKRelay)
        
        // Connect the relay
        await mockRelay.connect()
        
        // Create a subscription without explicit relays (should use default relays)
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
        
        // Verify subscription was sent to relay
        XCTAssertFalse(mockRelay.activeSubscriptions.isEmpty, "Subscription should be active on relay")
        let originalSubId = mockRelay.activeSubscriptions.keys.first!
        
        // Simulate relay disconnect
        await mockRelay.disconnect()
        mockRelay.activeSubscriptions.removeAll()
        
        // Give time for disconnect to process
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Simulate relay reconnect
        await mockRelay.connect()
        
        // Give time for replay to happen
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify subscription was replayed
        XCTAssertFalse(mockRelay.activeSubscriptions.isEmpty, "Subscription should be replayed on reconnect")
        
        // Cancel the subscription
        task.cancel()
        _ = await task.result
    }
    
    func testSubscriptionReplayWithExplicitRelays() async throws {
        // Create test relay URLs
        let relay1URL = "wss://relay1.example"
        let relay2URL = "wss://relay2.example"
        
        // Add relays to pool
        let mockRelay1 = MockRelay(url: relay1URL)
        let mockRelay2 = MockRelay(url: relay2URL)
        await pool.addRelay(relay: mockRelay1 as any NDKRelay)
        await pool.addRelay(relay: mockRelay2 as any NDKRelay)
        
        // Connect relays
        await mockRelay1.connect()
        await mockRelay2.connect()
        
        // Create a subscription with explicit relays
        let filter = NDKFilter(kinds: [1], limit: 10)
        let dataSource = ndk.observe(
            filter: filter,
            relays: Set([relay1URL, relay2URL]),
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
        
        // Verify subscription was sent to both relays
        XCTAssertFalse(mockRelay1.activeSubscriptions.isEmpty, "Subscription should be active on relay1")
        XCTAssertFalse(mockRelay2.activeSubscriptions.isEmpty, "Subscription should be active on relay2")
        
        // Simulate relay1 disconnect
        await mockRelay1.disconnect()
        mockRelay1.activeSubscriptions.removeAll()
        
        // Give time for disconnect to process
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify relay2 still has subscription
        XCTAssertFalse(mockRelay2.activeSubscriptions.isEmpty, "Subscription should still be active on relay2")
        
        // Simulate relay1 reconnect
        await mockRelay1.connect()
        
        // Give time for replay to happen
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify subscription was replayed to relay1
        XCTAssertFalse(mockRelay1.activeSubscriptions.isEmpty, "Subscription should be replayed on relay1 reconnect")
        XCTAssertFalse(mockRelay2.activeSubscriptions.isEmpty, "Subscription should still be active on relay2")
        
        // Cancel the subscription
        task.cancel()
        _ = await task.result
    }
    
    func testSubscriptionReplayWithOutboxModel() async throws {
        // Create NDK with outbox enabled
        let outboxNDK = NDK(pool: pool, enableOutbox: true)
        
        // Create test relay URLs
        let relay1URL = "wss://relay1.example"
        let relay2URL = "wss://relay2.example"
        
        // Add relays to pool
        let mockRelay1 = MockRelay(url: relay1URL)
        let mockRelay2 = MockRelay(url: relay2URL)
        await pool.addRelay(relay: mockRelay1 as any NDKRelay)
        await pool.addRelay(relay: mockRelay2 as any NDKRelay)
        
        // Connect relays
        await mockRelay1.connect()
        await mockRelay2.connect()
        
        // Mock outbox tracker to return relay preferences
        let author = "test-pubkey"
        await outboxNDK.outboxTracker?.cacheRelayList(
            pubkey: author,
            read: [relay1URL],
            write: [relay1URL, relay2URL]
        )
        
        // Create a subscription that will use outbox model
        let filter = NDKFilter(kinds: [1], authors: [author], limit: 10)
        let dataSource = outboxNDK.observe(filter: filter, cachePolicy: .networkOnly)
        
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
        
        // Verify subscription was sent to author's write relays
        XCTAssertFalse(mockRelay1.activeSubscriptions.isEmpty, "Subscription should be active on relay1 (author's write relay)")
        XCTAssertFalse(mockRelay2.activeSubscriptions.isEmpty, "Subscription should be active on relay2 (author's write relay)")
        
        // Simulate relay1 disconnect
        await mockRelay1.disconnect()
        mockRelay1.activeSubscriptions.removeAll()
        
        // Give time for disconnect to process
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Simulate relay1 reconnect
        await mockRelay1.connect()
        
        // Give time for replay to happen
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify subscription was replayed to relay1
        XCTAssertFalse(mockRelay1.activeSubscriptions.isEmpty, "Subscription should be replayed on relay1 reconnect")
        XCTAssertFalse(mockRelay2.activeSubscriptions.isEmpty, "Subscription should still be active on relay2")
        
        // Cancel the subscription
        task.cancel()
        _ = await task.result
        
        await outboxNDK.close()
    }
    
    func testSubscriptionCleanupRemovesRelayMappings() async throws {
        // Create a test relay URL
        let relayURL = "wss://test.relay.example"
        
        // Add relay to pool
        let mockRelay = MockRelay(url: relayURL)
        await pool.addRelay(relay: mockRelay as any NDKRelay)
        
        // Connect the relay
        await mockRelay.connect()
        
        // Create a subscription
        let filter = NDKFilter(kinds: [1], limit: 10)
        let handle = ndk.subscribe(filter: filter, cachePolicy: .networkOnly)
        
        // Start collecting events
        let task = Task {
            var events: [NDKEvent] = []
            for await event in handle {
                events.append(event)
            }
            return events
        }
        
        // Give the subscription time to be established
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify subscription was sent to relay
        XCTAssertFalse(mockRelay.activeSubscriptions.isEmpty, "Subscription should be active on relay")
        
        // Cancel the subscription
        await handle.cancel()
        task.cancel()
        _ = await task.result
        
        // Give time for cleanup
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Disconnect and reconnect relay
        await mockRelay.disconnect()
        mockRelay.activeSubscriptions.removeAll()
        await mockRelay.connect()
        
        // Give time for potential replay
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify subscription was NOT replayed (since it was cancelled)
        XCTAssertTrue(mockRelay.activeSubscriptions.isEmpty, "Cancelled subscription should not be replayed")
    }
}

// MARK: - Mock Relay for Testing

private actor MockRelay: NDKRelay {
    let url: String
    var activeSubscriptions: [String: [NDKFilter]] = [:]
    private var isConnected = false
    
    init(url: String) {
        self.url = url
    }
    
    func connect() async {
        isConnected = true
        // Simulate relay connection event
        await NDK.shared?.pool?.relayChanges.send(.relayConnected(self))
    }
    
    func disconnect() async {
        isConnected = false
        // Simulate relay disconnection event
        await NDK.shared?.pool?.relayChanges.send(.relayDisconnected(self, error: nil))
    }
    
    func send(_ message: String) async throws {
        // Parse REQ message and track subscription
        if message.starts(with: "[\"REQ\"") {
            // Simple parsing for test purposes
            let components = message.components(separatedBy: "\"")
            if components.count > 3 {
                let subId = components[3]
                activeSubscriptions[subId] = []
            }
        }
    }
    
    func trackSubscription(id: String, filters: [NDKFilter]) async {
        activeSubscriptions[id] = filters
    }
    
    func removeSubscription(id: String) async {
        activeSubscriptions.removeValue(forKey: id)
    }
    
    func addSubscription(_ subscription: InternalSubscription, filters: [NDKFilter]) async {
        activeSubscriptions[subscription.id] = filters
    }
    
    // Other required protocol methods would go here...
}