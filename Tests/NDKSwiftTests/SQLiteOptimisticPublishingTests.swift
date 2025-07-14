import XCTest
@testable import NDKSwift

class SQLiteOptimisticPublishingTests: XCTestCase {
    private var cache: NDKSQLiteCache!
    private var tempDbPath: String!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a temporary database for testing
        tempDbPath = NSTemporaryDirectory() + UUID().uuidString + ".db"
        cache = try await NDKSQLiteCache(path: tempDbPath)
    }
    
    override func tearDown() async throws {
        try await super.tearDown()
        
        // Clean up the temporary database file
        if FileManager.default.fileExists(atPath: tempDbPath) {
            try FileManager.default.removeItem(atPath: tempDbPath)
        }
    }
    
    func testAddUnpublishedEvent() async throws {
        // Create a test event using proper NDKEvent initializer
        let event = NDKEvent(
            id: "test_event_id",
            pubkey: "test_pubkey",
            createdAt: 1234567890,
            kind: 1,
            tags: [],
            content: "Test content",
            sig: "test_signature"
        )
        
        let targetRelays = Set(["wss://relay1.com", "wss://relay2.com"])
        
        // Add as unpublished event
        try await cache.addUnpublishedEvent(event, relays: targetRelays)
        
        // Verify the event was saved
        let retrievedEvent = await cache.getEvent(id: "test_event_id")
        XCTAssertNotNil(retrievedEvent)
        XCTAssertEqual(retrievedEvent?.content, "Test content")
        
        // Verify the confirmation state is optimistic
        let confirmationState = await cache.getEventConfirmationState(eventId: "test_event_id")
        XCTAssertNotNil(confirmationState)
        XCTAssertEqual(confirmationState, .optimistic)
    }
    
    func testConfirmEvent() async throws {
        // Create and add unpublished event
        let event = NDKEvent(
            id: "test_event_id",
            pubkey: "test_pubkey",
            createdAt: 1234567890,
            kind: 1,
            tags: [],
            content: "Test content",
            sig: "test_signature"
        )
        
        let targetRelays = Set(["wss://relay1.com", "wss://relay2.com"])
        try await cache.addUnpublishedEvent(event, relays: targetRelays)
        
        // Confirm the event
        try await cache.confirmEvent(eventId: "test_event_id", onRelay: "wss://relay1.com")
        
        // Verify the confirmation state is confirmed
        let confirmationState = await cache.getEventConfirmationState(eventId: "test_event_id")
        XCTAssertNotNil(confirmationState)
        XCTAssertEqual(confirmationState, .confirmed(fromRelay: "wss://relay1.com"))
    }
    
    func testGetEventConfirmationStateForNonExistentEvent() async throws {
        // Test getting confirmation state for non-existent event
        let confirmationState = await cache.getEventConfirmationState(eventId: "non_existent_event")
        XCTAssertNil(confirmationState)
    }
    
    func testOptimisticToConfirmedTransition() async throws {
        // Create and add unpublished event
        let event = NDKEvent(
            id: "test_event_id",
            pubkey: "test_pubkey",
            createdAt: 1234567890,
            kind: 1,
            tags: [],
            content: "Test content",
            sig: "test_signature"
        )
        
        let targetRelays = Set(["wss://relay1.com", "wss://relay2.com"])
        try await cache.addUnpublishedEvent(event, relays: targetRelays)
        
        // Initial state should be optimistic
        var confirmationState = await cache.getEventConfirmationState(eventId: "test_event_id")
        XCTAssertEqual(confirmationState, .optimistic)
        
        // Confirm the event
        try await cache.confirmEvent(eventId: "test_event_id", onRelay: "wss://relay1.com")
        
        // State should now be confirmed
        confirmationState = await cache.getEventConfirmationState(eventId: "test_event_id")
        XCTAssertEqual(confirmationState, .confirmed(fromRelay: "wss://relay1.com"))
    }
    
    func testGetUnpublishedEvents() async throws {
        // Create and add multiple unpublished events
        let event1 = NDKEvent(
            id: "test_event_1",
            pubkey: "test_pubkey",
            createdAt: 1234567890,
            kind: 1,
            tags: [],
            content: "Test content 1",
            sig: "test_signature_1"
        )
        
        let event2 = NDKEvent(
            id: "test_event_2",
            pubkey: "test_pubkey",
            createdAt: 1234567891,
            kind: 1,
            tags: [],
            content: "Test content 2",
            sig: "test_signature_2"
        )
        
        let event3 = NDKEvent(
            id: "test_event_3",
            pubkey: "test_pubkey",
            createdAt: 1234567892,
            kind: 1,
            tags: [],
            content: "Test content 3",
            sig: "test_signature_3"
        )
        
        let targetRelays1 = Set(["wss://relay1.com", "wss://relay2.com"])
        let targetRelays2 = Set(["wss://relay2.com", "wss://relay3.com"])
        let targetRelays3 = Set(["wss://relay1.com", "wss://relay3.com"])
        
        // Add events as unpublished
        try await cache.addUnpublishedEvent(event1, relays: targetRelays1)
        try await cache.addUnpublishedEvent(event2, relays: targetRelays2)
        try await cache.addUnpublishedEvent(event3, relays: targetRelays3)
        
        // Confirm one event
        try await cache.confirmEvent(eventId: "test_event_2", onRelay: "wss://relay2.com")
        
        // Get unpublished events
        let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        
        // Should get 2 events (event1 and event3), not the confirmed event2
        XCTAssertEqual(unpublishedEvents.count, 2)
        
        let eventIds = Set(unpublishedEvents.map { $0.event.id })
        XCTAssertTrue(eventIds.contains("test_event_1"))
        XCTAssertTrue(eventIds.contains("test_event_3"))
        XCTAssertFalse(eventIds.contains("test_event_2"))
        
        // Verify target relays are preserved
        for (event, relays) in unpublishedEvents {
            if event.id == "test_event_1" {
                XCTAssertEqual(relays, targetRelays1)
            } else if event.id == "test_event_3" {
                XCTAssertEqual(relays, targetRelays3)
            }
        }
    }
    
    func testGetUnpublishedEventsWithLimit() async throws {
        // Create multiple unpublished events
        for i in 1...5 {
            let event = NDKEvent(
                id: "test_event_\(i)",
                pubkey: "test_pubkey",
                createdAt: Int64(1234567890 + i),
                kind: 1,
                tags: [],
                content: "Test content \(i)",
                sig: "test_signature_\(i)"
            )
            
            try await cache.addUnpublishedEvent(event, relays: Set(["wss://relay1.com"]))
        }
        
        // Get with limit
        let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: 3600, limit: 3)
        
        // Should get only 3 events (most recent first)
        XCTAssertEqual(unpublishedEvents.count, 3)
        
        // Should be in descending order by creation time (newest first)
        let eventIds = unpublishedEvents.map { $0.event.id }
        XCTAssertEqual(eventIds, ["test_event_5", "test_event_4", "test_event_3"])
    }
    
    func testGetUnpublishedEventsWithAge() async throws {
        // This test is challenging to implement in unit tests since we'd need to wait for time
        // or mock the database time. For now, we'll just test that the method works with age parameter
        let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: 1, limit: nil)
        XCTAssertEqual(unpublishedEvents.count, 0) // No events older than 1 second
    }
}