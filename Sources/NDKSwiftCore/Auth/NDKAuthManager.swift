import Foundation
import LocalAuthentication
import Observation

/// NDK Authentication Manager using modern @Observable pattern
///
/// Provides comprehensive authentication and session management for NDK applications.
/// Uses iOS 17+ @Observable for reactive state management and integrates with
/// secure storage, biometric authentication, and automatic session restoration.
///
/// ## Key Features
///
/// - **Automatic Session Restoration**: Sessions persist across app launches
/// - **Multi-Account Support**: Manage multiple user sessions seamlessly
/// - **Secure Storage**: Uses iOS Keychain with proper access controls
/// - **Biometric Authentication**: Face ID/Touch ID integration
/// - **Reactive State**: Modern SwiftUI integration with @Observable
///
/// ## Usage
///
/// ```swift
/// @Observable
/// class AppModel {
///     let ndk: NDK
///     let authManager: NDKAuthManager
///
///     init() {
///         self.ndk = NDK(relayUrls: ["wss://relay.damus.io"], cache: MemoryCache())
///         self.authManager = NDKAuthManager(ndk: ndk)
///     }
/// }
///
/// struct ContentView: View {
///     @Environment(AppModel.self) var appModel
///
///     var body: some View {
///         if appModel.authManager.isAuthenticated {
///             MainAppView()
///         } else {
///             LoginView()
///         }
///     }
/// }
/// ```
@Observable
@MainActor
public class NDKAuthManager {
    // MARK: - Properties

    /// The NDK instance this auth manager is managing
    private let ndk: NDK

    // MARK: - Observable State

    /// Currently active session
    public private(set) var activeSession: NDKSession? {
        didSet {}
    }

    /// All available sessions
    public private(set) var availableSessions: [NDKSession] = [] {
        didSet {}
    }

    /// Current session state
    public private(set) var sessionState: SessionState = .noSession {
        didSet {}
    }

    /// Currently active signer (derived from active session)
    public private(set) var activeSigner: (any NDKSigner)?

    /// Whether biometric authentication is available on this device
    public private(set) var biometricAuthAvailable = false

    /// Type of biometric authentication available
    #if !os(watchOS)
        public private(set) var biometricType: LABiometryType = .none
    #endif

    // MARK: - Private Properties

    private let keychainManager: NDKKeychainManager
    private let signerRegistry: NDKSignerRegistry

    /// Session restoration task to prevent multiple concurrent restorations
    private var restorationTask: Task<Void, Never>?

    // MARK: - Session State

    /// Represents the current session state
    public enum SessionState: Equatable {
        case noSession
        case loading
        case active
        case error(Error)
        case biometricRequired

        public static func == (lhs: SessionState, rhs: SessionState) -> Bool {
            switch (lhs, rhs) {
            case (.noSession, .noSession),
                 (.loading, .loading),
                 (.active, .active),
                 (.biometricRequired, .biometricRequired):
                return true
            case (.error, .error):
                return true // Simplified comparison for errors
            default:
                return false
            }
        }
    }

    // MARK: - Computed Properties

    /// Whether there is an active session (read-only or read-write)
    public var hasActiveSession: Bool {
        sessionState == .active && activeSession != nil
    }

    /// Whether the user is authenticated (alias for hasActiveSession)
    public var isAuthenticated: Bool {
        hasActiveSession
    }

    /// Whether the active session can sign events
    public var canSign: Bool {
        guard sessionState == .active,
              let session = activeSession else { return false }
        return session.signerType != nil && activeSigner != nil
    }

    /// The public key of the active session
    public var activePubkey: String? {
        activeSession?.pubkey
    }

    /// Whether session is being loaded
    public var isLoading: Bool {
        sessionState == .loading
    }

    /// Whether there are any available sessions
    public var hasSessions: Bool {
        !availableSessions.isEmpty
    }

    // MARK: - Initialization

    public init(ndk: NDK) {
        self.ndk = ndk
        keychainManager = NDKKeychainManager()
        signerRegistry = NDKSignerRegistry.shared

        // Check biometric availability
        updateBiometricAvailability()
    }

    // MARK: - Session Management

