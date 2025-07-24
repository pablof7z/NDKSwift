import SwiftUI
import NDKSwift

@main
struct SocratesApp: App {
    @StateObject private var nostrManager = NostrManager()
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.colorScheme, .dark)
                .preferredColorScheme(.dark)
                .environmentObject(nostrManager)
                .environmentObject(appState)
        }
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: NDKUser?
    
    // Audio state
    @Published var isRecording = false
    @Published var currentlyPlayingId: String?
    @Published var recordingStartTime: Date?
    
    // Signer reference for reactions
    var signer: NDKSigner? {
        nostrManager?.ndk?.signer
    }
    
    // Lazy reference to NostrManager
    private weak var nostrManager: NostrManager?
    
    func setNostrManager(_ manager: NostrManager) {
        self.nostrManager = manager
    }
    
    func reset() {
        isAuthenticated = false
        currentUser = nil
        isRecording = false
        currentlyPlayingId = nil
    }
}

// MARK: - Nostr Manager
@MainActor
class NostrManager: ObservableObject {
    @Published var ndk: NDK?
    
    private var ndkAuthManager: NDKAuthManager
    
    // Recommended relays for Socrates
    let defaultRelays = [
        RelayConstants.primal,
        RelayConstants.damus,
        RelayConstants.nosLol,
        RelayConstants.nostrBand,
        RelayConstants.nostrWine
    ]
    
    // Key for storing user-added relays
    private static let userRelaysKey = "SocratesUserAddedRelays"
    
    init() {
        self.ndkAuthManager = NDKAuthManager.shared
        setupNDK()
    }
    
    private func setupNDK() {
        let allRelays = getAllRelays()
        ndk = NDK(relayUrls: allRelays)
        
        if let ndk = ndk {
            ndkAuthManager.setNDK(ndk)
            
            // Check if there are any existing sessions and restore them
            Task {
                await ndk.connect()
                
                // Try to restore existing session if available
                if !ndkAuthManager.availableSessions.isEmpty {
                    print("Found existing sessions: \(ndkAuthManager.availableSessions.count)")
                    // NDKAuthView will handle automatic session restoration
                }
            }
        }
    }
    
    func login(with signer: NDKSigner) async throws -> NDKSessionData {
        guard let ndk = ndk else { throw NostrError.signerRequired }
        
        // Start session with web of trust and mute list support
        let sessionData = try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList, .muteList, .webOfTrust(depth: 2)],
                preloadStrategy: .progressive
            )
        )
        
        // Create or update session with auth manager for persistence
        if let privateSigner = signer as? NDKPrivateKeySigner {
            _ = try await ndkAuthManager.createSession(
                with: privateSigner,
                requiresBiometric: false,
                isHardwareBacked: false
            )
        }
        
        return sessionData
    }
    
    func logout() {
        Task {
            // Clear all sessions from keychain
            for session in ndkAuthManager.availableSessions {
                try? await ndkAuthManager.deleteSession(session)
            }
        }
        
        // Clear active authentication state
        ndkAuthManager.logout()
        
        // Clear NDK signer
        ndk?.signer = nil
    }
    
    // Check if user is authenticated via NDKAuth
    var isAuthenticated: Bool {
        ndkAuthManager.isAuthenticated
    }
    
    // Get auth manager for use in UI
    var authManager: NDKAuthManager {
        return ndkAuthManager
    }
    
    // MARK: - Relay Management
    
    /// Get all relays (default + user-added)
    private func getAllRelays() -> [String] {
        let userRelays = getUserAddedRelays()
        let allRelays = defaultRelays + userRelays
        return Array(Set(allRelays)) // Remove duplicates
    }
    
    /// Get user-added relays from UserDefaults
    private func getUserAddedRelays() -> [String] {
        return UserDefaults.standard.stringArray(forKey: Self.userRelaysKey) ?? []
    }
    
    /// Add a user relay and persist it
    func addUserRelay(_ relayURL: String) {
        var userRelays = getUserAddedRelays()
        guard !userRelays.contains(relayURL) && !defaultRelays.contains(relayURL) else {
            print("Relay \(relayURL) already exists")
            return
        }
        
        userRelays.append(relayURL)
        UserDefaults.standard.set(userRelays, forKey: Self.userRelaysKey)
        print("Added user relay: \(relayURL)")
    }
    
    /// Remove a user relay and persist the change
    func removeUserRelay(_ relayURL: String) {
        var userRelays = getUserAddedRelays()
        userRelays.removeAll(value: relayURL)
        UserDefaults.standard.set(userRelays, forKey: Self.userRelaysKey)
        print("Removed user relay: \(relayURL)")
    }
    
    /// Get list of user-added relays (for UI display)
    var userAddedRelays: [String] {
        return getUserAddedRelays()
    }
}

// MARK: - Errors
enum NostrError: LocalizedError {
    case signerRequired
    case invalidKey
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .signerRequired:
            return "No signer available"
        case .invalidKey:
            return "Invalid private key"
        case .networkError:
            return "Network connection failed"
        }
    }
}