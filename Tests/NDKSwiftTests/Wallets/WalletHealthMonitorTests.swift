import XCTest
import CashuSwift
@testable import NDKSwift

final class WalletHealthMonitorTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var wallet: NIP60Wallet!
    var healthMonitor: WalletHealthMonitor!
    var eventManager: WalletEventManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create signer
        let privateKey = Crypto.generatePrivateKey()
        signer = NDKPrivateKeySigner(privateKey: privateKey)
        
        // Create NDK instance with SQLite cache
        let cache = try await NDKSQLiteCache()
        ndk = NDK(signer: signer, cache: cache)
        
        // Create wallet
        wallet = NIP60Wallet(ndk: ndk, cache: cache)
        
        // Get references to internal components
        eventManager = wallet.eventManager
        healthMonitor = wallet.healthMonitor
    }
    
    override func tearDown() async throws {
        await wallet.stop()
        ndk = nil
        signer = nil
        wallet = nil
        try await super.tearDown()
    }
    
    // MARK: - Tests
    
    func testRelayHealthWithNoEvents() async throws {
        // Given: No events in the wallet
        let relay1 = NDKRelay(url: "wss://relay1.example.com")
        let relay2 = NDKRelay(url: "wss://relay2.example.com")
        
        // When: Checking relay health
        let healthStatus = await healthMonitor.checkRelayHealth(walletRelays: [relay1, relay2])
        
        // Then: All relays should be healthy with no events
        XCTAssertEqual(healthStatus.count, 2)
        for relayHealth in healthStatus {
            XCTAssertTrue(relayHealth.isHealthy)
            XCTAssertEqual(relayHealth.knownEvents, 0)
            XCTAssertTrue(relayHealth.missingEvents.isEmpty)
            XCTAssertTrue(relayHealth.extraEvents.isEmpty)
        }
    }
    
    func testRelayHealthWithMissingEvents() async throws {
        // Given: A token event that exists locally
        let eventId = "test-event-123"
        await eventManager.addCurrentTokenEventId(eventId)
        
        // And: One relay has seen the event, another hasn't
        let relay1 = NDKRelay(url: "wss://relay1.example.com")
        let relay2 = NDKRelay(url: "wss://relay2.example.com")
        
        // Mark event as seen only on relay1
        await ndk.eventTracker.markSeen(eventId: eventId, relay: relay1.url)
        await ndk.eventTracker.updatePublishStatus(eventId: eventId, relay: relay1.url, status: .succeeded)
        
        // When: Checking relay health
        let healthStatus = await healthMonitor.checkRelayHealth(walletRelays: [relay1, relay2])
        
        // Then: relay1 should be healthy, relay2 should have missing events
        let relay1Health = healthStatus.first { $0.relay.url == relay1.url }!
        let relay2Health = healthStatus.first { $0.relay.url == relay2.url }!
        
        XCTAssertTrue(relay1Health.isHealthy)
        XCTAssertEqual(relay1Health.knownEvents, 1)
        XCTAssertTrue(relay1Health.missingEvents.isEmpty)
        
        XCTAssertFalse(relay2Health.isHealthy)
        XCTAssertEqual(relay2Health.knownEvents, 0)
        XCTAssertEqual(relay2Health.missingEvents, [eventId])
    }
    
    func testRelayHealthStatusAggregation() async throws {
        // Given: Multiple events and relays with different states
        let event1 = "event-1"
        let event2 = "event-2"
        await eventManager.addCurrentTokenEventId(event1)
        await eventManager.addCurrentTokenEventId(event2)
        
        let relay1 = NDKRelay(url: "wss://relay1.example.com")
        let relay2 = NDKRelay(url: "wss://relay2.example.com")
        let relay3 = NDKRelay(url: "wss://relay3.example.com")
        
        // relay1 has all events
        await ndk.eventTracker.markSeen(eventId: event1, relay: relay1.url)
        await ndk.eventTracker.markSeen(eventId: event2, relay: relay1.url)
        
        // relay2 has only event1
        await ndk.eventTracker.markSeen(eventId: event1, relay: relay2.url)
        
        // relay3 has no events
        
        // When: Getting wallet health status
        let status = await healthMonitor.getWalletHealthStatus(walletRelays: [relay1, relay2, relay3])
        
        // Then: Status should correctly aggregate the health information
        XCTAssertFalse(status.isHealthy) // Not all relays are healthy
        XCTAssertEqual(status.totalEvents, 2)
        XCTAssertEqual(status.syncedRelays, 1) // Only relay1 is fully synced
        XCTAssertEqual(status.outOfSyncRelays, 2) // relay2 and relay3 are out of sync
        XCTAssertEqual(status.relayHealth.count, 3)
    }
    
    func testRelayHealthWithDeletedEvents() async throws {
        // Given: An event that was added then marked as deleted
        let eventId = "deleted-event-123"
        await eventManager.addCurrentTokenEventId(eventId)
        await eventManager.markEventDeleted(eventId)
        
        // Update current token event IDs to remove the deleted one
        let current = await eventManager.getCurrentTokenEventIds()
        await eventManager.setCurrentTokenEventIds(current.subtracting([eventId]))
        
        let relay = NDKRelay(url: "wss://relay.example.com")
        
        // When: Checking relay health
        let healthStatus = await healthMonitor.checkRelayHealth(walletRelays: [relay])
        
        // Then: Deleted events should not appear in canonical set
        let relayHealth = healthStatus.first!
        XCTAssertTrue(relayHealth.isHealthy)
        XCTAssertEqual(relayHealth.knownEvents, 0)
        XCTAssertTrue(relayHealth.missingEvents.isEmpty)
    }
    
    func testEventPublishingUpdatesTracker() async throws {
        // Given: A new event to publish
        let event = try await ndk.event()
            .content("Test wallet event")
            .kind(7375)
            .build(signer: signer)
        
        let relay1 = NDKRelay(url: "wss://relay1.example.com")
        let relay2 = NDKRelay(url: "wss://relay2.example.com")
        
        // Mock successful publish to relay1, failed to relay2
        // Note: In a real test, you'd use a MockRelay that implements RelayProtocol
        
        // When: Publishing the event (this would normally go through NDKEventManager)
        // For this test, we'll simulate what NDKEventManager does
        await ndk.eventTracker.updatePublishStatus(eventId: event.id, relay: relay1.url, status: .succeeded)
        await ndk.eventTracker.markSeen(eventId: event.id, relay: relay1.url)
        await ndk.eventTracker.updatePublishStatus(eventId: event.id, relay: relay2.url, status: .failed(.connectionFailed))
        
        // Then: Event tracker should have the correct status
        let seenOnRelays = await ndk.eventTracker.getSeenOnRelays(eventId: event.id)
        XCTAssertTrue(seenOnRelays.contains(relay1.url))
        XCTAssertFalse(seenOnRelays.contains(relay2.url))
        
        let successfulRelays = await ndk.eventTracker.getSuccessfullyPublishedRelays(eventId: event.id)
        XCTAssertEqual(successfulRelays, [relay1.url])
        
        let failedRelays = await ndk.eventTracker.getFailedPublishRelays(eventId: event.id)
        XCTAssertEqual(failedRelays, [relay2.url])
    }
}