    /// Initialize the authentication manager
    ///
    /// This method should be called early in your app lifecycle (e.g., in your App's .task modifier).
    /// It automatically:
    /// - Loads all saved sessions from the keychain
    /// - Restores the most recent active session
    /// - Handles biometric authentication if required
    /// - Sets up the NDK signer
    ///
    /// ## Usage
    /// ```swift
    /// .task {
    ///     await authManager.initialize()
    /// }
    /// ```
    public func initialize() async {
        await restoreSessions()
    }

    /// Restore all sessions from secure storage
    ///
    /// This method loads all saved sessions and attempts to restore the most recent active session.
    /// Called automatically by `initialize()`.
    public func restoreSessions() async {
        do {
            sessionState = .loading

            // Load all session identifiers
            let sessionIds = try await keychainManager.getAllSessionIdentifiers()

            // Load session metadata for each
            var sessions: [NDKSession] = []
            for sessionId in sessionIds {
                do {
                    let data = try await keychainManager.retrieveSessionMetadata(identifier: sessionId)
                    let session = try JSONCoding.decode(NDKSession.self, from: data)
                    sessions.append(session)
                } catch {
                    NDKLogger.log(.error, category: .auth, "Failed to load session \(sessionId): \(error)")
                    // Clean up corrupted session
                    do {
                        try await keychainManager.deleteSessionMetadata(identifier: sessionId)
                    } catch {
                        NDKLogger.log(.warning, category: .auth, "Failed to delete corrupted session metadata for \(sessionId): \(error.localizedDescription)")
                    }
                }
            }

            availableSessions = sessions.sortedByLastUsed

            // Try to restore the active session
            if let activeSession = sessions.activeSession {
                try await restoreActiveSession(activeSession)
            } else if let mostRecent = sessions.sortedByLastUsed.first {
                // Use most recent session if no active session
                try await restoreActiveSession(mostRecent)
            } else {
                // No sessions available
                sessionState = .noSession
            }

        } catch {
            // Don't show error to user for session restoration failures
            // Just treat it as no session
            sessionState = .noSession
        }
    }

    /// Restore a specific session as the active session
    /// - Parameter session: The session to restore
    private func restoreActiveSession(_ session: NDKSession) async throws {
        // If this session is already active, skip restoration
        if activeSession?.id == session.id, sessionState == .active {
            return
        }

        do {
            // Check if this is a read-only session (no signerType)
            if session.signerType == nil {
                // Read-only session - no signer to restore
                var updatedSession = session
                updatedSession.markAsActive()
                updatedSession.updateLastUsed()

                // Update other sessions to inactive
                availableSessions = availableSessions.map { existingSession in
                    var updated = existingSession
                    if updated.id == session.id {
                        updated = updatedSession
                    } else {
                        updated.markAsInactive()
                    }
                    return updated
                }

                activeSession = updatedSession
                activeSigner = nil
                sessionState = .active

                // Clear signer on NDK for read-only mode
                ndk.signer = nil

                // Save updated session metadata
                try await saveSessionMetadata(updatedSession)

                NDKLogger.log(.info, category: .auth, "Read-only session restored for user: \(updatedSession.pubkey)")
                return
            }

            // Check if biometric authentication is required
            if session.requiresBiometric {
                let biometricSuccess = await authenticateWithBiometrics(reason: "Access your account")
                if !biometricSuccess {
                    sessionState = .biometricRequired
                    return
                }
            }

            // Load the signer data
            let signerData = try await keychainManager.retrieveSignerData(identifier: session.id)

            // Deserialize the signer
            let signer = try await signerRegistry.createSigner(from: signerData, ndk: ndk)

            // Update state
            var updatedSession = session
            updatedSession.markAsActive()
            updatedSession.updateLastUsed()

            // Update other sessions to inactive
            availableSessions = availableSessions.map { existingSession in
                var updated = existingSession
                if updated.id == session.id {
                    updated = updatedSession
                } else {
                    updated.markAsInactive()
                }
                return updated
            }

            activeSession = updatedSession
            activeSigner = signer
            sessionState = .active

            // Set signer on NDK if available
            ndk.signer = signer

            // Don't initialize session data here - let the app call startSession()
            // This avoids duplicate subscriptions

            // Save updated session metadata
            try await saveSessionMetadata(updatedSession)

            NDKLogger.log(.info, category: .auth, "Session restored for user: \(updatedSession.pubkey)")
        } catch let decodingError as DecodingError {
            // Handle corrupted session data specifically
            NDKLogger.log(.error, category: .auth, "Corrupted session data detected for \(session.id): \(decodingError)")

            // Remove from available sessions
            availableSessions.removeAll { $0.id == session.id }

            // Try to clean up keychain data
            do {
                try await keychainManager.deleteSignerData(identifier: session.id)
                try await keychainManager.deleteSessionMetadata(identifier: session.id)
                NDKLogger.log(.info, category: .auth, "Cleaned up corrupted session data for \(session.id)")
            } catch {
                NDKLogger.log(.warning, category: .auth, "Failed to clean up corrupted session: \(error)")
            }

            // Throw specific corrupted session error
            throw NDKAuthError.corruptedSessionData(sessionId: session.id)
        } catch {
            // If we fail to restore a session due to other errors
            NDKLogger.log(.error, category: .auth, "Failed to restore session \(session.id): \(error)")

            // Remove from available sessions
            availableSessions.removeAll { $0.id == session.id }

            // Try to clean up keychain data
            do {
                try await keychainManager.deleteSignerData(identifier: session.id)
                try await keychainManager.deleteSessionMetadata(identifier: session.id)
                NDKLogger.log(.info, category: .auth, "Cleaned up failed session data for \(session.id)")
            } catch {
                NDKLogger.log(.warning, category: .auth, "Failed to clean up failed session: \(error)")
            }

            // Re-throw the original error
            throw error
        }
    }

