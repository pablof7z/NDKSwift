import XCTest
@testable import NDKSwift

/// Comprehensive tests for NIP-42 authentication flow including automatic retry
final class NDKRelayAuthenticationFlowTests: XCTestCase {
    var ndk: NDK!
    var mockRelay: MockAuthRelay!
    var authDelegate: TestAuthenticationDelegate!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        try await super.setUp()
        signer = try NDKPrivateKeySigner.generate()
        ndk = NDK(signer: signer)
        authDelegate = TestAuthenticationDelegate()
        ndk.authenticationDelegate = authDelegate
        
        // Create mock relay with auth support
        mockRelay = MockAuthRelay(url: "wss://auth.test.relay")
        mockRelay.ndk = ndk
    }
    
    override func tearDown() async throws {
        ndk = nil
        mockRelay = nil
        authDelegate = nil
        signer = nil
        try await super.tearDown()
    }
    
    // MARK: - Auth Flow Tests
    
    func testAuthChallengeTriggersStateTransition() async throws {
        // Connect relay
        await mockRelay.simulateConnect()
        let connectedState = mockRelay.connectionState
        XCTAssertEqual(connectedState, .connected)
        
        // Simulate AUTH challenge
        let challenge = "test-challenge-xyz"
        await mockRelay.simulateAuthChallenge(challenge: challenge)
        
        // Verify state transition
        let authRequiredState = mockRelay.connectionState
        XCTAssertEqual(authRequiredState, .authRequired(challenge: challenge))
        
        // Verify delegate was called
        XCTAssertTrue(authDelegate.authRequested)
        XCTAssertEqual(authDelegate.lastChallenge, challenge)
    }
    
    func testPublishFailureWithAuthRequiredTriggersRetry() async throws {
        // Set delegate to approve authentication
        authDelegate.shouldAuthenticate = true
        
        // Connect relay
        await mockRelay.simulateConnect()
        
        // Create test event
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test note requiring auth")
            .build(signer: signer)
        
        // Configure relay to reject with auth-required error
        mockRelay.shouldRejectWithAuthRequired = true
        
        // Track publish attempts
        var publishAttempts = 0
        mockRelay.onPublishAttempt = { _ in
            publishAttempts += 1
        }
        
        // Try to publish - should fail with auth required
        do {
            _ = try await ndk.publish(event, to: [mockRelay.url])
            XCTFail("Expected publish to fail with auth required")
        } catch {
            // Expected failure
            print("Initial publish failed as expected: \(error)")
        }
        
        // Verify event was tracked for retry
        let pendingEvents = await ndk.eventManager.getPendingAuthEvents(for: mockRelay.url)
        XCTAssertEqual(pendingEvents.count, 1)
        XCTAssertEqual(pendingEvents.first?.id, event.id)
        
        // Simulate AUTH challenge from relay
        let challenge = "auth-challenge-123"
        await mockRelay.simulateAuthChallenge(challenge: challenge)
        
        // Wait for auth flow to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify authentication was attempted
        XCTAssertTrue(authDelegate.authRequested)
        let state = mockRelay.connectionState
        XCTAssertEqual(state, .authenticating)
        
        // Simulate successful authentication
        mockRelay.shouldRejectWithAuthRequired = false
        await mockRelay.simulateAuthSuccess()
        
        // Wait for retry to happen
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify event was retried and succeeded
        XCTAssertGreaterThanOrEqual(publishAttempts, 2, "Event should have been retried after authentication")
        
        // Verify no more pending events
        let remainingPending = await ndk.eventManager.getPendingAuthEvents(for: mockRelay.url)
        XCTAssertEqual(remainingPending.count, 0, "Pending events should be cleared after retry")
    }
    
    func testMultipleEventsRetryAfterAuthentication() async throws {
        authDelegate.shouldAuthenticate = true
        await mockRelay.simulateConnect()
        
        // Create multiple events
        let events = try await withThrowingTaskGroup(of: NDKEvent.self) { group in
            for i in 0..<3 {
                group.addTask {
                    try await NDKEventBuilder(ndk: self.ndk)
                        .kind(1)
                        .content("Test note \(i)")
                        .build(signer: self.signer)
                }
            }
            
            var results: [NDKEvent] = []
            for try await event in group {
                results.append(event)
            }
            return results
        }
        
        // Configure relay to require auth
        mockRelay.shouldRejectWithAuthRequired = true
        
        // Try to publish all events - all should fail
        for event in events {
            do {
                _ = try await ndk.publish(event, to: [mockRelay.url])
            } catch {
                // Expected
            }
        }
        
        // Verify all events are pending
        let pendingEvents = await ndk.eventManager.getPendingAuthEvents(for: mockRelay.url)
        XCTAssertEqual(pendingEvents.count, 3)
        
        // Trigger authentication flow
        await mockRelay.simulateAuthChallenge(challenge: "bulk-auth-test")
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Complete authentication
        mockRelay.shouldRejectWithAuthRequired = false
        await mockRelay.simulateAuthSuccess()
        
        // Wait for retries
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Verify all events were retried
        let publishedEvents = mockRelay.publishedEvents
        XCTAssertEqual(publishedEvents.count, 3, "All events should have been published after auth")
        
        // Verify no pending events remain
        let remaining = await ndk.eventManager.getPendingAuthEvents(for: mockRelay.url)
        XCTAssertEqual(remaining.count, 0)
    }
    
    func testAuthenticationDeclinedDoesNotRetry() async throws {
        // Set delegate to decline authentication
        authDelegate.shouldAuthenticate = false
        
        await mockRelay.simulateConnect()
        
        // Create test event
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test note")
            .build(signer: signer)
        
        // Configure relay to require auth
        mockRelay.shouldRejectWithAuthRequired = true
        
        // Try to publish
        do {
            _ = try await ndk.publish(event, to: [mockRelay.url])
        } catch {
            // Expected
        }
        
        // Trigger AUTH challenge
        await mockRelay.simulateAuthChallenge(challenge: "declined-auth-test")
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Verify delegate was called but auth was declined
        XCTAssertTrue(authDelegate.authRequested)
        let currentState = mockRelay.connectionState
        if case .authRequired(let challenge) = currentState {
            XCTAssertEqual(challenge, "declined-auth-test")
        } else {
            XCTFail("Expected authRequired state, got \(currentState)")
        }
        
        // Event should still be pending since auth was declined
        let pendingEvents = await ndk.eventManager.getPendingAuthEvents(for: mockRelay.url)
        XCTAssertEqual(pendingEvents.count, 1)
    }
    
    func testRelayStateStreamNotifiesAuthenticationChanges() async throws {
        var receivedStates: [NDKRelayConnectionState] = []
        
        let stateTask = Task {
            for await state in mockRelay.stateStream {
                receivedStates.append(state)
                if case .authenticated = state {
                    break
                }
            }
        }
        
        // Simulate connection flow
        await mockRelay.simulateConnect()
        await mockRelay.simulateAuthChallenge(challenge: "stream-test")
        mockRelay.updateConnectionState(.authenticating)
        await mockRelay.simulateAuthSuccess()
        
        await stateTask.value
        
        // Verify we received all state transitions
        XCTAssertTrue(receivedStates.contains(.connected))
        XCTAssertTrue(receivedStates.contains { state in
            if case .authRequired = state { return true }
            return false
        })
        XCTAssertTrue(receivedStates.contains(.authenticating))
        XCTAssertTrue(receivedStates.contains(.authenticated))
    }
}

