import Foundation
import NDKSwift
import SwiftUI

@MainActor
class NostrManager: ObservableObject {
    @Published var ndk: NDK?
    @Published var currentUser: NDKUser?
    @Published var isConnected = false
    @Published var relayStatus: [String: Bool] = [:]
    
    private var signer: NDKPrivateKeySigner?
    
    // Default relays for the app
    let defaultRelays = [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://nos.lol",
        "wss://relay.snort.social",
        "wss://relay.primal.net"
    ]
    
    init() {
        setupNDK()
    }
    
    private func setupNDK() {
        ndk = NDK(
            explicitRelayURLs: defaultRelays,
            cacheAdapter: NDKSQLiteCache(),
            enableOutboxModel: true
        )
        
        Task {
            await connectToRelays()
        }
    }
    
    func connectToRelays() async {
        guard let ndk = ndk else { return }
        
        do {
            try await ndk.connect()
            isConnected = true
            logger.info("Connected to relays")
            
            // Monitor relay status
            await monitorRelayStatus()
        } catch {
            logger.error("Failed to connect to relays: \(error)")
            isConnected = false
        }
    }
    
    private func monitorRelayStatus() async {
        guard let ndk = ndk else { return }
        
        for relay in ndk.pool.relays() {
            relayStatus[relay.url] = relay.status == .connected
        }
    }
    
    func login(with privateKey: String) async throws {
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        self.signer = signer
        ndk.signer = signer
        
        let publicKey = signer.publicKey(hex: true)
        currentUser = ndk.user(withPublicKey: publicKey)
        
        // Fetch user profile
        if let user = currentUser {
            try await user.fetchProfile()
        }
        
        logger.info("Logged in with public key: \(publicKey)")
    }
    
    func createNewAccount(displayName: String, about: String? = nil) async throws -> String {
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
        // Generate new private key
        let privateKey = NDKPrivateKeySigner.generatePrivateKey()
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        self.signer = signer
        ndk.signer = signer
        
        let publicKey = signer.publicKey(hex: true)
        currentUser = ndk.user(withPublicKey: publicKey)
        
        // Create and publish profile
        let metadata = UserProfile(
            name: displayName,
            displayName: displayName,
            about: about ?? "Nutsack wallet user",
            nip05: nil,
            lud16: nil,
            website: nil,
            picture: nil,
            banner: nil
        )
        
        if let user = currentUser {
            try await user.updateProfile(metadata)
        }
        
        logger.info("Created new account with public key: \(publicKey)")
        return privateKey
    }
    
    func logout() {
        signer = nil
        ndk?.signer = nil
        currentUser = nil
        logger.info("Logged out")
    }
    
    func fetchNIP60Wallets() async throws -> [NDKEvent] {
        guard let ndk = ndk, let currentUser = currentUser else {
            throw NostrError.notLoggedIn
        }
        
        let filter = NDKFilter(
            kinds: [37375],
            authors: [currentUser.publicKey],
            limit: 100
        )
        
        let events = try await ndk.fetchEvents(filter)
        return Array(events)
    }
    
    func publishNIP60Wallet(_ walletEvent: NDKEvent) async throws {
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
        try await walletEvent.sign()
        try await ndk.publish(event: walletEvent)
        logger.info("Published NIP-60 wallet event")
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