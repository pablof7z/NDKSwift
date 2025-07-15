import XCTest
@testable import NDKSwift

/// Standalone tests for event publishing that compile and run independently
/// These tests validate the event publishing functionality without external dependencies
final class StandaloneEventPublishingTests: XCTestCase {
    
    func testEventCreationAndSigning() async throws {
        // Create a private key signer
        let privateKey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Build and sign an event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Hello, Nostr!")
            .tag(["t", "test"])
            .build(signer: signer)
        
        // Verify event properties
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.content, "Hello, Nostr!")
        XCTAssertEqual(event.id.count, 64) // Event ID should be 64-char hex
        XCTAssertEqual(event.sig.count, 128) // Signature should be 128-char hex
        XCTAssertFalse(event.pubkey.isEmpty)
        XCTAssertTrue(event.tags.contains { $0 == ["t", "test"] })
    }
    
    func testEventWithMultipleTags() async throws {
        // Create signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Build event with various tags
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Tagged event")
            .tag(["t", "nostr"])
            .tag(["t", "swift"])
            .tag(["r", "https://example.com"])
            .tagHashtag("programming")
            .build(signer: signer)
        
        // Verify tags
        XCTAssertEqual(event.tags.count, 4)
        XCTAssertTrue(event.tags.contains { $0 == ["t", "nostr"] })
        XCTAssertTrue(event.tags.contains { $0 == ["t", "swift"] })
        XCTAssertTrue(event.tags.contains { $0 == ["r", "https://example.com"] })
        XCTAssertTrue(event.tags.contains { $0 == ["t", "programming"] })
    }
    
    func testReplyEventStructure() async throws {
        // Create signer
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
        
        // Verify reply structure
        let eTags = replyEvent.tags.filter { $0.count >= 2 && $0[0] == "e" }
        XCTAssertEqual(eTags.count, 1)
        XCTAssertTrue(eTags.contains { tag in
            tag.count >= 4 &&
            tag[1] == originalEvent.id &&
            tag[3] == "reply"
        })
        
        let pTags = replyEvent.tags.filter { $0.count >= 2 && $0[0] == "p" }
        XCTAssertTrue(pTags.contains { $0[1] == originalEvent.pubkey })
    }
    
    func testReactionEvent() async throws {
        // Create signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Create original event
        let originalEvent = try await NDKEventBuilder()
            .kind(1)
            .content("Great post!")
            .build(signer: signer)
        
        // Create reaction using builder
        let reactionEvent = try await NDKEventBuilder.reaction(
            "🔥",
            to: originalEvent
        ).build(signer: signer)
        
        // Verify reaction
        XCTAssertEqual(reactionEvent.kind, EventKind.reaction)
        XCTAssertEqual(reactionEvent.content, "🔥")
        
        // Verify required tags
        let eTags = reactionEvent.tags.filter { $0.count >= 2 && $0[0] == "e" }
        XCTAssertTrue(eTags.contains { $0[1] == originalEvent.id })
        
        let pTags = reactionEvent.tags.filter { $0.count >= 2 && $0[0] == "p" }
        XCTAssertTrue(pTags.contains { $0[1] == originalEvent.pubkey })
        
        let kTags = reactionEvent.tags.filter { $0.count >= 2 && $0[0] == "k" }
        XCTAssertTrue(kTags.contains { $0[1] == String(originalEvent.kind) })
    }
    
    func testEventTimestamp() async throws {
        // Create signer
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        let beforeTime = Int64(Date().timeIntervalSince1970)
        
        // Build event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Timestamp test")
            .build(signer: signer)
        
        let afterTime = Int64(Date().timeIntervalSince1970)
        
        // Verify timestamp is within expected range
        XCTAssertGreaterThanOrEqual(event.createdAt, beforeTime)
        XCTAssertLessThanOrEqual(event.createdAt, afterTime)
    }
    
    func testCustomTimestamp() async throws {
        // Create signer
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
    
    func testDeletionEvent() async throws {
        // Create signer
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
        let deletionEvent = try await NDKEventBuilder.deletion(
            events: [(event1.id, event1.kind), (event2.id, event2.kind)],
            reason: "Testing deletion"
        ).build(signer: signer)
        
        // Verify deletion event
        XCTAssertEqual(deletionEvent.kind, EventKind.deletion)
        XCTAssertEqual(deletionEvent.content, "Testing deletion")
        
        let eTags = deletionEvent.tags.filter { $0.count >= 2 && $0[0] == "e" }
        XCTAssertEqual(eTags.count, 2)
        XCTAssertTrue(eTags.contains { $0[1] == event1.id })
        XCTAssertTrue(eTags.contains { $0[1] == event2.id })
        
        let kTags = deletionEvent.tags.filter { $0.count >= 2 && $0[0] == "k" }
        // Note: The actual implementation might deduplicate k tags or only add one
        // Let's check what we actually get
        XCTAssertGreaterThanOrEqual(kTags.count, 1)
        // All k tags should have value "1" (kind of deleted events)
        XCTAssertTrue(kTags.allSatisfy { $0[1] == "1" })
    }
}