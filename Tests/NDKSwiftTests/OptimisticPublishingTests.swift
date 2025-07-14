import XCTest
@testable import NDKSwift

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
final class OptimisticPublishingTests: XCTestCase {
    
    var ndk: NDK!
    var cache: SimpleMemoryCache!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create cache
        cache = SimpleMemoryCache()
        
        // Create NDK with optimistic publishing enabled
        ndk = NDK(
            relayUrls: [],
            signer: nil,
            cache: cache
        )
        
        // Ensure optimistic publishing is enabled
        ndk.optimisticPublishingConfig = NDKOptimisticPublishingConfig(
            enabled: true,
            cacheUnpublishedEvents: true,
            dispatchToSubscriptions: true
        )
    }
    
    override func tearDown() async throws {
        ndk = nil
        cache = nil
        try await super.tearDown()
    }
    
    func testOptimisticEventDispatchToSubscription() async throws {
        // Create a subscription that matches text notes
        let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])])
        
        // Create an event
        let event = NDKEvent(
            id: "test_event_id",
            pubkey: "test_pubkey",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test optimistic event",
            signature: "test_signature"
        )
        
        // Publish the event (this should trigger optimistic dispatch)
        _ = try await ndk.publish(event)
        
        // Check that the event was added to cache as unpublished
        let confirmationState = await cache.getEventConfirmationState(eventId: event.id)
        XCTAssertEqual(confirmationState, .optimistic)
        
        // Verify event was cached
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
        XCTAssertEqual(cachedEvent?.id, event.id)
        
        // Clean up
        await subscription.close()
    }
    
    func testOptimisticEventConfirmation() async throws {
        // Create an event
        let event = NDKEvent(
            id: "test_event_id_2",
            pubkey: "test_pubkey",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test confirmation",
            signature: "test_signature"
        )
        
        // Publish the event
        _ = try await ndk.publish(event)
        
        // Verify initial state is optimistic
        let initialState = await cache.getEventConfirmationState(eventId: event.id)
        XCTAssertEqual(initialState, .optimistic)
        
        // Simulate relay confirmation
        try await cache.confirmEvent(eventId: event.id, onRelay: "wss://relay.example.com")
        
        // Verify state changed to confirmed
        let confirmedState = await cache.getEventConfirmationState(eventId: event.id)
        XCTAssertEqual(confirmedState, .confirmed(fromRelay: "wss://relay.example.com"))
        XCTAssertTrue(confirmedState?.isConfirmed ?? false)
    }
    
    func testSkipOptimisticEvents() async throws {
        // Create a subscription that skips optimistic events
        var options = NDKSubscriptionOptions()
        options.skipOptimisticEvents = true
        
        let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])], options: options)
        
        // Create an event
        let event = NDKEvent(
            id: "test_event_id_3",
            pubkey: "test_pubkey",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test skip optimistic",
            signature: "test_signature"
        )
        
        // Publish the event
        _ = try await ndk.publish(event)
        
        // The event should still be in cache
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
        
        // But the subscription should have the skipOptimisticEvents option
        let subscriptionOptions = await subscription.options
        XCTAssertTrue(subscriptionOptions.skipOptimisticEvents)
        
        // Clean up
        await subscription.close()
    }
    
    func testOptimisticPublishingDisabled() async throws {
        // Disable optimistic publishing
        ndk.optimisticPublishingConfig = .disabled
        
        // Create an event
        let event = NDKEvent(
            id: "test_event_id_4",
            pubkey: "test_pubkey",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test disabled optimistic",
            signature: "test_signature"
        )
        
        // Publish the event
        _ = try await ndk.publish(event)
        
        // Event should not have optimistic confirmation state
        let confirmationState = await cache.getEventConfirmationState(eventId: event.id)
        XCTAssertNil(confirmationState)
        
        // Event should still be in cache from regular save
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
    }
    
    func testEventSourceTypes() async throws {
        // Test EventSource enum
        let relaySource = EventSource.relay(MockRelay())
        let optimisticSource = EventSource.optimistic
        let cacheSource = EventSource.cache
        
        // These should compile and be distinct
        switch relaySource {
        case .relay:
            XCTAssertTrue(true)
        case .optimistic, .cache:
            XCTFail("Should be relay source")
        }
        
        switch optimisticSource {
        case .optimistic:
            XCTAssertTrue(true)
        case .relay, .cache:
            XCTFail("Should be optimistic source")
        }
        
        switch cacheSource {
        case .cache:
            XCTAssertTrue(true)
        case .relay, .optimistic:
            XCTFail("Should be cache source")
        }
    }
    
    func testEventConfirmationState() async throws {
        // Test EventConfirmationState enum
        let optimisticState = EventConfirmationState.optimistic
        let confirmedState = EventConfirmationState.confirmed(fromRelay: "wss://relay.example.com")
        
        // Test isConfirmed property
        XCTAssertFalse(optimisticState.isConfirmed)
        XCTAssertTrue(confirmedState.isConfirmed)
        
        // Test equality
        XCTAssertEqual(optimisticState, .optimistic)
        XCTAssertEqual(confirmedState, .confirmed(fromRelay: "wss://relay.example.com"))
        XCTAssertNotEqual(optimisticState, confirmedState)
    }
}

// Mock relay for testing
class MockRelay: RelayProtocol {
    let url: String = "wss://test.relay.com"
    
    func send(_ message: String) async throws {
        // Mock implementation
    }
    
    func getSignatureStats() async -> SignatureStats {
        return SignatureStats()
    }
    
    func updateSignatureStats(_ updater: @escaping (inout SignatureStats) -> Void) async {
        // Mock implementation
    }
}