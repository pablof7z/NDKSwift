import XCTest
@testable import NDKSwift

/// Minimal test to verify event publishing test infrastructure
final class MinimalEventPublishingTest: XCTestCase {
    
    func testMockRelayBehavior() async throws {
        // Test MockRelay functionality
        let relay = MockRelay(url: "wss://test.relay.com")
        
        // Create a test event
        let event = NDKEvent(
            id: "test123",
            pubkey: "pubkey123",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Test event",
            sig: "sig123"
        )
        
        // Test successful publish
        let (success, message) = try await relay.publish(event)
        XCTAssertTrue(success)
        XCTAssertNil(message)
        XCTAssertEqual(relay.publishedEvents.count, 1)
        XCTAssertEqual(relay.publishedEvents.first?.id, "test123")
        
        // Test failed publish
        relay.shouldFailPublish = true
        do {
            _ = try await relay.publish(event)
            XCTFail("Expected publish to throw error")
        } catch NDKError.relayError(let relayUrl, let message) {
            XCTAssertEqual(relayUrl, "wss://test.relay.com")
            XCTAssertEqual(message, "Mock relay publish failure")
        }
    }
    
    func testSimpleMockCacheBehavior() async throws {
        // Test SimpleMockCache functionality
        let cache = SimpleMockCache()
        
        // Create test event
        let event = NDKEvent(
            id: "cache123",
            pubkey: "pubkey123",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Cached event",
            sig: "sig123"
        )
        
        // Save event
        try await cache.saveEvent(event)
        
        // Retrieve event
        let retrieved = await cache.getEvent(id: "cache123")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.content, "Cached event")
        
        // Test query
        let filter = NDKFilter(ids: ["cache123"])
        let results = try await cache.queryEvents(filter)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "cache123")
    }
    
    func testEventBuilderBasics() async throws {
        // Test that we can create a simple signer
        let privateKey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Test pubkey generation
        let pubkey = try await signer.pubkey
        XCTAssertFalse(pubkey.isEmpty)
        XCTAssertEqual(pubkey.count, 64) // Hex pubkey should be 64 chars
    }
}