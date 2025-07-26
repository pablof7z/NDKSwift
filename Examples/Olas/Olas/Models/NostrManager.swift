import Foundation
import NDKSwift
import SwiftUI
import Observation

@MainActor
@Observable
class NostrManager {
    var ndk: NDK?
    var isConnected = false
    var relayStatus: [String: Bool] = [:]
    
    private var ndkAuthManager: NDKAuthManager
    var cache: NDKSQLiteCache?
    
    // Declarative data sources
    private(set) var userProfileDataSource: UserProfileDataSource?
    
    // Current user's profile
    private(set) var currentUserProfile: NDKUserProfile?
    private var profileObservationTask: Task<Void, Never>?
    
    // Default relays for Olas (visual content focused)
    let defaultRelays = [
        RelayConstants.primal,
        RelayConstants.damus,
        RelayConstants.nosLol,
        RelayConstants.nostrWine,
        "wss://relay.nostr.band"
    ]
    
    // Key for storing user-added relays
    private static let userRelaysKey = "OlasUserAddedRelays"
    
    init() {
        print("🎨 [OlasManager] Initializing...")
        self.ndkAuthManager = NDKAuthManager.shared
        Task {
            await setupNDK()
        }
    }
    
    private func setupNDK() async {
        print("🎨 [OlasManager] Setting up NDK...")
        // Initialize SQLite cache for better performance and offline access
        do {
            cache = try await NDKSQLiteCache()
            let allRelays = getAllRelays()
            ndk = NDK(relayUrls: allRelays, cache: cache)
            print("NDK initialized with SQLite cache and \(allRelays.count) relays")
        } catch {
            print("Failed to initialize SQLite cache: \(error). Continuing without cache.")
            let allRelays = getAllRelays()
            ndk = NDK(relayUrls: allRelays)
        }
        
        // Set NDK on auth manager
        if let ndk = ndk {
            print("🎨 [OlasManager] Setting NDK on auth manager")
            ndkAuthManager.setNDK(ndk)
            
            // Configure NIP-89 client tags for Olas
            ndk.clientTagConfig = NDKClientTagConfig(
                name: "Olas",
                relay: RelayConstants.primal,
                autoTag: true,
                excludedKinds: [
                    EventKind.encryptedDirectMessage
                ]
            )
            print("🎨 [OlasManager] Configured NIP-89 client tags")
        }
        
        Task {
            await connectToRelays()
        }
    }
    
    func connectToRelays() async {
        guard let ndk = ndk else { return }
        
        print("OlasManager - Connecting to relays")
        await ndk.connect()
        isConnected = true
        print("OlasManager - Connected to relays")
        
        // Monitor relay status
        await monitorRelayStatus()
    }
    
    private func monitorRelayStatus() async {
        guard let ndk = ndk else { return }
        
        // Monitor relay changes
        let relayChanges = await ndk.relayChanges
        for await change in relayChanges {
            switch change {
            case .relayConnected(let relay):
                relayStatus[relay.url] = true
            case .relayDisconnected(let relay):
                relayStatus[relay.url] = false
            case .relayAdded(let relay):
                relayStatus[relay.url] = false
            case .relayRemoved(let relay):
                relayStatus.removeValue(forKey: relay)
            }
        }
    }
    
