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
    
    init() {
        self.ndkAuthManager = NDKAuthManager.shared
        Task {
            await setupNDK()
        }
    }
    
    private func setupNDK() async {
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
            ndkAuthManager.setNDK(ndk)
        }
        
        Task {
            await connectToRelays()
        }
    }
    
    func connectToRelays() async {
        guard let ndk = ndk else { return }
        
        await ndk.connect()
        isConnected = true
        print("Connected to relays")
        
        // Monitor relay status
        await monitorRelayStatus()
    }
    
    private func monitorRelayStatus() async {
        guard let ndk = ndk else { return }
        
        // Relay status monitoring not available in current API
    }
    
    func login(with privateKey: String) async throws {
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        ndk.signer = signer
        
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
            let subscription = ndk.subscribe(filters: [metadataFilter])
            
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
    
    func createNewAccount(displayName: String, about: String? = nil) async throws -> NDKSession {
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
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
        try await ndkAuthManager.switchToSession(session)
        
        // Create and publish profile
        let metadata = NDKUserProfile(
            name: displayName,
            displayName: displayName,
            about: about ?? "Nutsack wallet user"
        )
        
        if ndkAuthManager.isAuthenticated {
            // Create metadata event
            let metadataContent = try JSONEncoder().encode(metadata)
            let metadataEvent = try await NDKEventBuilder()
                .content(String(data: metadataContent, encoding: .utf8) ?? "{}")
                .kind(0)
                .build(signer: signer)
            
            try await ndk.publish(metadataEvent)
            
            // Update session with profile
            try await ndkAuthManager.updateActiveSessionProfile(metadata)
        }
        
        print("Created new account with public key: \(session.pubkey)")
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
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        
        // Create session with auth manager
        let session = try await ndkAuthManager.createSession(
            with: signer,
            displayName: displayName,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Switch to this session
        try await ndkAuthManager.switchToSession(session)
        
        print("Created account from nsec with public key: \(session.pubkey)")
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
            kinds: [37375],
            limit: 100
        )
        
        // Fetch events - will use cache if available and fetch from relays if needed
        let events = try await ndk.fetchEvents(filter)
        return Array(events)
    }
    
    func publishNIP60Wallet(_ walletEvent: NDKEvent) async throws {
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
        try await ndk.publish(walletEvent)
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