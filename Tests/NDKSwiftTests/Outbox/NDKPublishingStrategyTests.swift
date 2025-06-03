import XCTest
@testable import NDKSwift

final class NDKPublishingStrategyTests: XCTestCase {
    var mockNDK: MockNDKForPublishing!
    var tracker: NDKOutboxTracker!
    var ranker: NDKRelayRanker!
    var selector: NDKRelaySelector!
    var strategy: NDKPublishingStrategy!
    
    override func setUp() async throws {
        mockNDK = MockNDKForPublishing()
        tracker = NDKOutboxTracker(ndk: mockNDK)
        ranker = NDKRelayRanker(ndk: mockNDK, tracker: tracker)
        selector = NDKRelaySelector(ndk: mockNDK, tracker: tracker, ranker: ranker)
        strategy = NDKPublishingStrategy(ndk: mockNDK, selector: selector, ranker: ranker)
    }
    
    func testSuccessfulPublish() async throws {
        // Set up relays
        let relay1 = MockRelay(url: "wss://relay1.com", shouldSucceed: true)
        let relay2 = MockRelay(url: "wss://relay2.com", shouldSucceed: true)
        mockNDK.mockRelays = [relay1, relay2]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://relay1.com", "wss://relay2.com"]
        )
        
        // Create and sign event
        let event = NDKEvent(
            id: "test_event_id",
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test note",
            sig: "test_signature"
        )
        
        let config = OutboxPublishConfig(
            minSuccessfulRelays: 1,
            publishInBackground: false
        )
        
        let result = try await strategy.publish(event, config: config)
        
        XCTAssertEqual(result.eventId, "test_event_id")
        XCTAssertEqual(result.overallStatus, .succeeded)
        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.failureCount, 0)
    }
    
    func testPartialFailure() async throws {
        // Set up relays with mixed success
        let relay1 = MockRelay(url: "wss://relay1.com", shouldSucceed: true)
        let relay2 = MockRelay(url: "wss://relay2.com", shouldSucceed: false)
        let relay3 = MockRelay(url: "wss://relay3.com", shouldSucceed: false)
        mockNDK.mockRelays = [relay1, relay2, relay3]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://relay1.com", "wss://relay2.com", "wss://relay3.com"]
        )
        
        let event = createTestEvent()
        
        let config = OutboxPublishConfig(
            minSuccessfulRelays: 1,
            maxRetries: 1
        )
        
        let result = try await strategy.publish(event, config: config)
        
        XCTAssertEqual(result.overallStatus, .succeeded)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertGreaterThan(result.failureCount, 0)
    }
    
    func testCompleteFailure() async throws {
        // All relays fail
        let relay1 = MockRelay(url: "wss://relay1.com", shouldSucceed: false)
        let relay2 = MockRelay(url: "wss://relay2.com", shouldSucceed: false)
        mockNDK.mockRelays = [relay1, relay2]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://relay1.com", "wss://relay2.com"]
        )
        
        let event = createTestEvent()
        
        let config = OutboxPublishConfig(
            minSuccessfulRelays: 2,
            maxRetries: 1
        )
        
        let result = try await strategy.publish(event, config: config)
        
        XCTAssertEqual(result.overallStatus, .failed)
        XCTAssertEqual(result.successCount, 0)
    }
    
    func testRateLimitHandling() async throws {
        let relay = MockRelay(
            url: "wss://relay.com",
            responseType: .rateLimited
        )
        mockNDK.mockRelays = [relay]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://relay.com"]
        )
        
        let event = createTestEvent()
        
        let config = OutboxPublishConfig(
            minSuccessfulRelays: 1,
            maxRetries: 3,
            initialBackoffInterval: 0.01 // 10ms for testing
        )
        
        let result = try await strategy.publish(event, config: config)
        
        // Should have retried
        XCTAssertGreaterThan(relay.publishAttempts, 1)
    }
    
    func testPOWRequirement() async throws {
        let relay = MockRelay(
            url: "wss://relay.com",
            responseType: .requiresPow(difficulty: 10)
        )
        mockNDK.mockRelays = [relay]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://relay.com"]
        )
        
        var event = createTestEvent()
        event.id = nil // Clear ID so it can be regenerated
        event.sig = nil // Clear signature
        
        let config = OutboxPublishConfig(
            minSuccessfulRelays: 1,
            enablePow: true,
            maxPowDifficulty: 20
        )
        
        let result = try await strategy.publish(event, config: config)
        
        // Should have attempted POW
        XCTAssertEqual(result.powDifficulty, 10)
        
        // Relay should have been called multiple times (once for POW check, once after POW)
        XCTAssertGreaterThan(relay.publishAttempts, 1)
    }
    
    func testPOWDisabled() async throws {
        let relay = MockRelay(
            url: "wss://relay.com",
            responseType: .requiresPow(difficulty: 10)
        )
        mockNDK.mockRelays = [relay]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://relay.com"]
        )
        
        let event = createTestEvent()
        
        let config = OutboxPublishConfig(
            minSuccessfulRelays: 1,
            enablePow: false
        )
        
        let result = try await strategy.publish(event, config: config)
        
        // Should fail when POW is disabled
        XCTAssertEqual(result.overallStatus, .failed)
        if case .failed(let reason) = result.relayStatuses["wss://relay.com"] {
            XCTAssertEqual(reason, .powGenerationFailed)
        }
    }
    
    func testCancelPublish() async throws {
        let relay = MockRelay(
            url: "wss://relay.com",
            responseDelay: 1.0 // Slow relay
        )
        mockNDK.mockRelays = [relay]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://relay.com"]
        )
        
        let event = createTestEvent()
        
        // Start publishing in background
        Task {
            _ = try await strategy.publish(event)
        }
        
        // Give it a moment to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Cancel
        await strategy.cancelPublish(eventId: event.id!)
        
        let result = await strategy.getPublishResult(for: event.id!)
        XCTAssertEqual(result.overallStatus, .cancelled)
    }
    
    func testGetPendingItems() async throws {
        let slowRelay = MockRelay(
            url: "wss://slow.relay",
            responseDelay: 2.0
        )
        mockNDK.mockRelays = [slowRelay]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://slow.relay"]
        )
        
        let event = createTestEvent()
        
        // Start publishing in background
        Task {
            _ = try await strategy.publish(event)
        }
        
        // Check pending items
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        let pendingItems = await strategy.getPendingItems()
        
        XCTAssertEqual(pendingItems.count, 1)
        XCTAssertEqual(pendingItems.first?.event.id, event.id)
    }
    
    func testCleanupCompleted() async throws {
        let relay = MockRelay(url: "wss://relay.com", shouldSucceed: true)
        mockNDK.mockRelays = [relay]
        
        await tracker.track(
            pubkey: "test_pubkey",
            writeRelays: ["wss://relay.com"]
        )
        
        // Publish multiple events
        for i in 0..<5 {
            let event = createTestEvent(id: "event_\(i)")
            _ = try await strategy.publish(event)
        }
        
        // Should have 5 completed items
        var allResults: [PublishResult] = []
        for i in 0..<5 {
            let result = await strategy.getPublishResult(for: "event_\(i)")
            allResults.append(result)
        }
        
        XCTAssertEqual(allResults.filter { $0.overallStatus == .succeeded }.count, 5)
        
        // Clean up old items
        await strategy.cleanupCompleted(olderThan: 0) // Clean all
        
        // Should be gone
        let cleanedResult = await strategy.getPublishResult(for: "event_0")
        XCTAssertEqual(cleanedResult.overallStatus, .unknown)
    }
    
    // MARK: - Helper Methods
    
    private func createTestEvent(id: String = "test_event_id") -> NDKEvent {
        return NDKEvent(
            id: id,
            pubkey: "test_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test content",
            sig: "test_signature"
        )
    }
}

