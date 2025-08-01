import XCTest
@testable import NDKSwift

final class NDKEventTrackerTests: XCTestCase {
    
    private var tracker: NDKEventTracker!
    private let testEventId = "test-event-id-123"
    private let testRelay1 = "wss://relay1.example.com"
    private let testRelay2 = "wss://relay2.example.com"
    
    override func setUp() async throws {
        tracker = NDKEventTracker()
    }
    
    override func tearDown() async throws {
        tracker = nil
    }
    
    // MARK: - Relay Tracking Tests
    
    func testMarkSeen() async {
        // When
        await tracker.markSeen(eventId: testEventId, relay: testRelay1)
        let seenRelays = await tracker.getSeenOnRelays(eventId: testEventId)
        
        // Then
        XCTAssertTrue(seenRelays.contains(testRelay1))
        XCTAssertEqual(seenRelays.count, 1)
    }
    
    func testMarkSeenMultipleRelays() async {
        // When
        await tracker.markSeen(eventId: testEventId, relay: testRelay1)
        await tracker.markSeen(eventId: testEventId, relay: testRelay2)
        let seenRelays = await tracker.getSeenOnRelays(eventId: testEventId)
        
        // Then
        XCTAssertTrue(seenRelays.contains(testRelay1))
        XCTAssertTrue(seenRelays.contains(testRelay2))
        XCTAssertEqual(seenRelays.count, 2)
    }
    
    func testMarkSeenDuplicateRelay() async {
        // When
        await tracker.markSeen(eventId: testEventId, relay: testRelay1)
        await tracker.markSeen(eventId: testEventId, relay: testRelay1)
        let seenRelays = await tracker.getSeenOnRelays(eventId: testEventId)
        
        // Then
        XCTAssertEqual(seenRelays.count, 1)
    }
    
    func testSetSourceRelay() async {
        // When
        await tracker.setSourceRelay(eventId: testEventId, relay: testRelay1)
        let sourceRelay = await tracker.getSourceRelay(eventId: testEventId)
        let seenRelays = await tracker.getSeenOnRelays(eventId: testEventId)
        
        // Then
        XCTAssertEqual(sourceRelay, testRelay1)
        XCTAssertTrue(seenRelays.contains(testRelay1))
    }
    
    func testGetSourceRelayNotSet() async {
        // When
        let sourceRelay = await tracker.getSourceRelay(eventId: testEventId)
        
        // Then
        XCTAssertNil(sourceRelay)
    }
    
    // MARK: - Publish Status Tests
    
    func testUpdatePublishStatus() async {
        // When
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay1, status: .succeeded)
        let status = await tracker.getPublishStatus(eventId: testEventId, relay: testRelay1)
        
