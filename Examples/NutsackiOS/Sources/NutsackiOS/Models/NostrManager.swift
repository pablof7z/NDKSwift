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
        "wss://relay.primal.net",
        "wss://relay.snort.social",
        "wss://relay.primal.net"
    ]
    
    init() {
        setupNDK()
    }
    
    private func setupNDK() {
        ndk = NDK(relayUrls: defaultRelays)
        
        Task {
            await connectToRelays()
        }
    }
    
    func connectToRelays() async {
        guard let ndk = ndk else { return }
        
        await ndk.connect()
        isConnected = true
        logger.info("Connected to relays")
        
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
        self.signer = signer
        ndk.signer = signer
        
        let publicKey = try await signer.pubkey
        currentUser = NDKUser(pubkey: publicKey)
        
        // Fetch user profile
        if currentUser != nil {
            let metadataFilter = NDKFilter(
                authors: [publicKey],
                kinds: [0],
                limit: 1
            )
            if let event = try await ndk.fetchEvent(metadataFilter),
               let contentData = event.content.data(using: .utf8),
               let _ = try? JSONDecoder().decode(NDKUserProfile.self, from: contentData) {
                // Profile metadata is published and will be available via async property
            }
        }
        
        logger.info("Logged in with public key: \(publicKey)")
    }
    
    func createNewAccount(displayName: String, about: String? = nil) async throws -> String {
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
        // Generate new private key
        let privateKeyHex = Crypto.generatePrivateKey()
        let signer = try NDKPrivateKeySigner(privateKey: privateKeyHex)
        self.signer = signer
        ndk.signer = signer
        
        // Store the private key for return
        let privateKey = privateKeyHex
        
        let publicKey = try await signer.pubkey
        currentUser = NDKUser(pubkey: publicKey)
        
        // Create and publish profile
        let metadata = NDKUserProfile(
            name: displayName,
            displayName: displayName,
            about: about ?? "Nutsack wallet user"
        )
        
        if currentUser != nil {
            // Create metadata event
            let metadataContent = try JSONEncoder().encode(metadata)
            let metadataEvent = try await NDKEventBuilder()
                .content(String(data: metadataContent, encoding: .utf8) ?? "{}")
                .kind(0)
                .build(signer: signer)
            
            try await ndk.publish(metadataEvent)
            
            // Store profile in user object
            // Profile is set - will be available via async property
            // Profile metadata is published
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
            authors: [currentUser.npub],
            kinds: [37375],
            limit: 100
        )
        
        let events = try await ndk.fetchEvents(filter)
        return Array(events)
    }
    
    func publishNIP60Wallet(_ walletEvent: NDKEvent) async throws {
        guard let ndk = ndk else { throw NostrError.ndkNotInitialized }
        
        try await ndk.publish(walletEvent)
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