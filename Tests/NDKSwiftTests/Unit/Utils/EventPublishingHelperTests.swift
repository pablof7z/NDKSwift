import XCTest
@testable import NDKSwift

// Mock event type for testing
struct MockPublishableEvent: NDKPublishableEvent {
    let event: NDKEvent
    
    init(event: NDKEvent) {
        self.event = event
    }
}

final class EventPublishingHelperTests: NDKTestCase {
    
    func testCreateAndPublish_successfullyPublishesEvent() async throws {
        // Setup
        let signer = try NDKPrivateKeySigner(privateKey: TestHelpers.generateRandomPrivateKey())
        let ndk = NDK(explicitRelayUrls: ["wss://test.relay.com"], signer: signer)
        
        // Create mock relay
        let mockRelay = MockRelay(url: "wss://test.relay.com")
        mockRelay.connectionState = .connected
        ndk.pool.relays[mockRelay.url] = mockRelay
        
        // Test createAndPublish
        let result = try await EventPublishingHelper.createAndPublish(
            type: MockPublishableEvent.self,
            ndk: ndk,
            logPrefix: "TestEvent"
        ) {
            let event = NDKEvent(
                pubkey: signer.publicKey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: 1,
                tags: [],
                content: "Test content"
            )
            try event.sign(with: signer)
            return MockPublishableEvent(event: event)
        }
        
        // Verify
        XCTAssertEqual(result.event.content, "Test content")
        XCTAssertEqual(result.event.kind, 1)
        XCTAssertNotNil(result.event.signature)
        
        // Verify the event was sent to the relay
        let sentMessages = await mockRelay.getSentMessages()
        XCTAssertEqual(sentMessages.count, 1)
        
        if let message = sentMessages.first,
           case .event(let sentEvent) = message {
            XCTAssertEqual(sentEvent.id, result.event.id)
            XCTAssertEqual(sentEvent.content, "Test content")
        } else {
            XCTFail("Expected event message")
        }
    }
    
    func testCreateAndPublishWithId_logsEventId() async throws {
        // Setup
        let signer = try NDKPrivateKeySigner(privateKey: TestHelpers.generateRandomPrivateKey())
        let ndk = NDK(explicitRelayUrls: ["wss://test.relay.com"], signer: signer)
        
        // Create mock relay
        let mockRelay = MockRelay(url: "wss://test.relay.com")
        mockRelay.connectionState = .connected
        ndk.pool.relays[mockRelay.url] = mockRelay
        
        // Test createAndPublishWithId
        let result = try await EventPublishingHelper.createAndPublishWithId(
            type: MockPublishableEvent.self,
            ndk: ndk,
            logPrefix: "TestEventWithId"
        ) {
            let event = NDKEvent(
                pubkey: signer.publicKey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: 1,
                tags: [],
                content: "Test content with ID logging"
            )
            try event.sign(with: signer)
            return MockPublishableEvent(event: event)
        }
        
        // Verify
        XCTAssertEqual(result.event.content, "Test content with ID logging")
        XCTAssertNotNil(result.event.id)
        XCTAssertFalse(result.event.id.isEmpty)
        
        // Verify the event was sent to the relay
        let sentMessages = await mockRelay.getSentMessages()
        XCTAssertEqual(sentMessages.count, 1)
    }
    
    func testCreateAndPublish_propagatesErrors() async throws {
        // Setup
        let signer = try NDKPrivateKeySigner(privateKey: TestHelpers.generateRandomPrivateKey())
        let ndk = NDK(explicitRelayUrls: ["wss://test.relay.com"], signer: signer)
        
        // No connected relays - publishing should fail
        
        // Test that errors are propagated
        do {
            _ = try await EventPublishingHelper.createAndPublish(
                type: MockPublishableEvent.self,
                ndk: ndk,
                logPrefix: "TestError"
            ) {
                let event = NDKEvent(
                    pubkey: signer.publicKey,
                    createdAt: Timestamp(Date().timeIntervalSince1970),
                    kind: 1,
                    tags: [],
                    content: "This should fail"
                )
                try event.sign(with: signer)
                return MockPublishableEvent(event: event)
            }
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected - publishing should fail with no connected relays
            XCTAssertNotNil(error)
        }
    }
    
    func testCreateAndPublish_handlesMultipleRelays() async throws {
        // Setup
        let signer = try NDKPrivateKeySigner(privateKey: TestHelpers.generateRandomPrivateKey())
        let ndk = NDK(explicitRelayUrls: ["wss://test1.relay.com", "wss://test2.relay.com"], signer: signer)
        
        // Create mock relays
        let mockRelay1 = MockRelay(url: "wss://test1.relay.com")
        mockRelay1.connectionState = .connected
        ndk.pool.relays[mockRelay1.url] = mockRelay1
        
        let mockRelay2 = MockRelay(url: "wss://test2.relay.com")
        mockRelay2.connectionState = .connected
        ndk.pool.relays[mockRelay2.url] = mockRelay2
        
        // Test createAndPublish with multiple relays
        let result = try await EventPublishingHelper.createAndPublish(
            type: MockPublishableEvent.self,
            ndk: ndk,
            logPrefix: "MultiRelayTest"
        ) {
            let event = NDKEvent(
                pubkey: signer.publicKey,
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: 1,
                tags: [],
                content: "Multi-relay test"
            )
            try event.sign(with: signer)
            return MockPublishableEvent(event: event)
        }
        
        // Verify event was sent to both relays
        let sentMessages1 = await mockRelay1.getSentMessages()
        let sentMessages2 = await mockRelay2.getSentMessages()
        
        XCTAssertEqual(sentMessages1.count, 1)
        XCTAssertEqual(sentMessages2.count, 1)
        
        // Verify same event was sent to both
        if let message1 = sentMessages1.first,
           let message2 = sentMessages2.first,
           case .event(let event1) = message1,
           case .event(let event2) = message2 {
            XCTAssertEqual(event1.id, event2.id)
            XCTAssertEqual(event1.id, result.event.id)
        } else {
            XCTFail("Expected event messages")
        }
    }
}