    func login(with privateKey: String) async throws {
        guard let ndk = ndk else { throw OlasError.ndkNotInitialized }
        
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Start session with follow list and mute list support
        try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList, .muteList],
                preloadStrategy: .progressive
            )
        )
        
        let publicKey = try await signer.pubkey
        print("Logged in with public key: \(publicKey)")
        
        // Initialize declarative data sources
        await initializeDataSources(for: publicKey)
    }
    
    func createNewAccount(displayName: String, about: String? = nil, picture: String? = nil) async throws -> NDKSession {
        print("🎨 [OlasManager] createNewAccount() called with displayName: \(displayName)")
        
        guard let ndk = ndk else { 
            print("🎨 [OlasManager] ERROR: NDK is not initialized!")
            throw OlasError.ndkNotInitialized 
        }
        
        // Generate new private key
        let signer = try NDKPrivateKeySigner.generate()
        
        // Start session
        print("🎨 [OlasManager] Starting session...")
        try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList, .muteList],
                preloadStrategy: .progressive
            )
        )
        
        // Create auth session for persistence
        let session = try await ndkAuthManager.createSession(
            with: signer,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Create and publish profile
        let metadata = NDKUserProfile(
            name: displayName.lowercased().replacingOccurrences(of: " ", with: "_"),
            displayName: displayName,
            about: about ?? "Visual storyteller on Nostr 📸",
            picture: picture
        )
        
        if ndkAuthManager.isAuthenticated {
            print("🎨 [OlasManager] User is authenticated, publishing metadata...")
            // Create metadata event
            let metadataContent = try JSONCoding.encodeToString(metadata)
            let metadataEvent = try await NDKEventBuilder(ndk: ndk)
                .content(metadataContent)
                .kind(EventKind.metadata)
                .build(signer: signer)
            
            _ = try await ndk.publish(metadataEvent)
            
            // Update session with profile
            try await ndkAuthManager.updateActiveSessionProfile(metadata)
        }
        
        // Initialize declarative data sources
        await initializeDataSources(for: session.pubkey)
        
        print("🎨 [OlasManager] createNewAccount() completed successfully")
        return session
    }
    
    func createAccountFromNsec(_ nsec: String, displayName: String) async throws -> NDKSession {
        print("🎨 [OlasManager] createAccountFromNsec() called")
        guard let ndk = ndk else { throw OlasError.ndkNotInitialized }
        
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        
        // Start session
        try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList, .muteList],
                preloadStrategy: .progressive
            )
        )
        
        // Create auth session for persistence
        let session = try await ndkAuthManager.createSession(
            with: signer,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Initialize declarative data sources
        await initializeDataSources(for: session.pubkey)
        
        print("🎨 [OlasManager] createAccountFromNsec() completed successfully")
        return session
    }
    
    func logout() {
        // Cancel profile observation
        profileObservationTask?.cancel()
        profileObservationTask = nil
        currentUserProfile = nil
        
        // Clean up data sources
        userProfileDataSource = nil
        
        // Clear all cached data and sessions
        Task {
            if let cache = cache {
                try? await cache.clear()
                print("Cleared all cached data")
            }
            
            // Clear all sessions from keychain
            for session in ndkAuthManager.availableSessions {
                try? await ndkAuthManager.deleteSession(session)
            }
        }
        
        // Clear active authentication state
        ndkAuthManager.logout()
        
        // Clear NDK signer
        ndk?.signer = nil
        
        print("Logged out and cleared all authentication data")
    }
    
    // MARK: - Auth State Management
    
    /// Check if user is authenticated via NDKAuth
    var isAuthenticated: Bool {
        ndkAuthManager.isAuthenticated
    }
    
    /// Get auth manager for use in UI
    var authManager: NDKAuthManager {
        return ndkAuthManager
    }
    
    /// Get current user from auth manager
    var currentUser: NDKUser? {
        get async {
            guard ndkAuthManager.isAuthenticated else { return nil }
            return try? await ndkAuthManager.activeSigner?.user()
        }
    }
    
    // MARK: - Declarative Data Sources
    
    private func initializeDataSources(for pubkey: String) async {
        guard let ndk = ndk else { return }
        
        print("OlasManager - Initializing declarative data sources for user: \(pubkey.prefix(8))...")
        
        // Cancel any existing profile observation
        profileObservationTask?.cancel()
        
        // Start observing user profile using NDKProfileManager
        profileObservationTask = Task { @MainActor in
            // Use maxAge of 3600 (1 hour) for the profile
            for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: 3600) {
                self.currentUserProfile = profile
            }
        }
        
        // Initialize user profile data source (kept for compatibility)
        userProfileDataSource = UserProfileDataSource(ndk: ndk, pubkey: pubkey)
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
    func addUserRelay(_ relayURL: String) async {
        var userRelays = getUserAddedRelays()
        guard !userRelays.contains(relayURL) && !defaultRelays.contains(relayURL) else {
            print("OlasManager - Relay \(relayURL) already exists")
            return
        }
        
        userRelays.append(relayURL)
        UserDefaults.standard.set(userRelays, forKey: Self.userRelaysKey)
        
        // Add relay to NDK
        if let ndk = ndk {
            await ndk.addRelay(relayURL)
        }
        
        print("OlasManager - Added user relay: \(relayURL)")
    }
    
    /// Remove a user relay and persist the change
    func removeUserRelay(_ relayURL: String) async {
        var userRelays = getUserAddedRelays()
        userRelays.removeAll { $0 == relayURL }
        UserDefaults.standard.set(userRelays, forKey: Self.userRelaysKey)
        
        // Remove relay from NDK (only if not a default relay)
        if !defaultRelays.contains(relayURL), let ndk = ndk {
            await ndk.removeRelay(relayURL)
        }
        
        print("OlasManager - Removed user relay: \(relayURL)")
    }
    
    /// Get list of user-added relays (for UI display)
    var userAddedRelays: [String] {
        return getUserAddedRelays()
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