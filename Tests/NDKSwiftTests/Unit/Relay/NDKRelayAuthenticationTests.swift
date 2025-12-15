@testable import NDKSwiftCore
import XCTest

final class NDKRelayAuthenticationTests: XCTestCase {
    var ndk: NDK!
    var mockRelay: NDKRelay!
    var authDelegate: MockAuthenticationDelegate!

    override func setUp() async throws {
        try await super.setUp()
        let signer = try NDKPrivateKeySigner.generate()
        ndk = NDK(signer: signer)
        mockRelay = NDKRelay(url: "wss://auth.relay.test")
        mockRelay.setNDK(ndk)
        authDelegate = MockAuthenticationDelegate()
        ndk.authenticationDelegate = authDelegate
    }

    override func tearDown() async throws {
        ndk = nil
        mockRelay = nil
        authDelegate = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func testRelayAuthenticationStates() async throws {
        // Initial state should be disconnected
        let initialState = await mockRelay.connectionState
        XCTAssertEqual(initialState, .disconnected)

        // Simulate connection
        await mockRelay.updateConnectionState(.connected)
        let connectedState = await mockRelay.connectionState
        XCTAssertEqual(connectedState, .connected)
        let isAuthenticatedAfterConnect = await mockRelay.isAuthenticated
        XCTAssertFalse(isAuthenticatedAfterConnect)

        // Simulate AUTH challenge
        let challenge = "test-challenge-123"
        await mockRelay.updateConnectionState(.authRequired(challenge: challenge))
        let authRequiredState = await mockRelay.connectionState
        XCTAssertEqual(authRequiredState, .authRequired(challenge: challenge))

        // Simulate authenticating
        await mockRelay.updateConnectionState(.authenticating)
        let authenticatingState = await mockRelay.connectionState
        XCTAssertEqual(authenticatingState, .authenticating)

        // Simulate successful authentication
        await mockRelay.updateConnectionState(.authenticated)
        let authenticatedState = await mockRelay.connectionState
        XCTAssertEqual(authenticatedState, .authenticated)
        let isAuthenticatedFinal = await mockRelay.isAuthenticated
        XCTAssertTrue(isAuthenticatedFinal)
        let isConnectedFinal = await mockRelay.isConnected
        XCTAssertTrue(isConnectedFinal)
    }

    func testAuthenticationDelegateFlow() async throws {
        // Set up delegate expectations
        authDelegate.shouldAuthenticate = true

        // Simulate AUTH challenge
        let challenge = "test-challenge-456"
        await ndk.handleAuthChallenge(challenge: challenge, from: mockRelay)

        // Verify delegate was called
        XCTAssertTrue(authDelegate.authRequested)
        XCTAssertEqual(authDelegate.lastChallenge, challenge)
        XCTAssertEqual(authDelegate.lastRelay?.url, mockRelay.url)

        // Verify relay state progression
        let state = await mockRelay.connectionState
        XCTAssertEqual(state, .authenticating)
    }

    func testAuthenticationDelegateDecline() async throws {
        // Set up delegate to decline authentication
        authDelegate.shouldAuthenticate = false

        // Start in connected state
        await mockRelay.updateConnectionState(.connected)

        // Simulate AUTH challenge
        let challenge = "test-challenge-789"
        await ndk.handleAuthChallenge(challenge: challenge, from: mockRelay)

        // Verify delegate was called
        XCTAssertTrue(authDelegate.authRequested)

        // Verify relay state went to authRequired but not authenticating
        let state = await mockRelay.connectionState
        XCTAssertEqual(state, .authRequired(challenge: challenge))
    }

    func testAuthenticationWithoutDelegate() async throws {
        // Remove delegate
        ndk.authenticationDelegate = nil

        // Ensure we have a signer
        XCTAssertNotNil(ndk.signer)

        // Start in connected state
        await mockRelay.updateConnectionState(.connected)

        // Simulate AUTH challenge
        let challenge = "test-challenge-000"
        await ndk.handleAuthChallenge(challenge: challenge, from: mockRelay)

        // Should authenticate by default when signer is present
        let state = await mockRelay.connectionState
        XCTAssertEqual(state, .authenticating)
    }

    func testAuthenticationWithoutSigner() async throws {
        // Remove signer
        ndk.signer = nil
        ndk.authenticationDelegate = nil

        // Start in connected state
        await mockRelay.updateConnectionState(.connected)

        // Simulate AUTH challenge
        let challenge = "test-challenge-111"
        await ndk.handleAuthChallenge(challenge: challenge, from: mockRelay)

        // Should not authenticate without signer
        let state = await mockRelay.connectionState
        XCTAssertEqual(state, .authRequired(challenge: challenge))
    }

    func testRelayStateStream() async throws {
        // Set up expectation for state changes
        var receivedStates: [NDKRelayConnectionState] = []

        let task = Task {
            for await state in mockRelay.stateStream {
                receivedStates.append(state.connectionState)
                if state.connectionState == .authenticated {
                    break
                }
            }
        }

        // Give the stream time to set up
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Progress through states
        await mockRelay.updateConnectionState(.connected)
        await mockRelay.updateConnectionState(.authRequired(challenge: "test"))
        await mockRelay.updateConnectionState(.authenticating)
        await mockRelay.updateConnectionState(.authenticated)

        // Wait for task to complete
        await task.value

        // Verify we received state updates
        XCTAssertTrue(receivedStates.contains(.connected))
        XCTAssertTrue(receivedStates.contains(.authenticated))
    }
}

// MARK: - Mock Authentication Delegate

class MockAuthenticationDelegate: NDKAuthenticationDelegate {
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
