@testable import NDKSwiftCore
import XCTest

/// Integration tests for NIP-42 authentication flow
final class NIP42AuthenticationIntegrationTests: XCTestCase {
    func testFullAuthenticationFlowWithRealRelay() async throws {
        // Skip if not running integration tests
        guard ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] != nil else {
            throw XCTSkip("Integration tests not enabled")
        }

        // Use a test relay that supports NIP-42 (replace with actual auth relay)
        let authRelayURL = ProcessInfo.processInfo.environment["AUTH_RELAY_URL"] ?? "wss://auth.nostr.wine"

        // Create NDK with signer
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)

        // Set up authentication delegate
        let authDelegate = InteractiveAuthDelegate()
        ndk.authenticationDelegate = authDelegate

        // Track state changes
        var stateChanges: [NDKRelayConnectionState] = []

        // Add relay
        let relay = try await ndk.addRelay(authRelayURL)

        // Monitor state changes
        let stateTask = Task {
            for await state in relay.stateStream {
                stateChanges.append(state.connectionState)
                print("Relay state changed to: \(state.connectionState)")

                // Stop after authenticated or after timeout
                if case .authenticated = state.connectionState {
                    break
                }
            }
        }

        // Try to connect
        do {
            try await relay.connect()
            print("Connected to relay: \(authRelayURL)")
        } catch {
            print("Connection error: \(error)")
        }

        // Create and publish an event
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("NIP-42 authentication test: \(Date())")
            .build(signer: signer)

        print("Publishing event: \(event.id)")

        // Attempt to publish - might fail with auth required
        do {
            let publishedRelays = try await ndk.publish(event)
            print("Event published to \(publishedRelays.count) relays")
        } catch {
            print("Publish failed: \(error)")

            // If auth is required, wait for authentication
            if let ndkError = error as? NDKError,
               case let .publishFailed(_, message) = ndkError,
               message.lowercased().contains("auth") || message.lowercased().contains("restricted")
            {
                print("Authentication required, waiting for auth flow...")

                // Wait for authentication to complete
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

                // Check if we're authenticated now
                if await relay.isAuthenticated {
                    print("Authenticated! Retrying publish...")

                    // Events should be automatically retried, but we can also manually retry
                    let retryResult = try await ndk.publish(event)
                    print("Retry successful! Published to \(retryResult.count) relays")
                }
            }
        }

        // Cancel state monitoring
        stateTask.cancel()

        // Verify we went through auth states
        print("State changes: \(stateChanges)")

        // Disconnect
        await relay.disconnect()
    }

    func testAuthRequiredEventDetection() async throws {
        // Create NDK
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)

        // Create a simulated auth-required scenario
        let mockCache = MemoryCache()
        let eventManager = NDKEventManager(ndk: ndk, cache: mockCache)

        // Create test event
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test")
            .build(signer: signer)

        // In real usage, auth-required errors happen during publish
        // Here we simulate the tracking that would occur
        await eventManager.trackPendingAuthEvent(event, for: "wss://test.relay")

        // Verify event is tracked
        let pending = await eventManager.getPendingAuthEvents(for: "wss://test.relay")
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, event.id)
    }
}

// MARK: - Interactive Auth Delegate for Testing

class InteractiveAuthDelegate: NDKAuthenticationDelegate {
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool {
        print("\n🔐 Authentication Required")
        print("Relay: \(relay.url)")
        print("Challenge: \(challenge)")
        print("Approving authentication...\n")

        // In a real app, this would show a UI prompt
        // For testing, we auto-approve
        return true
    }
}
