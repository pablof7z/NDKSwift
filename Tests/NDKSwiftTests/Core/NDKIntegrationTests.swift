@testable import NDKSwift
import XCTest

final class NDKIntegrationTests: XCTestCase {
    var ndk: NDK!
    
    override func setUp() async throws {
        ndk = NDK()
        
        // Add test relays
        _ = await ndk.relayPool.addRelay(url: "wss://test1.relay.com")
        _ = await ndk.relayPool.addRelay(url: "wss://test2.relay.com")
    }
    
    override func tearDown() async throws {
        ndk = nil
    }
    
    // MARK: - Core Functionality Tests
    
    func testNDKInitialization() {
        XCTAssertNotNil(ndk)
        XCTAssertNil(ndk.signer) // Should be nil initially
        XCTAssertNil(ndk.cacheAdapter) // Should be nil initially
        XCTAssertEqual(ndk.relays.count, 2)
    }
    
    func testSignerIntegration() async throws {
        // Test setting a signer
        let signer = try NDKPrivateKeySigner()
        ndk.signer = signer
        
        XCTAssertNotNil(ndk.signer)
        
        let pubkey = try await signer.pubkey
        XCTAssertFalse(pubkey.isEmpty)
        XCTAssertEqual(pubkey.count, 64) // Hex pubkey should be 64 chars
    }
    
    func testCacheIntegration() async throws {
        // Test setting a cache adapter
        let cache = NDKInMemoryCache()
        ndk.cacheAdapter = cache
        
        XCTAssertNotNil(ndk.cacheAdapter)
        
        // Test basic cache operations through NDK
        let event = createTestEvent()
        await cache.setEvent(event, filters: [], relay: nil)
        
        let filter = NDKFilter(authors: [event.pubkey], kinds: [event.kind])
        let subscription = NDKSubscription(filters: [filter], ndk: ndk)
        let cachedEvents = await cache.query(subscription: subscription)
        
        XCTAssertEqual(cachedEvents.count, 1)
        XCTAssertEqual(cachedEvents.first?.id, event.id)
    }
    
    func testEventCreationAndSigning() async throws {
        let signer = try NDKPrivateKeySigner()
        ndk.signer = signer
        
        let event = NDKEvent(
            pubkey: try await signer.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test message"
        )
        
        // Generate ID
        let eventId = try event.generateID()
        XCTAssertNotNil(event.id)
        XCTAssertEqual(event.id, eventId)
        XCTAssertEqual(eventId.count, 64) // Hex ID should be 64 chars
        
        // Sign event
        event.sig = try await signer.sign(event)
        XCTAssertNotNil(event.sig)
        XCTAssertFalse(event.sig!.isEmpty)
    }
    
    func testSubscriptionLifecycle() async throws {
        let filter = NDKFilter(kinds: [1], limit: 10)
        let subscription = NDKSubscription(filters: [filter], ndk: ndk)
        
        // Test subscription creation
        XCTAssertFalse(subscription.isActive)
        XCTAssertFalse(subscription.isClosed)
        XCTAssertEqual(subscription.events.count, 0)
        
        // Test starting subscription
        subscription.start()
        XCTAssertTrue(subscription.isActive)
        XCTAssertFalse(subscription.isClosed)
        
        // Test closing subscription
        subscription.close()
        XCTAssertFalse(subscription.isActive)
        XCTAssertTrue(subscription.isClosed)
    }
    
    func testEventFiltering() {
        let filter = NDKFilter(
            authors: ["author1", "author2"],
            kinds: [1, 6],
            since: 1000,
            until: 2000
        )
        
        // Test matching event
        let matchingEvent = NDKEvent(
            pubkey: "author1",
            createdAt: 1500,
            kind: 1,
            tags: [],
            content: "Test"
        )
        XCTAssertTrue(filter.matches(event: matchingEvent))
        
        // Test non-matching author
        let wrongAuthorEvent = NDKEvent(
            pubkey: "author3",
            createdAt: 1500,
            kind: 1,
            tags: [],
            content: "Test"
        )
        XCTAssertFalse(filter.matches(event: wrongAuthorEvent))
        
        // Test non-matching kind
        let wrongKindEvent = NDKEvent(
            pubkey: "author1",
            createdAt: 1500,
            kind: 2,
            tags: [],
            content: "Test"
        )
        XCTAssertFalse(filter.matches(event: wrongKindEvent))
        
        // Test timestamp filtering
        let tooOldEvent = NDKEvent(
            pubkey: "author1",
            createdAt: 500,
            kind: 1,
            tags: [],
            content: "Test"
        )
        XCTAssertFalse(filter.matches(event: tooOldEvent))
        
        let tooNewEvent = NDKEvent(
            pubkey: "author1",
            createdAt: 2500,
            kind: 1,
            tags: [],
            content: "Test"
        )
        XCTAssertFalse(filter.matches(event: tooNewEvent))
    }
    
    func testRelayManagement() async throws {
        // Test adding relays
        XCTAssertEqual(ndk.relays.count, 2)
        
        let newRelay = await ndk.relayPool.addRelay(url: "wss://test3.relay.com")
        XCTAssertNotNil(newRelay)
        XCTAssertEqual(ndk.relays.count, 3)
        
        // Test relay lookup
        let foundRelay = await ndk.relayPool.relay(for: "wss://test1.relay.com")
        XCTAssertNotNil(foundRelay)
        XCTAssertEqual(foundRelay?.url, "wss://test1.relay.com")
        
        // Test relay removal
        await ndk.relayPool.removeRelay(url: "wss://test3.relay.com")
        XCTAssertEqual(ndk.relays.count, 2)
    }
    
    func testUserProfileHandling() async throws {
        let user = NDKUser(pubkey: "test_pubkey", ndk: ndk)
        
        XCTAssertEqual(user.pubkey, "test_pubkey")
        XCTAssertEqual(user.ndk, ndk)
        XCTAssertNil(user.profile) // Should be nil initially
        
        // Test profile creation
        let profile = NDKUserProfile(
            name: "Test User",
            about: "A test user",
            picture: "https://example.com/avatar.png",
            nip05: "test@example.com"
        )
        
        user.profile = profile
        XCTAssertNotNil(user.profile)
        XCTAssertEqual(user.profile?.name, "Test User")
        XCTAssertEqual(user.profile?.about, "A test user")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidEventHandling() {
        // Test event with missing required fields
        let invalidEvent = NDKEvent()
        
        XCTAssertThrowsError(try invalidEvent.generateID()) { error in
            // Should throw an error for missing pubkey
        }
    }
    
    func testInvalidSignerHandling() async throws {
        let event = createTestEvent()
        
        // Test signing without a signer set
        XCTAssertNil(ndk.signer)
        // Would need to test actual signing error, but that requires protocol refactoring
    }
    
    // MARK: - Helper Methods
    
    private func createTestEvent(
        pubkey: String = "test_pubkey",
        kind: Kind = 1,
        content: String = "Test content"
    ) -> NDKEvent {
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            tags: [],
            content: content
        )
        
        // Generate ID for tests that need it
        try? event.generateID()
        
        return event
    }
}