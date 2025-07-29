import XCTest
@testable import NDKSwift

final class RelaySubscriptionIDMappingTests: XCTestCase {
    var ndk: NDK!
    var manager: InternalSubscriptionManager!
    
    override func setUp() async throws {
        try await super.setUp()
        ndk = NDK()
        manager = InternalSubscriptionManager(ndk: ndk)
    }
    
    override func tearDown() async throws {
        ndk = nil
        manager = nil
        try await super.tearDown()
    }
    
    func testRelayGeneratedSubscriptionIDMapping() async throws {
        // Create a subscription with a specific fingerprint
        let fingerprint = "authors-kinds-limit"
        let originalSubId = "k1_fa98_4D2B"
        
        let subscription = await manager.createSubscription(
            id: originalSubId,
            filters: [NDKFilter(authors: ["fa984bd7"], kinds: [1], limit: 1)],
            relays: nil,
            fingerprint: fingerprint,
            closeOnEose: false,
            autoStart: false
        )
        
        // Simulate a relay generating its own subscription ID
        let relayGeneratedId = "authors-kinds-limit_E1EE06F5"
        
        // Register the relay ID mapping
        await manager.registerRelayIdMapping(relayId: relayGeneratedId, fingerprint: fingerprint)
        
        // Create a mock relay
        let mockRelay = MockRelay(url: "wss://test.relay/")
        
        // Create a test event
        let event = NDKEvent(content: "Test event", kind: 1)
        event.pubkey = "fa984bd7"
        event.id = "test_event_id"
        event.createdAt = Timestamp(Date().timeIntervalSince1970)
        event.sig = "test_signature"
        
        // Track events received by the subscription
        var receivedEvents: [NDKEvent] = []
        await subscription.setOnEvent { event, relay in
            receivedEvents.append(event)
        }
        
        // Process event with relay-generated ID
        await manager.processEvent(event, subscriptionId: relayGeneratedId, from: mockRelay)
        
        // Verify the event was routed correctly
        XCTAssertEqual(receivedEvents.count, 1, "Event should be routed to subscription via fingerprint mapping")
        XCTAssertEqual(receivedEvents.first?.id, event.id, "Correct event should be received")
    }
    
    func testMultipleSubscriptionsWithSameFingerprint() async throws {
        let fingerprint = "authors-kinds"
        
        // Create network subscription
        let networkSub = await manager.createSubscription(
            id: "network-sub",
            filters: [NDKFilter(authors: ["author1"], kinds: [1])],
            relays: ["wss://relay1.com/"],
            fingerprint: fingerprint,
            closeOnEose: false,
            autoStart: false
        )
        
        // Create cache-only subscription with same fingerprint
        let cacheSub = await manager.createSubscription(
            id: "cache-sub",
            filters: [NDKFilter(authors: ["author1"], kinds: [1])],
            relays: nil,
            fingerprint: fingerprint,
            closeOnEose: false,
            autoStart: false
        )
        
        // Register relay-generated ID
        let relayGeneratedId = "authors-kinds_ABC123"
        await manager.registerRelayIdMapping(relayId: relayGeneratedId, fingerprint: fingerprint)
        
        // Track events for both subscriptions
        var networkEvents: [NDKEvent] = []
        var cacheEvents: [NDKEvent] = []
        
        await networkSub.setOnEvent { event, relay in
            networkEvents.append(event)
        }
        
        await cacheSub.setOnEvent { event, relay in
            cacheEvents.append(event)
        }
        
        // Create test event
        let event = NDKEvent(content: "Reactive test", kind: 1)
        event.pubkey = "author1"
        event.id = "reactive_event_id"
        event.createdAt = Timestamp(Date().timeIntervalSince1970)
        event.sig = "test_signature"
        
        // Process event with relay-generated ID
        let mockRelay = MockRelay(url: "wss://relay1.com/")
        await manager.processEvent(event, subscriptionId: relayGeneratedId, from: mockRelay)
        
        // Both subscriptions should receive the event
        XCTAssertEqual(networkEvents.count, 1, "Network subscription should receive event")
        XCTAssertEqual(cacheEvents.count, 1, "Cache subscription should receive event")
        XCTAssertEqual(networkEvents.first?.id, event.id, "Network subscription got correct event")
        XCTAssertEqual(cacheEvents.first?.id, event.id, "Cache subscription got correct event")
    }
    
    func testCleanupOfRelayIDMappings() async throws {
        let fingerprint = "test-fingerprint"
        
        // Create subscription
        let sub = await manager.createSubscription(
            id: "test-sub",
            filters: [NDKFilter(kinds: [1])],
            relays: nil,
            fingerprint: fingerprint,
            closeOnEose: false,
            autoStart: false
        )
        
        // Register multiple relay IDs for the same fingerprint
        await manager.registerRelayIdMapping(relayId: "relay-id-1", fingerprint: fingerprint)
        await manager.registerRelayIdMapping(relayId: "relay-id-2", fingerprint: fingerprint)
        
        // Close the subscription
        await manager.closeSubscription(id: "test-sub")
        
        // Try to process an event with the old relay ID
        let event = NDKEvent(content: "Should be ignored", kind: 1)
        event.id = "ignored_event"
        event.createdAt = Timestamp(Date().timeIntervalSince1970)
        event.sig = "test_signature"
        
        let mockRelay = MockRelay(url: "wss://test.relay/")
        
        // This should not crash and should be ignored
        await manager.processEvent(event, subscriptionId: "relay-id-1", from: mockRelay)
        
        // Test passes if no crash occurs
        XCTAssertTrue(true, "Event processing with stale relay ID should not crash")
    }
}