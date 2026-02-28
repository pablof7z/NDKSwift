@testable import NDKSwiftCore
import XCTest

final class DeletionEventTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var cache: NDKNostrDBCache!

    override func setUp() async throws {
        try await super.setUp()

        // Create test signer
        signer = try NDKPrivateKeySigner.generate()

        // Create cache
        cache = try await NDKTestFactory.createTestCache()

        // Create NDK with test configuration
        ndk = NDK(
            relayURLs: ["wss://relay.test"],
            signer: signer,
            cache: cache
        )
    }

    override func tearDown() async throws {
        await ndk.disconnect()
        try await super.tearDown()
    }

    func testDeletionEventCreation() async throws {
        // Create a test event
        let testEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Test post to delete")
            .kind(EventKind.textNote)
            .build(signer: signer)

        // Create deletion event
        let deletionEvent = try await testEvent.createDeletionRequest(reason: "Test deletion", signer: signer, ndk: ndk)

        // Verify deletion event structure
        XCTAssertEqual(deletionEvent.kind, EventKind.deletion)
        XCTAssertEqual(deletionEvent.content, "Test deletion")
        let signerPubkey = try await signer.pubkey
        XCTAssertEqual(deletionEvent.pubkey, signerPubkey)

        // Check for e tag
        let eTags = deletionEvent.tags.filter { $0.count >= 2 && $0[0] == "e" }
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags[0][1], testEvent.id)

        // Check for k tag
        let kTags = deletionEvent.tags.filter { $0.count >= 2 && $0[0] == "k" }
        XCTAssertEqual(kTags.count, 1)
        XCTAssertEqual(kTags[0][1], String(testEvent.kind))
    }

    func testDeletionEventProcessing() async throws {
        // Create and save an event
        let originalEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Original content")
            .kind(EventKind.textNote)
            .build(signer: signer)

        // Save to cache
        try await cache.saveEvent(originalEvent)

        // Verify it's in cache
        let cachedEvent = await cache.getEvent(id: originalEvent.id)
        XCTAssertNotNil(cachedEvent)

        // Create deletion event from same author
        let deletionEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Deleting my post")
            .kind(EventKind.deletion)
            .tagEvent(originalEvent)
            .tag(["k", String(originalEvent.kind)])
            .build(signer: signer)

        // Test the deletion logic directly
        // Extract event IDs to delete from "e" tags
        let eventIdsToDelete = deletionEvent.tags
            .filter { $0.count >= 2 && $0[0] == "e" }
            .map { $0[1] }

        // Process deletion with author validation
        for eventId in eventIdsToDelete {
            if let event = await cache.getEvent(id: eventId) {
                // NIP-09: Only original author can delete
                if event.pubkey == deletionEvent.pubkey {
                    try await cache.deleteEvent(id: eventId)
                }
            }
        }

        // Verify event was deleted from cache
        let deletedEvent = await cache.getEvent(id: originalEvent.id)
        XCTAssertNil(deletedEvent, "Event should be deleted from cache")
    }

    func testDeletionEventAuthorValidation() async throws {
        // Create event from one author
        let originalSigner = signer!
        let originalEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Original content")
            .kind(EventKind.textNote)
            .build(signer: originalSigner)

        // Save to cache
        try await cache.saveEvent(originalEvent)

        // Create another signer (different author)
        let otherSigner = try NDKPrivateKeySigner.generate()

        // Try to delete from different author
        let deletionEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Trying to delete someone else's post")
            .kind(EventKind.deletion)
            .tagEvent(originalEvent)
            .tag(["k", String(originalEvent.kind)])
            .build(signer: otherSigner)

        // Test the deletion logic with wrong author
        let eventIdsToDelete = deletionEvent.tags
            .filter { $0.count >= 2 && $0[0] == "e" }
            .map { $0[1] }

        // Process deletion with author validation
        for eventId in eventIdsToDelete {
            if let event = await cache.getEvent(id: eventId) {
                // NIP-09: Only original author can delete
                if event.pubkey == deletionEvent.pubkey {
                    try await cache.deleteEvent(id: eventId)
                }
            }
        }

        // Verify event was NOT deleted (wrong author)
        let stillCachedEvent = await cache.getEvent(id: originalEvent.id)
        XCTAssertNotNil(stillCachedEvent, "Event should NOT be deleted by different author")
    }

    func testMultipleEventDeletion() async throws {
        // Create multiple events
        let event1 = try await NDKEventBuilder(ndk: ndk)
            .content("Event 1")
            .kind(EventKind.textNote)
            .build(signer: signer)

        let event2 = try await NDKEventBuilder(ndk: ndk)
            .content("Event 2")
            .kind(EventKind.textNote)
            .build(signer: signer)

        let event3 = try await NDKEventBuilder(ndk: ndk)
            .content("Event 3")
            .kind(EventKind.reaction)
            .build(signer: signer)

        // Save all to cache
        try await cache.saveEvent(event1)
        try await cache.saveEvent(event2)
        try await cache.saveEvent(event3)

        // Create deletion event for all three
        let deletionEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Batch deletion")
            .kind(EventKind.deletion)
            .tagEvent(event1)
            .tagEvent(event2)
            .tagEvent(event3)
            .tag(["k", String(EventKind.textNote)])
            .tag(["k", String(EventKind.reaction)])
            .build(signer: signer)

        // Test deletion logic
        let eventIdsToDelete = deletionEvent.tags
            .filter { $0.count >= 2 && $0[0] == "e" }
            .map { $0[1] }

        // Process all deletions
        for eventId in eventIdsToDelete {
            if let event = await cache.getEvent(id: eventId) {
                // NIP-09: Only original author can delete
                if event.pubkey == deletionEvent.pubkey {
                    try await cache.deleteEvent(id: eventId)
                }
            }
        }

        // Verify all events were deleted
        let deletedEvent1 = await cache.getEvent(id: event1.id)
        let deletedEvent2 = await cache.getEvent(id: event2.id)
        let deletedEvent3 = await cache.getEvent(id: event3.id)
        XCTAssertNil(deletedEvent1)
        XCTAssertNil(deletedEvent2)
        XCTAssertNil(deletedEvent3)
    }

    func testDeletionEventForNonExistentEvent() async throws {
        // Create deletion event for non-existent event
        let fakeEventId = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"

        let deletionEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Deleting non-existent event")
            .kind(EventKind.deletion)
            .tag(["e", fakeEventId])
            .tag(["k", String(EventKind.textNote)])
            .build(signer: signer)

        // Test deletion logic - should not crash
        let eventIdsToDelete = deletionEvent.tags
            .filter { $0.count >= 2 && $0[0] == "e" }
            .map { $0[1] }

        // Process deletion - should handle gracefully
        for eventId in eventIdsToDelete {
            if let event = await cache.getEvent(id: eventId) {
                // NIP-09: Only original author can delete
                if event.pubkey == deletionEvent.pubkey {
                    try await cache.deleteEvent(id: eventId)
                }
            } else {
                // Event not in cache - try to delete anyway
                do {
                    try await cache.deleteEvent(id: eventId)
                } catch {
                    // Expected - event doesn't exist
                }
            }
        }

        // Test passes if no crash occurs
        XCTAssertTrue(true)
    }

    func testEventDeleteMethod() async throws {
        // Create a test event
        let testEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Test post to delete via method")
            .kind(EventKind.textNote)
            .build(signer: signer)

        // Mock NDK for testing (since we need to avoid actual network calls)
        // This test focuses on the delete method creating the right event
        let deletionEvent = try await testEvent.createDeletionRequest(reason: "Method test", signer: signer, ndk: ndk)

        // Verify the deletion event is properly formed
        XCTAssertEqual(deletionEvent.kind, EventKind.deletion)
        XCTAssertEqual(deletionEvent.content, "Method test")
        // Check for e tag
        let hasETag = deletionEvent.tags.contains { tag in
            tag.count >= 2 && tag[0] == "e" && tag[1] == testEvent.id
        }
        XCTAssertTrue(hasETag)

        // Check for k tag
        let hasKTag = deletionEvent.tags.contains { tag in
            tag.count >= 2 && tag[0] == "k" && tag[1] == String(testEvent.kind)
        }
        XCTAssertTrue(hasKTag)
    }

    func testDeletionTombstoneForOutOfOrderEvents() async throws {
        // This tests the case where a deletion event arrives before the event it's deleting

        // Create an event that will be deleted
        let originalEvent = try await NDKEventBuilder(ndk: ndk)
            .content("This will be deleted before it arrives")
            .kind(EventKind.textNote)
            .build(signer: signer)

        // Create deletion event
        let deletionEvent = try await NDKEventBuilder(ndk: ndk)
            .content("Deleting an event that hasn't arrived yet")
            .kind(EventKind.deletion)
            .tagEvent(originalEvent)
            .tag(["k", String(originalEvent.kind)])
            .build(signer: signer)

        // Process the deletion event FIRST (before the original event exists in cache)
        // In the new architecture, we process events through the cache directly
        try await cache.processEvent(deletionEvent, from: "test-relay", subscriptionId: "test-sub")

        // Now try to process the original event (simulating it arriving from a relay)
        try await cache.processEvent(originalEvent, from: "test-relay", subscriptionId: "test-sub")

        // The original event should NOT be added to cache because it was tombstoned
        let cachedEvent = await cache.getEvent(id: originalEvent.id)
        XCTAssertNil(cachedEvent, "Event should not be in cache due to tombstone")
    }
}

// MARK: - Test Helpers

private extension DeletionEventTests {
    // Helper methods can be added here if needed
}