        // Then
        XCTAssertEqual(status, .succeeded)
    }
    
    func testGetRelayPublishStatuses() async {
        // When
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay1, status: .succeeded)
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay2, status: .failed(.connectionFailed))
        let statuses = await tracker.getRelayPublishStatuses(eventId: testEventId)
        
        // Then
        XCTAssertEqual(statuses.count, 2)
        XCTAssertEqual(statuses[testRelay1], .succeeded)
        if case .failed = statuses[testRelay2] {
            // Success
        } else {
            XCTFail("Expected failed status for relay2")
        }
    }
    
    func testGetSuccessfullyPublishedRelays() async {
        // When
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay1, status: .succeeded)
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay2, status: .failed(.connectionFailed))
        let successfulRelays = await tracker.getSuccessfullyPublishedRelays(eventId: testEventId)
        
        // Then
        XCTAssertEqual(successfulRelays, [testRelay1])
    }
    
    func testGetFailedPublishRelays() async {
        // When
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay1, status: .succeeded)
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay2, status: .failed(.connectionFailed))
        let failedRelays = await tracker.getFailedPublishRelays(eventId: testEventId)
        
        // Then
        XCTAssertEqual(failedRelays, [testRelay2])
    }
    
    func testWasPublished() async {
        // When not published
        var wasPublished = await tracker.wasPublished(eventId: testEventId)
        XCTAssertFalse(wasPublished)
        
        // When published to at least one relay
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay1, status: .succeeded)
        wasPublished = await tracker.wasPublished(eventId: testEventId)
        XCTAssertTrue(wasPublished)
    }
    
    // MARK: - OK Message Tests
    
    func testAddOKMessage() async {
        // When
        await tracker.addOKMessage(eventId: testEventId, relay: testRelay1, accepted: true, message: "Event accepted")
        let okMessage = await tracker.getOKMessage(eventId: testEventId, relay: testRelay1)
        
        // Then
        XCTAssertNotNil(okMessage)
        XCTAssertTrue(okMessage!.accepted)
        XCTAssertEqual(okMessage!.message, "Event accepted")
        XCTAssertNotNil(okMessage!.receivedAt)
    }
    
    func testGetRelayOKMessages() async {
        // When
        await tracker.addOKMessage(eventId: testEventId, relay: testRelay1, accepted: true, message: "OK")
        await tracker.addOKMessage(eventId: testEventId, relay: testRelay2, accepted: false, message: "Rejected: duplicate")
        let okMessages = await tracker.getRelayOKMessages(eventId: testEventId)
        
        // Then
        XCTAssertEqual(okMessages.count, 2)
        XCTAssertTrue(okMessages[testRelay1]!.accepted)
        XCTAssertFalse(okMessages[testRelay2]!.accepted)
    }
    
    // MARK: - Custom Properties Tests
    
    func testSetAndGetCustomProperty() async {
        // When
        await tracker.setCustomProperty(eventId: testEventId, key: "testKey", value: "testValue")
        let value = await tracker.getCustomProperty(eventId: testEventId, key: "testKey") as? String
        
        // Then
        XCTAssertEqual(value, "testValue")
    }
    
    func testGetCustomProperties() async {
        // When
        await tracker.setCustomProperty(eventId: testEventId, key: "key1", value: "value1")
        await tracker.setCustomProperty(eventId: testEventId, key: "key2", value: 42)
        let properties = await tracker.getCustomProperties(eventId: testEventId)
        
        // Then
        XCTAssertEqual(properties.count, 2)
        XCTAssertEqual(properties["key1"] as? String, "value1")
        XCTAssertEqual(properties["key2"] as? Int, 42)
    }
    
    // MARK: - Timestamp Tests
    
    func testFirstSeenTimestamp() async {
        // When
        let beforeMark = Date()
        await tracker.markSeen(eventId: testEventId, relay: testRelay1)
        let afterMark = Date()
        let timestamp = await tracker.getFirstSeenTimestamp(eventId: testEventId)
        
        // Then
        XCTAssertNotNil(timestamp)
        XCTAssertTrue(timestamp! >= beforeMark)
        XCTAssertTrue(timestamp! <= afterMark)
    }
    
    func testFirstSeenTimestampNotUpdatedOnSubsequentMarks() async {
        // When
        await tracker.markSeen(eventId: testEventId, relay: testRelay1)
        let firstTimestamp = await tracker.getFirstSeenTimestamp(eventId: testEventId)
        
        // Add a small delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await tracker.markSeen(eventId: testEventId, relay: testRelay2)
        let secondTimestamp = await tracker.getFirstSeenTimestamp(eventId: testEventId)
        
        // Then
        XCTAssertEqual(firstTimestamp, secondTimestamp)
    }
    
    // MARK: - Cleanup Tests
    
    func testRemoveEvent() async {
        // Setup
        await tracker.markSeen(eventId: testEventId, relay: testRelay1)
        await tracker.setSourceRelay(eventId: testEventId, relay: testRelay1)
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay1, status: .succeeded)
        await tracker.addOKMessage(eventId: testEventId, relay: testRelay1, accepted: true, message: "OK")
        await tracker.setCustomProperty(eventId: testEventId, key: "key", value: "value")
        
        // When
        await tracker.removeEvent(eventId: testEventId)
        
        // Then
        let seenRelays = await tracker.getSeenOnRelays(eventId: testEventId)
        let sourceRelay = await tracker.getSourceRelay(eventId: testEventId)
        let publishStatuses = await tracker.getRelayPublishStatuses(eventId: testEventId)
        let okMessages = await tracker.getRelayOKMessages(eventId: testEventId)
        let customProperties = await tracker.getCustomProperties(eventId: testEventId)
        let timestamp = await tracker.getFirstSeenTimestamp(eventId: testEventId)
        
        XCTAssertTrue(seenRelays.isEmpty)
        XCTAssertNil(sourceRelay)
        XCTAssertTrue(publishStatuses.isEmpty)
        XCTAssertTrue(okMessages.isEmpty)
        XCTAssertTrue(customProperties.isEmpty)
        XCTAssertNil(timestamp)
    }
    
    func testCleanupOldEvents() async {
        // Setup - create events with different timestamps
        let oldEventId = "old-event"
        let recentEventId = "recent-event"
        
        // Mark old event
        await tracker.markSeen(eventId: oldEventId, relay: testRelay1)
        
        // Get timestamp between old and new events
        let cutoffDate = Date()
        
        // Wait a bit and mark recent event
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        await tracker.markSeen(eventId: recentEventId, relay: testRelay1)
        
        // When
        await tracker.cleanupOldEvents(cutoffDate: cutoffDate)
        
        // Then
        let oldEventRelays = await tracker.getSeenOnRelays(eventId: oldEventId)
        let recentEventRelays = await tracker.getSeenOnRelays(eventId: recentEventId)
        
        XCTAssertTrue(oldEventRelays.isEmpty)
        XCTAssertFalse(recentEventRelays.isEmpty)
    }
    
    // MARK: - Stats Tests
    
    func testGetStats() async {
        // Setup
        await tracker.markSeen(eventId: testEventId, relay: testRelay1)
        await tracker.markSeen(eventId: testEventId, relay: testRelay2)
        await tracker.updatePublishStatus(eventId: testEventId, relay: testRelay1, status: .succeeded)
        await tracker.addOKMessage(eventId: testEventId, relay: testRelay1, accepted: true, message: "OK")
        await tracker.setCustomProperty(eventId: testEventId, key: "key", value: "value")
        
        // When
        let stats = await tracker.getStats()
        
        // Then
        XCTAssertEqual(stats["trackedEvents"] as? Int, 1)
        XCTAssertEqual(stats["totalSeenRelays"] as? Int, 2)
        XCTAssertEqual(stats["eventsWithPublishStatus"] as? Int, 1)
        XCTAssertEqual(stats["eventsWithOKMessages"] as? Int, 1)
        XCTAssertEqual(stats["eventsWithCustomProperties"] as? Int, 1)
        XCTAssertEqual(stats["eventsWithTimestamps"] as? Int, 1)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentAccess() async {
        // Test that concurrent operations don't cause data races
        await withTaskGroup(of: Void.self) { group in
            // Multiple concurrent writes
            for i in 0..<100 {
                group.addTask {
                    let eventId = "event-\(i)"
                    let relay = "wss://relay\(i).example.com"
                    
                    await self.tracker.markSeen(eventId: eventId, relay: relay)
                    await self.tracker.updatePublishStatus(eventId: eventId, relay: relay, status: .succeeded)
                    await self.tracker.setCustomProperty(eventId: eventId, key: "index", value: i)
                }
            }
            
            // Wait for all tasks to complete
            await group.waitForAll()
        }
        
        // Verify data integrity
        let stats = await tracker.getStats()
        XCTAssertEqual(stats["trackedEvents"] as? Int, 100)
    }
}