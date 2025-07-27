import XCTest
@testable import NDKSwift

/// Tests for NDKEventManager's publish functionality
final class NDKEventManagerTests: NDKTestCase {
    
    var ndk: NDK!
    var eventManager: NDKEventManager!
    var mockCache: MemoryCache!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockCache = createMemoryCache()
        ndk = createTestNDK(cache: mockCache)
        eventManager = ndk.eventManager
    }
    
    override func tearDown() async throws {
        eventManager = nil
        mockCache = nil
        ndk = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Event Publishing Tests
    
    func testPublishSignedEvent() async throws {
        // Create a signed event
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let event = try await ndk.createEvent { builder in
            builder
                .kind(1)
                .content("Test note")
        }
        
        // Since we don't have real relays, the publish will fail
        // but we can verify the event was created correctly
        XCTAssertFalse(event.sig.isEmpty)
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.content, "Test note")
        XCTAssertEqual(event.pubkey, try await signer.pubkey)
    }
    
    func testPublishUnsignedEventFails() async throws {
        // Create unsigned event manually
        let event = EventTestFactory.createEvent(sig: "")
        
        do {
            _ = try await eventManager.publish(event)
            XCTFail("Should have thrown error for unsigned event")
        } catch {
            // Expected error
            XCTAssertTrue(error is NDKError)
        }
    }
    
    func testPublishWithBuilder() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let (event, _) = try await eventManager.publish { builder in
            builder
                .kind(1)
                .content("Built event")
                .tag(["p", TestFixtures.Keys.alice.publicKey])
        }
        
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.content, "Built event")
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.tags[0], ["p", TestFixtures.Keys.alice.publicKey])
    }
    
    // MARK: - Event Caching Tests
    
    func testPublishedEventIsCached() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Add a mock relay so publish succeeds
        let mockRelay = await createTestMockRelay()
        await ndk.pool.addRelay(mockRelay.url)
        
        let event = try await ndk.createEvent { builder in
            builder
                .kind(1)
                .content("Cached event")
        }
        
        // Try to publish (will fail without real relay, but should still cache)
        _ = try? await eventManager.publish(event)
        
        // Event should be in cache
        let cachedEvent = await mockCache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
        XCTAssertEqual(cachedEvent?.id, event.id)
    }
    
    // MARK: - Replaceable Event Tests
    
    func testPublishReplaceableEvent() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        let author = try await signer.pubkey
        
        // Create metadata event (kind 0 - replaceable)
        let metadata1 = try await ndk.createEvent { builder in
            builder
                .kind(0)
                .content("{\"name\":\"Alice\"}")
        }
        
        // Save to cache
        try await mockCache.saveEvent(metadata1)
        
        // Create newer metadata
        let metadata2 = try await ndk.createEvent { builder in
            builder
                .kind(0)
                .content("{\"name\":\"Alice Updated\"}")
        }
        
        // Save newer version
        try await mockCache.saveEvent(metadata2)
        
        // Query for metadata
        let events = try await mockCache.queryEvents(
            NDKFilter(authors: [author], kinds: [0])
        )
        
        // Should have both events in cache (cache doesn't enforce replaceable logic)
        XCTAssertEqual(events.count, 2)
    }
    
    // MARK: - Parameterized Replaceable Event Tests
    
    func testPublishParameterizedReplaceableEvent() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        let author = try await signer.pubkey
        let dTag = "article-123"
        
        // Create article (kind 30023 - parameterized replaceable)
        let article1 = try await ndk.createEvent { builder in
            builder
                .kind(30023)
                .content("Original article")
                .tag(["d", dTag])
        }
        
        try await mockCache.saveEvent(article1)
        
        // Create updated version
        let article2 = try await ndk.createEvent { builder in
            builder
                .kind(30023)
                .content("Updated article")
                .tag(["d", dTag])
        }
        
        try await mockCache.saveEvent(article2)
        
        // Query for articles
        let events = try await mockCache.queryEvents(
            NDKFilter(
                authors: [author],
                kinds: [30023],
                tags: ["d": Set([dTag])]
            )
        )
        
        // Cache stores both versions
        XCTAssertEqual(events.count, 2)
    }
    
    // MARK: - Optimistic Publishing Tests
    
    func testOptimisticPublishing() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let event = try await ndk.createEvent { builder in
            builder
                .kind(1)
                .content("Optimistic event")
        }
        
        // Event should be added to cache immediately for optimistic publishing
        _ = try? await eventManager.publish(event)
        
        // Check if event was added to unpublished events
        let unpublishedEvents = await mockCache.getUnpublishedEvents(maxAge: 60, limit: nil)
        XCTAssertFalse(unpublishedEvents.isEmpty)
    }
    
    func testRetryUnpublishedEvents() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        // Create an event
        let event = try await ndk.createEvent { builder in
            builder
                .kind(1)
                .content("Unpublished event")
        }
        
        // Add to unpublished events
        try await mockCache.addUnpublishedEvent(event, relays: ["wss://relay1.test", "wss://relay2.test"])
        
        // Try to retry (will fail without real relays)
        let results = try await eventManager.retryUnpublishedEvents()
        
        // Should attempt to publish
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].event.id, event.id)
    }
    
    // MARK: - Relay Selection Tests
    
    func testPublishToSpecificRelays() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let event = try await ndk.createEvent { builder in
            builder
                .kind(1)
                .content("Relay-specific event")
        }
        
        let targetRelays: Set<String> = ["wss://specific1.test", "wss://specific2.test"]
        
        // Publish to specific relays (will fail without real relays)
        do {
            _ = try await eventManager.publish(event: event, to: targetRelays)
        } catch {
            // Expected to fail without real relays
        }
        
        // The event should still be cached
        let cachedEvent = await mockCache.getEvent(id: event.id)
        XCTAssertNotNil(cachedEvent)
    }
    
    // MARK: - Error Handling Tests
    
    func testPublishWithoutSigner() async throws {
        // Remove signer
        ndk.signer = nil
        
        do {
            _ = try await eventManager.publish { builder in
                builder.kind(1).content("No signer")
            }
            XCTFail("Should have thrown error without signer")
        } catch {
            // Expected error
            XCTAssertTrue(error is NDKError)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestMockRelay() async -> MockRelay {
        return MockRelay(url: "wss://test.relay")
    }
}