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
    
    // Default relays for the app
    let defaultRelays = [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://relay.primal.net",
        "wss://relay.snort.social",
        "wss://relay.primal.net"
    ]
    
    init(from: String) {
        print("🏚️ [NostrManager] Initializing...", from)
        self.ndkAuthManager = NDKAuthManager.shared
        Task {
            await setupNDK()
        }
    }
    
    private func setupNDK() async {
        print("🏚️ [NostrManager] Setting up NDK...")
        // Initialize SQLite cache for better performance and offline access
        do {
            cache = try await NDKSQLiteCache()
            ndk = NDK(relayUrls: defaultRelays, cache: cache)
            print("NDK initialized with SQLite cache")
        } catch {
            print("Failed to initialize SQLite cache: \(error). Continuing without cache.")
            // Fall back to no cache if initialization fails
            ndk = NDK(relayUrls: defaultRelays)
        }
        
        // Set NDK on auth manager
        if let ndk = ndk {
            print("🏚️ [NostrManager] Setting NDK on auth manager")
            ndkAuthManager.setNDK(ndk)
        }
        
        Task {
            await connectToRelays()
        }
    }
    
    func connectToRelays() async {
        guard let ndk = ndk else { return }
        
        print("NostrManager - Connecting to relays: \(defaultRelays)")
        await ndk.connect()
        isConnected = true
        print("NostrManager - Connected to relays")
        
        // Check actual connected relays
        // Note: pool is internal, so we can't access it directly
        print("NostrManager - Connected to NDK with relays: \(defaultRelays)")
        
        // Monitor relay status
        await monitorRelayStatus()
    }
    
    private func monitorRelayStatus() async {
        guard ndk != nil else { return }
        
        // Relay status monitoring not available in current API
    }
    
    func login(with privateKey: String) async throws {
        guard ndk != nil else { throw NostrError.ndkNotInitialized }
        
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        ndk?.signer = signer
        
        let publicKey = try await signer.pubkey
        print("Logged in with public key: \(publicKey)")
        
        // Start profile subscription in background (non-blocking)
        Task {
            let metadataFilter = NDKFilter(
                authors: [publicKey],
                kinds: [0],
                limit: 1
            )
            
            // Subscribe to profile updates
            if let subscription = await ndk?.subscribe(filters: [metadataFilter]) {
                for try await event in subscription {
                    if let contentData = event.content.data(using: .utf8),
                       let _ = try? JSONDecoder().decode(NDKUserProfile.self, from: contentData) {
                        // Profile is automatically cached by NDK's SQLite cache
                        print("Profile metadata received and cached for \(publicKey)")
                        break // Only need first profile event
                    }
                }
            }
        }
    }
    
    func createNewAccount(displayName: String, about: String? = nil) async throws -> NDKSession {
        print("🏚️ [NostrManager] createNewAccount() called with displayName: \(displayName)")
        print("🏚️ [NostrManager] NDK instance: \(ndk != nil ? "exists" : "nil")")
        print("🏚️ [NostrManager] Is connected: \(isConnected)")
        
        guard let ndk = ndk else { 
            print("🏚️ [NostrManager] ERROR: NDK is not initialized!")
            throw NostrError.ndkNotInitialized 
        }
        
        // Generate new private key
        let privateKeyHex = Crypto.generatePrivateKey()
        let signer = try NDKPrivateKeySigner(privateKey: privateKeyHex)
        
        // Create session with auth manager
        let session = try await ndkAuthManager.createSession(
            with: signer,
            displayName: displayName,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Switch to this session
        print("🏚️ [NostrManager] Switching to new session...")
        try await ndkAuthManager.switchToSession(session)
        
        // Create and publish profile
        let metadata = NDKUserProfile(
            name: displayName,
            displayName: displayName,
            about: about ?? "Nutsack wallet user"
        )
        
        if ndkAuthManager.isAuthenticated {
            print("🏚️ [NostrManager] User is authenticated, publishing metadata...")
            // Create metadata event
            let metadataContent = try JSONEncoder().encode(metadata)
            let metadataEvent = try await NDKEventBuilder()
                .content(String(data: metadataContent, encoding: .utf8) ?? "{}")
                .kind(0)
                .build(signer: signer)
            
            _ = try await ndk.publish(metadataEvent)
            
            // Update session with profile
            try await ndkAuthManager.updateActiveSessionProfile(metadata)
        }
        
        print("🏚️ [NostrManager] createNewAccount() completed successfully with pubkey: \(session.pubkey)")
        return session
    }
    
    func logout() {
        ndkAuthManager.logout()
        print("Logged out")
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
    
    /// Create account using existing nsec
    func createAccountFromNsec(_ nsec: String, displayName: String) async throws -> NDKSession {
        print("🏚️ [NostrManager] createAccountFromNsec() called with displayName: \(displayName)")
        guard ndk != nil else { throw NostrError.ndkNotInitialized }
        
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        
        // Create session with auth manager
        let session = try await ndkAuthManager.createSession(
            with: signer,
            displayName: displayName,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Switch to this session
        print("🏚️ [NostrManager] Switching to imported session...")
        try await ndkAuthManager.switchToSession(session)
        
        print("🏚️ [NostrManager] createAccountFromNsec() completed successfully with pubkey: \(session.pubkey)")
        return session
    }
    
    /// Get current user from auth manager
    var currentUser: NDKUser? {
        get async {
            guard ndkAuthManager.isAuthenticated else { return nil }
            return try? await ndkAuthManager.activeSigner?.user()
        }
    }
    
    func fetchNIP60Wallets() async throws -> [NDKEvent] {
        guard let ndk = ndk,
              ndkAuthManager.isAuthenticated,
              let user = await currentUser else {
            throw NostrError.notLoggedIn
        }
        
        let filter = NDKFilter(
            authors: [user.npub],
            kinds: [EventKind.walletInfo],
            limit: 100
        )
        
        // Fetch events - will use cache if available and fetch from relays if needed
        let events = try await ndk.fetchEvents([filter])
        return Array(events)
    }
    
    func publishNIP60Wallet(_ walletEvent: NDKEvent) async throws {
        guard ndk != nil else { throw NostrError.ndkNotInitialized }
        
        _ = try await ndk?.publish(walletEvent)
        print("Published NIP-60 wallet event")
    }
}

enum NostrError: LocalizedError {
    case ndkNotInitialized
    case notLoggedIn
    case invalidPrivateKey
    
    var errorDescription: String? {
        switch self {
        case .ndkNotInitialized:
            return "NDK is not initialized"
        case .notLoggedIn:
            return "Not logged in to Nostr"
        case .invalidPrivateKey:
            return "Invalid private key"
        }
    }
}