// MARK: - Mock Auth Relay

class MockAuthRelay: MockRelayProtocol, @unchecked Sendable {
    var shouldRejectWithAuthRequired = false
    var onPublishAttempt: ((NDKEvent) -> Void)?
    
    override func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?) {
        onPublishAttempt?(event)
        
        if shouldRejectWithAuthRequired {
            throw NDKError.publishFailed(
                relay: url,
                message: "error: restricted: authentication required"
            )
        }
        
        // Track published event
        return (success: true, message: nil)
    }
    
    func simulateConnect() async {
        await connect()
    }
    
    func simulateAuthChallenge(challenge: String) async {
        updateConnectionState(.authRequired(challenge: challenge))
        if let ndk = ndk, let authDelegate = ndk.authenticationDelegate {
            // Cast self to NDKRelay since delegate expects NDKRelay type
            if let relay = await ndk.pool?.relays.first(where: { $0.url == self.url }) {
                let shouldAuth = await authDelegate.relay(relay, requiresAuthenticationWithChallenge: challenge)
                if shouldAuth {
                    updateConnectionState(.authenticating)
                }
            }
        }
    }
    
    func simulateAuthSuccess() async {
        updateConnectionState(.authenticated)
        // Trigger retry of pending events
        // TODO: retryPendingAuthEvents method is not available in NDKEventManager
        // if let ndk = ndk {
        //     await ndk.eventManager.retryPendingAuthEvents(for: url)
        // }
    }
}

// MARK: - Test Authentication Delegate

class TestAuthenticationDelegate: NDKAuthenticationDelegate {
    var shouldAuthenticate = true
    var authRequested = false
    var lastChallenge: String?
    var lastRelay: NDKRelay?
    
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool {
        authRequested = true
        lastChallenge = challenge
        lastRelay = relay
        return shouldAuthenticate
    }
}