    /// Add a new session with a signer and make it the active session
    ///
    /// This method handles everything automatically:
    /// - Creates the session
    /// - Stores signer data in keychain
    /// - Starts the NDK session immediately
    /// - Makes it the active session
    ///
    /// - Parameters:
    ///   - signer: The signer for this session
    ///   - requiresBiometric: Whether biometric auth is required for this session
    /// - Returns: The created session
    public func addSession(
        _ signer: any NDKSigner,
        requiresBiometric: Bool = false
    ) async throws -> NDKSession {
        // Get pubkey from signer
        let pubkey = try await signer.pubkey

        // Determine if hardware-backed based on signer type
        // Currently only private key signers with biometric requirement are considered hardware-backed
        let isHardwareBacked = requiresBiometric && signer is NDKPrivateKeySigner

        // Create session
        var session = NDKSession(
            pubkey: pubkey,
            signerType: type(of: signer).signerType,
            requiresBiometric: requiresBiometric,
            isHardwareBacked: isHardwareBacked
        )

        // Mark as active and update last used
        session.markAsActive()
        session.updateLastUsed()

        // Validate session
        try session.validate()

        // Serialize signer data
        let signerData = try await signer.serialize()

        // Store in keychain
        let biometricRequirement: NDKKeychainManager.BiometricRequirement = requiresBiometric ? .required : .none
        try await keychainManager.storeSignerData(
            identifier: session.id,
            data: signerData,
            requiresBiometric: biometricRequirement
        )

        // Store session metadata
        try await saveSessionMetadata(session)

        // Add to available sessions
        availableSessions.append(session)

        // Immediately activate this session to prevent flash of "Welcome Back"
        activeSession = session
        activeSigner = signer
        sessionState = .active

        // Set signer on NDK if available
        ndk.signer = signer

        // Start NDK session in background - don't block login
        Task {
            do {
                _ = try await ndk.startSession(
                    signer: signer,
                    config: NDKSessionConfiguration(
                        dataRequirements: [.followList, .muteList],
                        preloadStrategy: .progressive
                    )
                )
                NDKLogger.log(.info, category: .auth, "NDK session started successfully")
            } catch {
                NDKLogger.log(.warning, category: .auth, "Failed to start NDK session: \(error)")
            }
        }

        return session
    }