// MARK: - Mock Classes

class MockNDKForPublishing: NDK {
    var mockRelays: [MockRelay] = []
    
    override var relayPool: NDKRelayPool {
        return MockRelayPoolForPublishing(mockRelays: mockRelays)
    }
}

class MockRelayPoolForPublishing: NDKRelayPool {
    let mockRelays: [MockRelay]
    
    init(mockRelays: [MockRelay]) {
        self.mockRelays = mockRelays
        super.init()
    }
    
    override func relay(for url: String) -> NDKRelay? {
        return mockRelays.first { $0.url == url }
    }
    
    override func addRelay(url: String) async -> NDKRelay? {
        return mockRelays.first { $0.url == url }
    }
}

enum MockRelayResponse {
    case success
    case requiresPow(difficulty: Int)
    case rateLimited
    case authRequired
    case permanentFailure(String)
}

class MockRelayForPublishing: NDKRelay {
    let shouldSucceed: Bool
    let responseType: MockRelayResponse
    let responseDelay: TimeInterval
    var publishAttempts = 0
    
    init(
        url: String,
        shouldSucceed: Bool = true,
        responseType: MockRelayResponse = .success,
        responseDelay: TimeInterval = 0
    ) {
        self.shouldSucceed = shouldSucceed
        self.responseType = shouldSucceed ? .success : responseType
        self.responseDelay = responseDelay
        super.init(url: url)
    }
    
    override func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?) {
        publishAttempts += 1
        
        // Simulate delay
        if responseDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        
        switch responseType {
        case .success:
            return (true, nil)
        case .requiresPow(let difficulty):
            // If event has POW tag, succeed
            if event.tags.contains(where: { $0.first == "nonce" }) {
                return (true, nil)
            }
            return (false, "pow: difficulty \(difficulty) required")
        case .rateLimited:
            return (false, "rate-limited: too many requests")
        case .authRequired:
            return (false, "auth-required")
        case .permanentFailure(let message):
            return (false, "error: \(message)")
        }
    }
}