import Foundation
import Observation
import NDKSwiftCore
import NDKSwiftNostrDB

@Observable
@MainActor
public final class ChirpState {
    public private(set) var ndk: NDK
    public private(set) var authManager: NDKAuthManager
    public var initState: InitializationState = .loading

    public enum InitializationState: Equatable {
        case loading
        case error(Error)
        case ready
        case needsLogin

        public static func == (lhs: InitializationState, rhs: InitializationState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading),
                 (.ready, .ready),
                 (.needsLogin, .needsLogin):
                return true
            case (.error, .error):
                return true
            default:
                return false
            }
        }
    }

    internal init(ndk: NDK, authManager: NDKAuthManager) {
        self.ndk = ndk
        self.authManager = authManager
    }

    public static func create() async throws -> ChirpState {
        let cache = try await NDKNostrDBCache(path: nil)

        // Create NDK with cache and no initial relays
        // Relays will be discovered via NIP-65 and configured via outbox
        let ndk = NDK(
            relayURLs: [],
            cache: cache,
            debugMode: true,
            telemetryConfig: TelemetrySettings.makeConfig()
        )

        // Connect to relays (needed for both authenticated and unauthenticated data fetching)
        await ndk.connect()

        // Create managers
        let authManager = NDKAuthManager(ndk: ndk)

        // Initialize auth manager (restore sessions)
        await authManager.initialize()

        // Create state
        let state = ChirpState(ndk: ndk, authManager: authManager)

        // Start session if authenticated
        if authManager.isAuthenticated, let signer = authManager.activeSigner {
            Task {
                do {
                    try await ndk.startSession(
                        signer: signer,
                        config: NDKSessionConfiguration(
                            dataRequirements: [.followList, .muteList],
                            preloadStrategy: .progressive
                        )
                    )
                } catch {
                    // Log but don't fail initialization if session start fails
                    print("Failed to start session: \(error)")
                }
            }
        }

        return state
    }

    public func handleSuccessfulLogin() {
        // Start session if we have a signer
        if let signer = authManager.activeSigner {
            let ndkInstance = ndk
            Task {
                do {
                    try await ndkInstance.startSession(
                        signer: signer,
                        config: NDKSessionConfiguration(
                            dataRequirements: [.followList, .muteList],
                            preloadStrategy: .progressive
                        )
                    )
                } catch {
                    // Log but don't fail if session start fails
                    print("Failed to start session: \(error)")
                }
            }
        }
        initState = .ready
    }

    /// Logout from all accounts and return to welcome screen
    public func logout() async {
        // Remove all sessions (clears keychain, in-memory state, and ndk.signer)
        try? await authManager.removeAllSessions()

        // Return to login screen
        initState = .needsLogin
    }
}
