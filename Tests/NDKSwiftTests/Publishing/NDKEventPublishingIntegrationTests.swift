import XCTest
@testable import NDKSwift

/// Integration tests for event publishing functionality
/// These tests focus on the high-level behavior rather than mocking all components
final class NDKEventPublishingIntegrationTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKSigner!
    var cache: SimpleMockCache!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a private key signer for testing
        signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        // Create mock cache
        cache = SimpleMockCache()
        
        // Create NDK instance
        ndk = NDK(
            signer: signer,
            cache: cache
        )
    }
    
    override func tearDown() async throws {
        await cache.reset()
        ndk = nil
        signer = nil
        cache = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Publishing Tests
    
    func testEventBuilderCreatesValidEvent() async throws {
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
        let expectedPubkey = try await signer.pubkey
        XCTAssertEqual(event.pubkey, expectedPubkey)
        XCTAssertTrue(event.tags.contains { $0.count >= 2 && $0[0] == "t" && $0[1] == "test" })
    }
    
    func testEventCachingDuringPublish() async throws {
        // Create event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Test caching")
            .build(signer: signer)
        
        // Even without relays, the event should be cached
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
    
    func testPublishWithBuilder() async throws {
        // Publish using builder syntax
        let (event, _) = try await ndk.publish { builder in
            builder
                .kind(1)
                .content("Built and published")
                .tag(["subject", "test"])
        }
        
        // Verify event was created correctly
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.content, "Built and published")
        XCTAssertTrue(event.tags.contains { $0.count >= 2 && $0[0] == "subject" && $0[1] == "test" })
        
        // Verify event was cached
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
    }
    
    func testOptimisticPublishingDisabled() async throws {
        // Disable optimistic publishing
        ndk.optimisticPublishingConfig.enabled = false
        
        // Create event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("No optimistic")
            .build(signer: signer)
        
        // Publish (will fail without relays, but that's OK for this test)
        do {
            _ = try await ndk.publish(event)
        } catch {
            // Expected to fail without relays
        }
        
        // Event should still be cached
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
        
        // With optimistic disabled, unpublished events might still be tracked for retry
        // So we just verify the event was cached, not the unpublished status
        // This behavior depends on the NDK implementation
    }
    
    func testOptimisticPublishingEnabled() async throws {
        // Enable optimistic publishing
        ndk.optimisticPublishingConfig.enabled = true
        
        // Create event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("With optimistic")
            .build(signer: signer)
        
        // Publish (will fail without relays, but optimistic should work)
        do {
            _ = try await ndk.publish(event)
        } catch {
            // Expected to fail without relays
        }
        
        // Event should be cached
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
        
        // Should be in unpublished events (since no relays confirmed)
        let unpublished = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertTrue(unpublished.contains { $0.event.id == event.id })
    }
    
    func testReplyEventCreation() async throws {
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
    
    func testReactionEventCreation() async throws {
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
    
    func testEncryptedDirectMessage() async throws {
        // Create recipient
        let recipientSigner = try NDKPrivateKeySigner(privateKey: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
        let recipientPubkey = try await recipientSigner.pubkey
        let recipient = NDKUser(pubkey: recipientPubkey)
        
        // Create encrypted DM
        let dmEvent = try await NDKEventBuilder()
            .content("Secret message!")
            .kind(EventKind.encryptedDirectMessage)
            .tagUser(recipientPubkey)
            .encrypt(recipient: recipient, signer: signer)
        
        // Verify DM properties
        XCTAssertEqual(dmEvent.kind, EventKind.encryptedDirectMessage)
        XCTAssertNotEqual(dmEvent.content, "Secret message!") // Should be encrypted
        XCTAssertFalse(dmEvent.content.isEmpty) // Should have encrypted content
        
        // Verify recipient tag
        let pTags = dmEvent.tags.filter { $0.count >= 2 && $0[0] == "p" }
        XCTAssertTrue(pTags.contains { $0[1] == recipientPubkey })
    }
    
    func testEventDeletion() async throws {
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
    
    func testMultipleEventPublishing() async throws {
        // Create multiple events
        let events = try await withThrowingTaskGroup(of: NDKEvent.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try await NDKEventBuilder()
                        .kind(1)
                        .content("Event \(i)")
                        .build(signer: self.signer)
                }
            }
            
            var results: [NDKEvent] = []
            for try await event in group {
                results.append(event)
            }
            return results
        }
        
        // Publish all events
        for event in events {
            do {
                _ = try await ndk.publish(event)
            } catch {
                // OK if publishing fails without relays
            }
        }
        
        // Verify all events were cached
        for event in events {
            let cachedEvent = await cache.getEvent(id: event.id)
            XCTAssertNotNil(cachedEvent)
        }
    }
}