    /// Add a read-only session (no signing capabilities)
    /// - Parameter user: The NDKUser to create a read-only session for
    /// - Returns: The created session
    public func addSession(user: NDKUser) async throws -> NDKSession {
        // Create read-only session (no signerType)
        var session = NDKSession(
            pubkey: user.pubkey,
            signerType: nil, // nil indicates read-only
            requiresBiometric: false,
            isHardwareBacked: false
        )

        // Mark as active and update last used
        session.markAsActive()
        session.updateLastUsed()

        // Validate session
        try session.validate()

        // No signer data to store for read-only sessions
        // Just store session metadata
        try await saveSessionMetadata(session)

        // Update other sessions to inactive
        availableSessions = availableSessions.map { existingSession in
            var updated = existingSession
            updated.markAsInactive()
            return updated
        }

        // Add to available sessions
        availableSessions.append(session)

        // Immediately activate this session
        activeSession = session
        activeSigner = nil // No signer for read-only
        sessionState = .active

        // Clear signer on NDK for read-only mode
        ndk.signer = nil

        NDKLogger.log(.info, category: .auth, "Created read-only session for user: \(user.pubkey)")

        return session
    }

    /// Switch to a different session
    /// - Parameter session: The session to switch to
    public func switchToSession(_ session: NDKSession) async throws {
        guard availableSessions.contains(where: { $0.id == session.id }) else {
            throw NDKAuthError.sessionNotFound
        }

        // Only set to loading if we're not already active with this session
        // This prevents UI flicker when switching to a just-created session
        if activeSession?.id != session.id {
            sessionState = .loading

            // Clear current active state
            activeSigner = nil
            ndk.signer = nil
        }

        // Restore the selected session
        try await restoreActiveSession(session)
    }

    /// Remove a session from storage and clear it if active
    /// - Parameter session: The session to remove
    public func removeSession(_ session: NDKSession) async throws {
        // Remove from available sessions
        availableSessions.removeAll { $0.id == session.id }

        // Delete from keychain
        try await keychainManager.deleteSignerData(identifier: session.id)
        try await keychainManager.deleteSessionMetadata(identifier: session.id)

        // If this was the active session, clear it
        if activeSession?.id == session.id {
            logout()
        }

        NDKLogger.log(.info, category: .auth, "Deleted session for user: \(session.pubkey)")
    }

    /// Logout from the current session and remove it from storage
    ///
    /// This method performs a complete logout by:
    /// - Removing the active session from keychain storage
    /// - Clearing all in-memory state for the active session
    /// - Removing the session from available sessions list
    ///
    /// Other sessions remain in storage and can be switched to later.
    ///
    /// - Note: This is an async operation. Use `logoutAsync()` if you need to wait for completion.
    public func logout() {
        guard let session = activeSession else {
            // Already logged out
            activeSession = nil
            activeSigner = nil
            sessionState = .noSession
            ndk.signer = nil
            return
        }

        // Clear state immediately for responsive UI
        activeSession = nil
        activeSigner = nil
        sessionState = .noSession
        ndk.signer = nil

        // Remove from available sessions immediately
        availableSessions.removeAll { $0.id == session.id }

        // Remove from storage in background
        Task {
            do {
                try await keychainManager.deleteSignerData(identifier: session.id)
                try await keychainManager.deleteSessionMetadata(identifier: session.id)
                NDKLogger.log(.info, category: .auth, "Logged out and removed session for user: \(session.pubkey)")
            } catch {
                NDKLogger.log(.error, category: .auth, "Failed to remove session from keychain during logout: \(error)")
            }
        }
    }

    /// Logout from the current session and remove it from storage (async version)
    ///
    /// Same as `logout()` but waits for the keychain deletion to complete.
    /// Use this when you need to ensure the session is fully removed before proceeding.
    public func logoutAsync() async throws {
        guard let session = activeSession else {
            // Already logged out
            activeSession = nil
            activeSigner = nil
            sessionState = .noSession
            ndk.signer = nil
            return
        }

        // Clear state immediately
        activeSession = nil
        activeSigner = nil
        sessionState = .noSession
        ndk.signer = nil

        // Remove from available sessions
        availableSessions.removeAll { $0.id == session.id }

        // Remove from storage and wait
        try await keychainManager.deleteSignerData(identifier: session.id)
        try await keychainManager.deleteSessionMetadata(identifier: session.id)

        NDKLogger.log(.info, category: .auth, "Logged out and removed session for user: \(session.pubkey)")
    }

