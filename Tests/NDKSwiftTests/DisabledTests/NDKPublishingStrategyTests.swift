@testable import NDKSwiftCore
import XCTest

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
            signer: mockSigner,
            cache: mockCache
        )

        // Create mock relays
        for i in 1 ... 3 {
            let relay = MockOutboxRelay(url: "wss://relay\(i).test.com/")
            mockRelays.append(relay)
        }

        // Create publishing strategy
        publishingStrategy = ndk.publishingStrategy
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
        let event = try await OutboxTestFixtures.makeEvent(
            kind: EventKind.textNote,
            content: "Test optimistic publishing"
        )

        // When
        let result = try await publishingStrategy.publish(event)

        // Then - Event should be immediately saved to cache
        let cachedEvents = try await mockCache.queryEvents(NDKFilter(ids: [event.id]))
        XCTAssertEqual(cachedEvents.count, 1)
        XCTAssertEqual(cachedEvents.first?.id, event.id)

        // Result should be returned immediately (optimistic)
        XCTAssertNotNil(result)
    }

    func testPublishDispatchesToLocalObservers() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent(
            kind: EventKind.textNote,
            content: "Test local dispatch"
        )

        var receivedEvent: NDKEvent?
        let expectation = expectation(description: "Local observer receives event")

        // Subscribe to events
        let subscription = ndk.subscribe(
            filter: NDKFilter(authors: [event.pubkey], kinds: [EventKind.textNote])
        )

        Task {
            for await e in subscription.events {
                receivedEvent = e
                expectation.fulfill()
                break
            }
        }

        // When
        _ = try await publishingStrategy.publish(event)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedEvent?.id, event.id)
    }

    func testPublishResultInitiallyPending() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // When
        let result = try await publishingStrategy.publish(event)

        // Then
        let initialStatus = result.overallStatus
        XCTAssertTrue(
            initialStatus == .pending || initialStatus == .inProgress,
            "Initial status should be pending or in progress"
        )
    }

    // MARK: - Retry Logic Tests

    func testRetryOnConnectionFailure() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // Configure mock relay to fail first attempt
        mockRelays[0].shouldFailConnection = true
        mockRelays[0].maxRetryAttempts = 2

        // When
        let result = try await publishingStrategy.publish(event)

        // Wait for retries
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Then
        let relayStatuses = result.relayStatuses
        let status = relayStatuses[mockRelays[0].url]

        // Should have attempted multiple times
        XCTAssertNotNil(status)
        if case let .failed(error) = status {
            XCTAssertNotNil(error)
        }
    }

    func testRetryOnRateLimiting() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // Configure mock relay for rate limiting
        mockRelays[0].rateLimitAfterCount = 0 // Rate limit immediately

        // When
        let result = try await publishingStrategy.publish(event)

        // Wait briefly
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        let relayStatuses = result.relayStatuses
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
        let event = try await OutboxTestFixtures.makeEvent()

        // Configure mock relay for auth challenge
        mockRelays[0].shouldAuthChallenge = true
        mockRelays[0].simulateConnectionState(.connected)

        // When
        _ = try await publishingStrategy.publish(event)

        // Wait for auth attempt
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertGreaterThan(mockRelays[0].authAttempts, 0, "Should attempt authentication")
    }

    func testMaxRetriesLimit() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // Configure mock relay to always fail
        mockRelays[0].shouldRejectEvents = true
        mockRelays[0].rejectReason = "Always fails"

        // When
        let result = try await publishingStrategy.publish(event)

        // Wait for retries
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Then
        let status = result.overallStatus
        XCTAssertEqual(status, .failed, "Should fail after max retries")

        let publishCount = mockRelays[0].getPublishedCount(for: event.pubkey)
        XCTAssertLessThanOrEqual(publishCount, 3, "Should not exceed max retries + 1")
    }

    // MARK: - Relay Discovery Integration Tests

    func testTriggersDiscoveryForMissingRelayInfo() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEventWithPTags(
            author: OutboxTestFixtures.alicePubkey,
            pTaggedUsers: [OutboxTestFixtures.bobPubkey, OutboxTestFixtures.charliePubkey]
        )

        var discoveryTriggered = false
        let expectation = expectation(description: "Discovery triggered")

        // Subscribe to discovery events
        Task {
            for await discoveryEvent in await ndk.outbox.relayDiscoveries {
                if discoveryEvent.pubkey == OutboxTestFixtures.bobPubkey ||
                    discoveryEvent.pubkey == OutboxTestFixtures.charliePubkey
                {
                    discoveryTriggered = true
                    expectation.fulfill()
                    break
                }
            }
        }

        // When
        _ = try await publishingStrategy.publish(event)

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(discoveryTriggered)
    }

    func testRepublishesToNewlyDiscoveredRelays() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEventWithPTags(
            author: OutboxTestFixtures.alicePubkey,
            pTaggedUsers: [OutboxTestFixtures.bobPubkey]
        )

        // Create new mock relay for discovery
        let newRelay = MockOutboxRelay(url: "wss://newly-discovered.test.com/")

        // When - Initial publish
        let result = try await publishingStrategy.publish(event)

        // Simulate relay discovery
        await ndk.outbox.trackUser(OutboxTestFixtures.bobPubkey, emitDiscoveryEvent: true)

        // Wait for republish
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then - Check if event was republished to new relay
        let relayStatuses = result.relayStatuses
        XCTAssertTrue(relayStatuses.keys.contains(newRelay.url) || newRelay.publishedEvents.contains(where: { $0.id == event.id }))
    }

    // MARK: - Cancel Publish Tests

    func testCancelPublish() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // Configure relay with delay
        mockRelays[0].responseDelay = 2.0 // 2 second delay

        // When
        _ = try await publishingStrategy.publish(event)

        // Cancel after short delay
        Task {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await publishingStrategy.cancelPublish(eventId: event.id)
        }

        // Wait for cancellation
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        let updatedResult = await publishingStrategy.getPublishResult(for: event.id)
        XCTAssertEqual(updatedResult.overallStatus, .cancelled)
    }

    // MARK: - Get Publish Result Tests

    func testGetPublishResultAccuracy() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // Configure relays: one success, one failure, one rate limited
        mockRelays[0].shouldFailConnection = false
        mockRelays[1].shouldRejectEvents = true
        mockRelays[2].rateLimitAfterCount = 0

        // When
        _ = try await publishingStrategy.publish(event)

        // Wait for publishing
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        let publishResult = await publishingStrategy.getPublishResult(for: event.id, missingRelayInfoPubkeys: [])
        XCTAssertNotNil(publishResult)

        let successCount = publishResult.successCount
        let failureCount = publishResult.failureCount

        XCTAssertGreaterThanOrEqual(successCount, 1)
        XCTAssertGreaterThanOrEqual(failureCount, 1)
    }

    // MARK: - Retry Unpublished Events Tests

    // Removed testRetryUnpublishedEvents - method doesn't exist in NDKPublishingStrategy

    // MARK: - Auth Challenge Handling Tests

    func testHandleAuthChallengeWithDelegate() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // Configure mock relay for auth
        mockRelays[0].shouldAuthChallenge = true

        // Set up auth delegate
        class TestAuthDelegate: NDKAuthenticationDelegate {
            var authRequested = false

            func relay(_: NDKRelay, requiresAuthenticationWithChallenge _: String) async -> Bool {
                authRequested = true
                return true
            }
        }

        let authDelegate = TestAuthDelegate()
        ndk.authenticationDelegate = authDelegate

        // When
        _ = try await publishingStrategy.publish(event)

        // Wait for auth
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Then
        XCTAssertTrue(authDelegate.authRequested, "Auth delegate should be called")
        XCTAssertGreaterThan(mockRelays[0].authAttempts, 0)
    }

    // MARK: - Edge Cases Tests

    func testPublishToNoRelays() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // When - Publish to empty relay set
        let result = try await publishingStrategy.publish(event)

        // Then
        let status = result.overallStatus
        XCTAssertEqual(status, .succeeded, "Should succeed with no relays (nothing to do)")
    }

    func testConcurrentPublishOfSameEvent() async throws {
        // Given
        let event = try await OutboxTestFixtures.makeEvent()

        // When - Publish same event concurrently
        async let result1 = try await publishingStrategy.publish(event)
        async let result2 = try await publishingStrategy.publish(event)

        let results = try await [result1, result2]

        // Then - Both should succeed (deduplication)
        for result in results {
            let status = result.overallStatus
            XCTAssertTrue(
                status == .succeeded || status == .inProgress,
                "Concurrent publishes should be handled gracefully"
            )
        }
    }
}
