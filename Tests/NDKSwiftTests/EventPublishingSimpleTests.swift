import XCTest
@testable import NDKSwift

/// Simple tests for event publishing that compile and run independently
final class EventPublishingSimpleTests: XCTestCase {
    
    func testBasicEventCreation() async throws {
        // This test verifies that we can create and sign a basic event
        let privateKey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Build event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Hello, Nostr!")
            .build(signer: signer)
        
        // Verify basic properties
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.content, "Hello, Nostr!")
        XCTAssertFalse(event.id.isEmpty)
        XCTAssertFalse(event.sig.isEmpty)
    }
    
    func testEventPublishingWithCache() async throws {
        // This test verifies that events are cached when published
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        let cache = SimpleMockCache()
        let ndk = NDK(signer: signer, cache: cache)
        
        // Build event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Test caching")
            .build(signer: signer)
        
        // Attempt to publish (will fail without relays but should still cache)
        do {
            _ = try await ndk.publish(event)
        } catch {
            // Expected to fail without relays
        }
        
        // Verify event was cached
        let cachedEvent = await cache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
        XCTAssertEqual(cachedEvent?.content, "Test caching")
    }
    
    func testOptimisticPublishing() async throws {
        // This test verifies optimistic publishing behavior
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        let cache = SimpleMockCache()
        let ndk = NDK(signer: signer, cache: cache)
        
        // Enable optimistic publishing
        ndk.optimisticPublishingConfig.enabled = true
        
        // Build event
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Optimistic test")
            .build(signer: signer)
        
        // Attempt to publish
        do {
            _ = try await ndk.publish(event)
        } catch {
            // Expected to fail without relays
        }
        
        // Check that event is in unpublished cache
        let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        XCTAssertTrue(unpublishedEvents.contains { $0.event.id == event.id })
    }
    
    func testEventWithTags() async throws {
        // This test verifies that tags are properly added to events
        let signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        
        let event = try await NDKEventBuilder()
            .kind(1)
            .content("Event with tags")
            .tag(["t", "nostr"])
            .tag(["t", "test"])
            .tag(["r", "https://example.com"])
            .build(signer: signer)
        
        // Verify tags
        XCTAssertEqual(event.tags.count, 3)
        XCTAssertTrue(event.tags.contains { $0 == ["t", "nostr"] })
        XCTAssertTrue(event.tags.contains { $0 == ["t", "test"] })
        XCTAssertTrue(event.tags.contains { $0 == ["r", "https://example.com"] })
    }
}