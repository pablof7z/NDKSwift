import XCTest
@testable import NDKSwift

final class NDKPublishingStrategyTests: XCTestCase {
    
    private var ndk: NDK!
    private var publishingStrategy: NDKPublishingStrategy!
    private var mockSigner: NDKPrivateKeySigner!
    private var mockCache: MemoryCache!
    private var mockRelays: [MockOutboxRelay] = []
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock signer
        let privateKey = "test_private_key_123456789012345678901234567890123456789012345678901234"
        mockSigner = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Create memory cache
        mockCache = MemoryCache()
        
        // Create NDK instance
        ndk = NDK(
            explicitRelayUrls: [],
            signer: mockSigner,
            cache: mockCache
        )
        
        // Create mock relays
        for i in 1...3 {
            let relay = MockOutboxRelay(url: "wss://relay\(i).test.com/")
            mockRelays.append(relay)
        }
        
        // Create publishing strategy
        publishingStrategy = NDKPublishingStrategy(ndk: ndk)
    }
    
    override func tearDown() async throws {
        mockRelays.forEach { $0.reset() }
        mockRelays.removeAll()
        publishingStrategy = nil
        ndk = nil
        mockSigner = nil
        mockCache = nil
        try await super.tearDown()
    }
    
    // MARK: - Optimistic Publishing Tests
    
    func testPublishOptimisticallySavesToCache() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent(
            kind: .textNote,
            content: "Test optimistic publishing",
            pubkey: OutboxTestFixtures.alicePubkey
        )
        
        // Sign the event
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: Set(mockRelays.map { $0.url }),
            missingRelayInfoPubkeys: []
        )
        
        // Then - Event should be immediately saved to cache
        let cachedEvents = try await mockCache.queryEvents(NDKFilter(ids: [event.id]))
        XCTAssertEqual(cachedEvents.count, 1)
        XCTAssertEqual(cachedEvents.first?.id, event.id)
        
        // Result should be returned immediately (optimistic)
        XCTAssertNotNil(result)
    }
    
    func testPublishDispatchesToLocalObservers() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent(
            kind: .textNote,
            content: "Test local dispatch"
        )
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        var receivedEvent: NDKEvent?
        let expectation = expectation(description: "Local observer receives event")
        
        // Subscribe to events
        let subscription = ndk.subscribe(
            filter: NDKFilter(kinds: [.textNote], authors: [event.pubkey])
        )
        
        Task {
            for await e in subscription {
                receivedEvent = e
                expectation.fulfill()
                break
            }
        }
        
        // When
        _ = await publishingStrategy.publish(
            event: event,
            to: Set(mockRelays.map { $0.url }),
            missingRelayInfoPubkeys: []
        )
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvent?.id, event.id)
    }
    
    func testPublishResultInitiallyPending() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: Set(mockRelays.map { $0.url }),
            missingRelayInfoPubkeys: []
        )
        
        // Then
        let initialStatus = await result.overallStatus
        XCTAssertTrue(
            initialStatus == .pending || initialStatus == .inProgress,
            "Initial status should be pending or in progress"
        )
    }
    
    // MARK: - Retry Logic Tests
    
    func testRetryOnConnectionFailure() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Configure mock relay to fail first attempt
        mockRelays[0].shouldFailConnection = true
        mockRelays[0].maxRetryAttempts = 2
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: [mockRelays[0].url],
            missingRelayInfoPubkeys: []
        )
        
        // Wait for retries
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Then
        let relayStatuses = await result.relayStatuses
        let status = relayStatuses[mockRelays[0].url]
        
        // Should have attempted multiple times
        XCTAssertNotNil(status)
        if case .failed(let error) = status {
            XCTAssertNotNil(error)
        }
    }
    
    func testRetryOnRateLimiting() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Configure mock relay for rate limiting
        mockRelays[0].rateLimitAfterCount = 0 // Rate limit immediately
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: [mockRelays[0].url],
            missingRelayInfoPubkeys: []
        )
        
        // Wait briefly
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then
        let relayStatuses = await result.relayStatuses
        let status = relayStatuses[mockRelays[0].url]
        
        // Should be rate limited
        if case .rateLimited = status {
            XCTAssertTrue(true, "Relay should be rate limited")
        } else {
            XCTFail("Expected rate limited status")
        }
    }
    
    func testRetryOnAuthFailure() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Configure mock relay for auth challenge
        mockRelays[0].shouldAuthChallenge = true
        mockRelays[0].simulateConnectionState(.connected)
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: [mockRelays[0].url],
            missingRelayInfoPubkeys: []
        )
        
        // Wait for auth attempt
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then
        XCTAssertGreaterThan(mockRelays[0].authAttempts, 0, "Should attempt authentication")
    }
    
    func testMaxRetriesLimit() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Configure mock relay to always fail
        mockRelays[0].shouldRejectEvents = true
        mockRelays[0].rejectReason = "Always fails"
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: [mockRelays[0].url],
            missingRelayInfoPubkeys: [],
            maxRetries: 2
        )
        
        // Wait for retries
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Then
        let status = await result.overallStatus
        XCTAssertEqual(status, .failed, "Should fail after max retries")
        
        let publishCount = mockRelays[0].getPublishedCount(for: event.pubkey)
        XCTAssertLessThanOrEqual(publishCount, 3, "Should not exceed max retries + 1")
    }
    
    // MARK: - Relay Discovery Integration Tests
    
    func testTriggersDiscoveryForMissingRelayInfo() async throws {
        // Given
        let event = OutboxTestFixtures.makeEventWithPTags(
            author: OutboxTestFixtures.alicePubkey,
            pTaggedUsers: [OutboxTestFixtures.bobPubkey, OutboxTestFixtures.charliePubkey]
        )
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        var discoveryTriggered = false
        let expectation = expectation(description: "Discovery triggered")
        
        // Subscribe to discovery events
        let cancellable = await ndk.outbox.relayDiscoveryEvents.sink { discoveryEvent in
            if discoveryEvent.pubkeys.contains(OutboxTestFixtures.bobPubkey) ||
               discoveryEvent.pubkeys.contains(OutboxTestFixtures.charliePubkey) {
                discoveryTriggered = true
                expectation.fulfill()
            }
        }
        
        // When
        _ = await publishingStrategy.publish(
            event: event,
            to: Set(mockRelays.map { $0.url }),
            missingRelayInfoPubkeys: [OutboxTestFixtures.bobPubkey, OutboxTestFixtures.charliePubkey]
        )
        
        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(discoveryTriggered)
        
        cancellable.cancel()
    }
    
    func testRepublishesToNewlyDiscoveredRelays() async throws {
        // Given
        let event = OutboxTestFixtures.makeEventWithPTags(
            author: OutboxTestFixtures.alicePubkey,
            pTaggedUsers: [OutboxTestFixtures.bobPubkey]
        )
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Create new mock relay for discovery
        let newRelay = MockOutboxRelay(url: "wss://newly-discovered.test.com/")
        
        // When - Initial publish
        let result = await publishingStrategy.publish(
            event: event,
            to: Set(mockRelays.map { $0.url }),
            missingRelayInfoPubkeys: [OutboxTestFixtures.bobPubkey],
            republishOnRelayDiscovery: true
        )
        
        // Simulate relay discovery
        await ndk.outbox.trackUser(
            pubkey: OutboxTestFixtures.bobPubkey,
            readRelays: [newRelay.url],
            writeRelays: [],
            source: "wss://discovery.test.com/",
            emitDiscoveryEvent: true
        )
        
        // Wait for republish
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then - Check if event was republished to new relay
        let relayStatuses = await result.relayStatuses
        XCTAssertTrue(relayStatuses.keys.contains(newRelay.url) || newRelay.publishedEvents.contains(where: { $0.id == event.id }))
    }
    
    // MARK: - Cancel Publish Tests
    
    func testCancelPublish() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Configure relay with delay
        mockRelays[0].responseDelay = 2.0 // 2 second delay
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: [mockRelays[0].url],
            missingRelayInfoPubkeys: []
        )
        
        // Cancel after short delay
        Task {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await result.cancel()
        }
        
        // Wait for cancellation
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then
        let status = await result.overallStatus
        XCTAssertEqual(status, .cancelled)
    }
    
    // MARK: - Get Publish Result Tests
    
    func testGetPublishResultAccuracy() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Configure relays: one success, one failure, one rate limited
        mockRelays[0].shouldFailConnection = false
        mockRelays[1].shouldRejectEvents = true
        mockRelays[2].rateLimitAfterCount = 0
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: Set(mockRelays.map { $0.url }),
            missingRelayInfoPubkeys: []
        )
        
        // Wait for publishing
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then
        let publishResult = await publishingStrategy.getPublishResult(for: event.id)
        XCTAssertNotNil(publishResult)
        
        let successCount = await publishResult?.successCount ?? 0
        let failureCount = await publishResult?.failureCount ?? 0
        
        XCTAssertGreaterThanOrEqual(successCount, 1)
        XCTAssertGreaterThanOrEqual(failureCount, 1)
    }
    
    // MARK: - Retry Unpublished Events Tests
    
    func testRetryUnpublishedEvents() async throws {
        // Given - Add unpublished event to cache
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Save as unpublished
        try await mockCache.saveEvent(event, optimistic: true)
        
        // When
        await publishingStrategy.retryUnpublishedEvents()
        
        // Wait for retry
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then - Event should be published
        let published = mockRelays.contains { relay in
            relay.publishedEvents.contains { $0.id == event.id }
        }
        XCTAssertTrue(published, "Unpublished event should be retried")
    }
    
    // MARK: - Auth Challenge Handling Tests
    
    func testHandleAuthChallengeWithDelegate() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // Configure mock relay for auth
        mockRelays[0].shouldAuthChallenge = true
        
        // Set up auth delegate
        class TestAuthDelegate: NDKAuthenticationDelegate {
            var authRequested = false
            
            func ndk(_ ndk: NDK, didReceiveAuthenticationChallenge challenge: String, from relay: NDKRelay) async -> NDKEvent? {
                authRequested = true
                // Return mock auth event
                return OutboxTestFixtures.makeEvent(kind: .auth)
            }
        }
        
        let authDelegate = TestAuthDelegate()
        ndk.authenticationDelegate = authDelegate
        
        // When
        let result = await publishingStrategy.publish(
            event: event,
            to: [mockRelays[0].url],
            missingRelayInfoPubkeys: []
        )
        
        // Wait for auth
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then
        XCTAssertTrue(authDelegate.authRequested, "Auth delegate should be called")
        XCTAssertGreaterThan(mockRelays[0].authAttempts, 0)
    }
    
    // MARK: - Edge Cases Tests
    
    func testPublishToNoRelays() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // When - Publish to empty relay set
        let result = await publishingStrategy.publish(
            event: event,
            to: [],
            missingRelayInfoPubkeys: []
        )
        
        // Then
        let status = await result.overallStatus
        XCTAssertEqual(status, .succeeded, "Should succeed with no relays (nothing to do)")
    }
    
    func testConcurrentPublishOfSameEvent() async throws {
        // Given
        let event = OutboxTestFixtures.makeEvent()
        event.id = event.calculateEventId()
        event.sig = "mock_signature"
        
        // When - Publish same event concurrently
        async let result1 = publishingStrategy.publish(
            event: event,
            to: Set(mockRelays.map { $0.url }),
            missingRelayInfoPubkeys: []
        )
        
        async let result2 = publishingStrategy.publish(
            event: event,
            to: Set(mockRelays.map { $0.url }),
            missingRelayInfoPubkeys: []
        )
        
        let results = await [result1, result2]
        
        // Then - Both should succeed (deduplication)
        for result in results {
            let status = await result.overallStatus
            XCTAssertTrue(
                status == .succeeded || status == .inProgress,
                "Concurrent publishes should be handled gracefully"
            )
        }
    }
}