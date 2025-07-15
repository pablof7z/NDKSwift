import XCTest
@testable import NDKSwift

/// Basic tests for event publishing functionality
final class BasicEventPublishingTests: XCTestCase {
    
    func testEventBuilderCreatesValidEvent() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Build an event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Hello, Nostr!")
            .tag(["t", "test"])
            .build(signer: signer)
        
        // Verify event properties
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.content, "Hello, Nostr!")
        XCTAssertFalse(event.id.isEmpty)
        XCTAssertFalse(event.sig.isEmpty)
        let pubkey = try await signer.pubkey
        XCTAssertEqual(event.pubkey, pubkey)
        XCTAssertTrue(event.tags.contains { $0.count >= 2 && $0[0] == "t" && $0[1] == "test" })
    }
    
    func testEventIdCalculation() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Build an event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Test event ID")
            .build(signer: signer)
        
        // The event ID should be a 64-character hex string
        XCTAssertEqual(event.id.count, 64)
        XCTAssertTrue(event.id.allSatisfy { $0.isHexDigit })
    }
    
    func testEventSignature() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Build an event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Test signature")
            .build(signer: signer)
        
        // The signature should be a 128-character hex string
        XCTAssertEqual(event.sig.count, 128)
        XCTAssertTrue(event.sig.allSatisfy { $0.isHexDigit })
    }
    
    func testReplyEventTags() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Create original event
        let originalEvent = try await NDKEventBuilder()
            .kind(1)
            .content("Original post")
            .build(signer: signer)
        
        // Create reply
        let replyEvent = try await NDKEventBuilder()
            .kind(1)
            .content("This is a reply")
            .tagEvent(originalEvent.id, marker: "reply")
            .tagUser(originalEvent.pubkey)
            .build(signer: signer)
        
        // Verify reply tags
        let eTags = replyEvent.tags.filter { $0.count >= 2 && $0[0] == "e" }
        XCTAssertTrue(eTags.contains { tag in
            tag.count >= 4 &&
            tag[1] == originalEvent.id &&
            tag[3] == "reply"
        })
        
        // Verify p tag for original author
        let pTags = replyEvent.tags.filter { $0.count >= 2 && $0[0] == "p" }
        XCTAssertTrue(pTags.contains { $0[1] == originalEvent.pubkey })
    }
    
    func testReactionEvent() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Create original event
        let originalEvent = try await NDKEventBuilder()
            .kind(1)
            .content("Great post!")
            .build(signer: signer)
        
        // Create reaction
        let reactionEvent = try await NDKEventBuilder.reaction(
            "🔥",
            to: originalEvent
        ).build(signer: signer)
        
        // Verify reaction properties
        XCTAssertEqual(reactionEvent.kind, EventKind.reaction)
        XCTAssertEqual(reactionEvent.content, "🔥")
        
        // Verify tags
        let eTags = reactionEvent.tags.filter { $0.count >= 2 && $0[0] == "e" }
        XCTAssertTrue(eTags.contains { $0[1] == originalEvent.id })
        
        let pTags = reactionEvent.tags.filter { $0.count >= 2 && $0[0] == "p" }
        XCTAssertTrue(pTags.contains { $0[1] == originalEvent.pubkey })
    }
    
    func testDeletionEvent() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Create events to delete
        let event1 = try await NDKEventBuilder()
            .kind(1)
            .content("Delete me 1")
            .build(signer: signer)
        
        let event2 = try await NDKEventBuilder()
            .kind(1)
            .content("Delete me 2")
            .build(signer: signer)
        
        // Create deletion event
        let deletionEvent = try await NDKEventBuilder()
            .kind(EventKind.deletion)
            .content("Deleted for testing")
            .tag(["e", event1.id])
            .tag(["e", event2.id])
            .build(signer: signer)
        
        // Verify deletion event
        XCTAssertEqual(deletionEvent.kind, EventKind.deletion)
        
        let eTags = deletionEvent.tags.filter { $0.count >= 2 && $0[0] == "e" }
        XCTAssertEqual(eTags.count, 2)
        XCTAssertTrue(eTags.contains { $0[1] == event1.id })
        XCTAssertTrue(eTags.contains { $0[1] == event2.id })
    }
    
    func testEventWithMultipleTags() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Build event with multiple tags
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Event with multiple tags")
            .tag(["t", "nostr"])
            .tag(["t", "test"])
            .tag(["r", "https://example.com"])
            .tag(["emoji", "🔥", "fire"])
            .build(signer: signer)
        
        // Verify all tags are present
        let tTags = event.tags.filter { $0.count >= 2 && $0[0] == "t" }
        XCTAssertEqual(tTags.count, 2)
        XCTAssertTrue(tTags.contains { $0[1] == "nostr" })
        XCTAssertTrue(tTags.contains { $0[1] == "test" })
        
        let rTags = event.tags.filter { $0.count >= 2 && $0[0] == "r" }
        XCTAssertEqual(rTags.count, 1)
        XCTAssertEqual(rTags.first?[1], "https://example.com")
        
        let emojiTags = event.tags.filter { $0.count >= 3 && $0[0] == "emoji" }
        XCTAssertEqual(emojiTags.count, 1)
        XCTAssertEqual(emojiTags.first?[1], "🔥")
        XCTAssertEqual(emojiTags.first?[2], "fire")
    }
    
    func testEventTimestamp() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        let beforeTime = Int64(Date().timeIntervalSince1970)
        
        // Build event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Test timestamp")
            .build(signer: signer)
        
        let afterTime = Int64(Date().timeIntervalSince1970)
        
        // Verify timestamp is within expected range
        XCTAssertGreaterThanOrEqual(event.createdAt, beforeTime)
        XCTAssertLessThanOrEqual(event.createdAt, afterTime)
    }
    
    func testEventWithCustomTimestamp() async throws {
        // Create a signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        let customTimestamp: Timestamp = 1700000000
        
        // Build event with custom timestamp
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Custom timestamp")
            .createdAt(customTimestamp)
            .build(signer: signer)
        
        // Verify custom timestamp was used
        XCTAssertEqual(event.createdAt, customTimestamp)
    }
    
    func testEventCacheIntegration() async throws {
        // Create components
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        let cache = SimpleMockCache()
        let ndk = NDK(signer: signer, cache: cache)
        
        // Build event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Test caching")
            .build(signer: signer)
        
        // Even without relays, publishing should cache the event
        do {
            _ = try await ndk.publish(event)
        } catch {
            // Publishing might fail without relays, but caching should still work
        }
        
        // Verify event was cached
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
        XCTAssertEqual(cachedEvent?.id, event.id)
        XCTAssertEqual(cachedEvent?.content, "Test caching")
    }
}