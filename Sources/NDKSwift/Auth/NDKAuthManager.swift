import Foundation
import Observation
import LocalAuthentication

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
///     let authManager = NDKAuthManager.shared
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
    
    // MARK: - Shared Instance
    
    /// Shared authentication manager instance
    public static let shared = NDKAuthManager()
    
    // MARK: - Observable State
    
    /// Currently active session
    public private(set) var activeSession: NDKSession? {
        didSet {
        }
    }
    
    /// All available sessions
    public private(set) var availableSessions: [NDKSession] = [] {
        didSet {
        }
    }
    
    /// Current authentication state
    public private(set) var authenticationState: AuthenticationState = .unauthenticated {
        didSet {
        }
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
    private var ndk: NDK?
    
    /// Session restoration task to prevent multiple concurrent restorations
    private var restorationTask: Task<Void, Never>?
    
    // MARK: - Authentication State
    
    /// Represents the current authentication state
    public enum AuthenticationState: Equatable {
        case unauthenticated
        case authenticating
        case authenticated
        case authenticationFailed(Error)
        case biometricRequired
        case sessionExpired
        
        public static func == (lhs: AuthenticationState, rhs: AuthenticationState) -> Bool {
            switch (lhs, rhs) {
            case (.unauthenticated, .unauthenticated),
                 (.authenticating, .authenticating),
                 (.authenticated, .authenticated),
                 (.biometricRequired, .biometricRequired),
                 (.sessionExpired, .sessionExpired):
                return true
            case (.authenticationFailed, .authenticationFailed):
                return true // Simplified comparison for errors
            default:
                return false
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Whether user is currently authenticated
    public var isAuthenticated: Bool {
        authenticationState == .authenticated && activeSession != nil
    }
    
    /// Whether authentication is in progress
    public var isAuthenticating: Bool {
        authenticationState == .authenticating
    }
    
    /// Whether there are any available sessions
    public var hasSessions: Bool {
        !availableSessions.isEmpty
    }
    
    // MARK: - Initialization
    
    private init() {
        self.keychainManager = NDKKeychainManager()
        self.signerRegistry = NDKSignerRegistry.shared
        
        // Check biometric availability
        updateBiometricAvailability()
        
        // Don't restore session until NDK is set
        // Session restoration will be triggered by setNDK or manually
    }
    
    /// Set the NDK instance for signer operations
    /// - Parameter ndk: The NDK instance to use
    public func setNDK(_ ndk: NDK) {
        self.ndk = ndk
        
        // If we have an active signer, set it on NDK
        if let activeSigner = activeSigner {
            ndk.signer = activeSigner
        }
        
        // Start session restoration now that NDK is available
        if authenticationState == .unauthenticated {
            restoreSession()
        }
    }
    
    // MARK: - Session Management
    
    /// Restore sessions from secure storage
    public func restoreSession() {
        // Cancel any existing restoration task
        restorationTask?.cancel()
        
        restorationTask = Task { @MainActor in
            do {
                authenticationState = .authenticating
                
                // Load all session identifiers
                let sessionIds = try await keychainManager.getAllSessionIdentifiers()
                
                // Load session metadata for each
                var sessions: [NDKSession] = []
                for sessionId in sessionIds {
                    do {
                        let data = try await keychainManager.retrieveSessionMetadata(identifier: sessionId)
                        let session = try JSONDecoder().decode(NDKSession.self, from: data)
                        sessions.append(session)
                    } catch {
                        print("Failed to load session \(sessionId): \(error)")
                        // Clean up corrupted session
                        try? await keychainManager.deleteSessionMetadata(identifier: sessionId)
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
                    authenticationState = .unauthenticated
                }
                
            } catch {
                // Don't show error to user for session restoration failures
                // Just treat it as unauthenticated
                authenticationState = .unauthenticated
            }
        }
    }
    
    /// Restore a specific session as the active session
    /// - Parameter session: The session to restore
    private func restoreActiveSession(_ session: NDKSession) async throws {
        do {
            // Check if biometric authentication is required
            if session.requiresBiometric {
                let biometricSuccess = await authenticateWithBiometrics(reason: "Access your account")
                if !biometricSuccess {
                    authenticationState = .biometricRequired
                    return
                }
            }
            
            // Load the signer data
            let signerData = try await keychainManager.retrieveSignerData(identifier: session.id.uuidString)
            
            // Deserialize the signer
            let signer = try signerRegistry.createSigner(from: signerData, ndk: ndk)
            
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
            authenticationState = .authenticated
            
            // Set signer on NDK if available
            ndk?.signer = signer
            
            // Save updated session metadata
            try await saveSessionMetadata(updatedSession)
            
            print("Session restored for user: \(updatedSession.pubkey)")
        } catch {
            // If we fail to restore a session due to corrupted data, clean it up
            print("Failed to restore session \(session.id): \(error)")
            
            // Remove from available sessions
            availableSessions.removeAll { $0.id == session.id }
            
            // Try to clean up keychain data
            do {
                try await keychainManager.deleteSignerData(identifier: session.id.uuidString)
                try await keychainManager.deleteSessionMetadata(identifier: session.id.uuidString)
                print("Cleaned up corrupted session data for \(session.id)")
            } catch {
                print("Failed to clean up corrupted session: \(error)")
            }
            
            // Re-throw the original error
            throw error
        }
    }
    
    /// Create a new session with a signer
    /// - Parameters:
    ///   - signer: The signer for this session
    ///   - requiresBiometric: Whether biometric auth is required
    ///   - isHardwareBacked: Whether the signer uses secure enclave
    /// - Returns: The created session
    public func createSession(
        with signer: any NDKSigner,
        requiresBiometric: Bool = false,
        isHardwareBacked: Bool = false
    ) async throws -> NDKSession {
        
        // Get pubkey from signer
        let pubkey = try await signer.pubkey
        
        // Create session
        let session = NDKSession(
            pubkey: pubkey,
            signerType: type(of: signer).signerType,
            requiresBiometric: requiresBiometric,
            isHardwareBacked: isHardwareBacked
        )
        
        // Validate session
        try session.validate()
        
        // Serialize signer data
        let signerData = try await signer.serialize()
        
        // Store in keychain
        let biometricRequirement: NDKKeychainManager.BiometricRequirement = requiresBiometric ? .required : .none
        try await keychainManager.storeSignerData(
            identifier: session.id.uuidString,
            data: signerData,
            requiresBiometric: biometricRequirement
        )
        
        // Store session metadata
        try await saveSessionMetadata(session)
        
        // Add to available sessions
        availableSessions.append(session)
        
        return session
    }
    
    /// Switch to a different session
    /// - Parameter session: The session to switch to
    public func switchToSession(_ session: NDKSession) async throws {
        
        guard availableSessions.contains(where: { $0.id == session.id }) else {
            throw NDKAuthError.sessionNotFound
        }
        
        // Set to authenticating first to prevent UI flicker
        authenticationState = .authenticating
        
        // Clear current active state
        activeSigner = nil
        ndk?.signer = nil
        
        // Restore the selected session
        try await restoreActiveSession(session)
    }
    
    /// Delete a session
    /// - Parameter session: The session to delete
    public func deleteSession(_ session: NDKSession) async throws {
        // Remove from available sessions
        availableSessions.removeAll { $0.id == session.id }
        
        // Delete from keychain
        try await keychainManager.deleteSignerData(identifier: session.id.uuidString)
        try await keychainManager.deleteSessionMetadata(identifier: session.id.uuidString)
        
        // If this was the active session, clear it
        if activeSession?.id == session.id {
            logout()
        }
        
        print("Deleted session for user: \(session.pubkey)")
    }
    
    /// Logout from the current session
    public func logout() {
        
        activeSession = nil
        activeSigner = nil
        authenticationState = .unauthenticated
        ndk?.signer = nil
        
        // Mark all sessions as inactive
        availableSessions = availableSessions.map { session in
            var updated = session
            updated.markAsInactive()
            return updated
        }
        
    }
    
    // MARK: - Biometric Authentication
    
    /// Update biometric availability
    private func updateBiometricAvailability() {
        Task { @MainActor in
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
            print("Biometric authentication failed: \(error)")
            return false
        }
    }
    
    // MARK: - Profile Management
    
    /// Update the active session's profile information
    /// - Parameter profile: The profile to update with
    public func updateActiveSessionProfile(_ profile: NDKUserProfile) async throws {
        guard var session = activeSession else {
            throw NDKAuthError.noActiveSession
        }
        
        // Update session with profile data
        session.updateProfile(profile)
        
        // Update in available sessions array
        if let index = availableSessions.firstIndex(where: { $0.id == session.id }) {
            availableSessions[index] = session
        }
        
        // Update active session
        activeSession = session
        
        // Save updated metadata
        try await saveSessionMetadata(session)
        
        print("Updated profile for session: \(session.pubkey)")
    }
    
    // MARK: - Private Helpers
    
    /// Save session metadata to keychain
    /// - Parameter session: The session to save
    private func saveSessionMetadata(_ session: NDKSession) async throws {
        let data = try JSONCoding.encode(session)
        try await keychainManager.storeSessionMetadata(identifier: session.id.uuidString, data: data)
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
    
    public var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session available"
        case .sessionNotFound:
            return "Session not found"
        case .signerCreationFailed(let error):
            return "Failed to create signer: \(error.localizedDescription)"
        case .biometricAuthenticationFailed:
            return "Biometric authentication failed"
        case .keychainError(let error):
            return "Keychain error: \(error.localizedDescription)"
        case .invalidSession:
            return "Invalid session data"
        case .sessionExpired:
            return "Session has expired"
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
        case (.signerCreationFailed(let lhsError), .signerCreationFailed(let rhsError)),
             (.keychainError(let lhsError), .keychainError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}