    /// Remove all sessions from storage and logout
    ///
    /// This method performs a complete cleanup by:
    /// - Deleting all signer data from keychain
    /// - Deleting all session metadata from keychain
    /// - Clearing all in-memory state
    /// - Removing all available sessions
    ///
    /// Use this for complete app reset or when switching between environments.
    public func removeAllSessions() async throws {
        // Delete all sessions from keychain
        for session in availableSessions {
            do {
                try await keychainManager.deleteSignerData(identifier: session.id)
                try await keychainManager.deleteSessionMetadata(identifier: session.id)
            } catch {
                // Log but continue with other deletions
                NDKLogger.log(.error, category: .auth, "Failed to delete session \(session.id): \(error)")
            }
        }

        // Clear all state
        availableSessions = []
        activeSession = nil
        activeSigner = nil
        sessionState = .noSession
        ndk.signer = nil

        NDKLogger.log(.info, category: .auth, "Removed all sessions and logged out")
    }

    /// Clear all sessions from storage and logout
    /// - Note: This is an alias for `removeAllSessions()` for backward compatibility
    public func clearAllSessions() async throws {
        try await removeAllSessions()
    }

    // MARK: - Biometric Authentication

    /// Update biometric availability
    private func updateBiometricAvailability() {
        Task {
            biometricAuthAvailable = await keychainManager.isBiometricAuthenticationAvailable()
            #if !os(watchOS)
                biometricType = await keychainManager.getBiometricType()
            #endif
        }
    }

    /// Authenticate with biometrics
    /// - Parameter reason: Reason for authentication
    /// - Returns: True if authentication succeeded
    private func authenticateWithBiometrics(reason: String) async -> Bool {
        guard biometricAuthAvailable else { return false }

        let context = keychainManager.createAuthenticationContext(reason: reason)

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            NDKLogger.log(.error, category: .auth, "Biometric authentication failed: \(error)")
            return false
        }
    }

    // MARK: - Private Helpers

    /// Save session metadata to keychain
    /// - Parameter session: The session to save
    private func saveSessionMetadata(_ session: NDKSession) async throws {
        let data = try JSONCoding.encode(session)
        try await keychainManager.storeSessionMetadata(identifier: session.id, data: data)
    }
}

// MARK: - Authentication Errors

/// Errors that can occur during authentication operations
public enum NDKAuthError: LocalizedError {
    case noActiveSession
    case sessionNotFound
    case signerCreationFailed(Error)
    case biometricAuthenticationFailed
    case keychainError(Error)
    case invalidSession
    case sessionExpired
    case corruptedSessionData(sessionId: String)

    public var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session available"
        case .sessionNotFound:
            return "Session not found"
        case let .signerCreationFailed(error):
            return "Failed to create signer: \(error.localizedDescription)"
        case .biometricAuthenticationFailed:
            return "Biometric authentication failed"
        case let .keychainError(error):
            return "Keychain error: \(error.localizedDescription)"
        case .invalidSession:
            return "Invalid session data"
        case .sessionExpired:
            return "Session has expired"
        case let .corruptedSessionData(sessionId):
            return "Session data is corrupted for session: \(sessionId)"
        }
    }
}

// MARK: - Equatable conformance for testing

extension NDKAuthError: Equatable {
    public static func == (lhs: NDKAuthError, rhs: NDKAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.noActiveSession, .noActiveSession),
             (.sessionNotFound, .sessionNotFound),
             (.biometricAuthenticationFailed, .biometricAuthenticationFailed),
             (.invalidSession, .invalidSession),
             (.sessionExpired, .sessionExpired):
            return true
        case let (.signerCreationFailed(lhsError), .signerCreationFailed(rhsError)),
             let (.keychainError(lhsError), .keychainError(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case let (.corruptedSessionData(lhsId), .corruptedSessionData(rhsId)):
            return lhsId == rhsId
        default:
            return false
        }
    }
}
