import SwiftUI
import NDKSwift

@MainActor
class AppState: ObservableObject {
    @Published var ndk: NDK?
    @Published var isAuthenticated = false
    @Published var currentUserProfile: NDKUserProfile?
    @Published var currentUser: NDKUser?
    
    // Reactive data sources
    private(set) var profileManager: NDKProfileManager?
    
    // Auth management
    private let authManager = NDKAuthManager.shared
    
    // Default relays
    private let defaultRelays = [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://nos.lol",
        "wss://relay.primal.net",
        "wss://relay.snort.social"
    ]
    
    init() {
        Task {
            await setupNDK()
            await checkExistingSession()
        }
    }
    
    private func setupNDK() async {
        // Initialize with SQLite cache for performance
        let cache = try? await NDKSQLiteCache()
        
        // Create NDK instance
        let ndkInstance = NDK(cache: cache)
        
        // Add relays
        for relay in defaultRelays {
            await ndkInstance.addRelay(relay)
        }
        
        // Connect to relays
        await ndkInstance.connect()
        
        self.ndk = ndkInstance
        
        // Setup profile manager
        self.profileManager = ndkInstance.profileManager
        
        // Note: Zap manager would be initialized here if wallet support is needed
        // Example:
        // let zapManager = NDKZapManager(ndk: ndkInstance)
        // await zapManager.configureDefaults()
        
        // Set NDK for auth manager
        authManager.setNDK(ndkInstance)
    }
    
    private func checkExistingSession() async {
        // Restore sessions from keychain
        authManager.restoreSession()
        
        // Check if we have an active session
        if authManager.isAuthenticated, let session = authManager.activeSession {
            isAuthenticated = true
            currentUser = NDKUser(pubkey: session.pubkey)
            
            // Load current user profile
            await loadCurrentUserProfile(pubkey: session.pubkey)
        }
    }
    
    private func loadCurrentUserProfile(pubkey: String) async {
        guard let profileManager = profileManager else { return }
        
        // Observe profile updates
        Task {
            for await profile in await profileManager.observe(for: pubkey, maxAge: 3600) {
                await MainActor.run {
                    self.currentUserProfile = profile
                }
            }
        }
    }
    
    // MARK: - Authentication Methods
    
    func createAccount(displayName: String) async throws {
        guard let ndk = ndk else { throw OlasError.ndkNotInitialized }
        
        // Generate new key
        let signer = try NDKPrivateKeySigner.generate()
        
        // Create session with biometric protection
        let session = try await authManager.createSession(
            with: signer,
            requiresBiometric: true,
            isHardwareBacked: true
        )
        
        // Switch to session
        try await authManager.switchToSession(session)
        
        // Create profile
        let profile = NDKUserProfile(
            name: displayName.lowercased().replacingOccurrences(of: " ", with: "_"),
            displayName: displayName,
            about: "Visual storyteller on Nostr 📸",
            picture: nil
        )
        
        // Publish profile event
        let profileData = try JSONEncoder().encode(profile)
        let metadataEvent = try await ndk.event()
            .content(String(data: profileData, encoding: .utf8) ?? "{}")
            .kind(EventKind.metadata)
            .build(signer: signer)
        
        _ = try await ndk.publish(metadataEvent)
        
        // Update state
        let pubkey = try await signer.pubkey
        await MainActor.run {
            self.isAuthenticated = true
            self.currentUserProfile = profile
            self.currentUser = NDKUser(pubkey: pubkey)
        }
        
        // Start observing profile
        await loadCurrentUserProfile(pubkey: pubkey)
    }
    
    func login(with nsec: String) async throws {
        guard ndk != nil else { throw OlasError.ndkNotInitialized }
        
        // Create signer from nsec
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        
        // Create session
        let session = try await authManager.createSession(
            with: signer,
            requiresBiometric: true,
            isHardwareBacked: false
        )
        
        // Switch to session
        try await authManager.switchToSession(session)
        
        // Update state
        let pubkey = try await signer.pubkey
        await MainActor.run {
            self.isAuthenticated = true
            self.currentUser = NDKUser(pubkey: pubkey)
        }
        
        // Load profile
        await loadCurrentUserProfile(pubkey: pubkey)
    }
    
    func logout() async {
        authManager.logout()
        await MainActor.run {
            self.isAuthenticated = false
            self.currentUserProfile = nil
            self.currentUser = nil
        }
    }
}

// MARK: - Error Types

enum OlasError: LocalizedError {
    case ndkNotInitialized
    case invalidKey
    case profileCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .ndkNotInitialized:
            return "Network connection not ready. Please try again."
        case .invalidKey:
            return "Invalid private key format."
        case .profileCreationFailed:
            return "Failed to create profile. Please try again."
        }
    }
}