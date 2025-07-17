import Foundation
import NDKSwift

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: NDKUser?
    
    private var ndk: NDK?
    private var signer: NDKPrivateKeySigner?
    private var subscriptionManager: SubscriptionManager?
    private var accountManager = AccountManager()
    private var relayManager = RelayManager()
    
    init() {
        checkAuthStatus()
    }
    
    func login(privateKey: String) async throws {
        // Support both hex and nsec formats
        let signer: NDKPrivateKeySigner
        if privateKey.starts(with: "nsec") {
            signer = try NDKPrivateKeySigner(nsec: privateKey)
        } else {
            signer = try NDKPrivateKeySigner(privateKey: privateKey)
        }
        
        // Use relay URLs from RelayManager
        let activeRelayUrls = relayManager.relays
            .filter { $0.isActive }
            .map { $0.url }
        
        let ndk = NDK(relayUrls: activeRelayUrls.isEmpty ? [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social"
        ] : activeRelayUrls)
        ndk.signer = signer
        
        self.signer = signer
        self.ndk = ndk
        
        // Update RelayManager with NDK instance
        relayManager.setNDK(ndk)
        
        // Connect to all relays
        await ndk.pool.connectAll()
        
        let user = try await signer.user()
        self.currentUser = user
        self.isAuthenticated = true
        
        // Update AccountManager - convert nsec to hex for storage
        if accountManager.accounts.isEmpty {
            let hexPrivateKey: String
            if privateKey.starts(with: "nsec") {
                hexPrivateKey = try Bech32.privateKey(from: privateKey)
            } else {
                hexPrivateKey = privateKey
            }
            _ = try await accountManager.addAccount(privateKey: hexPrivateKey)
        }
        
        // Initialize subscription manager after successful login
        subscriptionManager = SubscriptionManager()
        await subscriptionManager?.initialize(ndk: ndk, userPubkey: user.pubkey)
    }
    
    func register() async throws {
        let privateKey = Crypto.generatePrivateKey()
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        
        // Use relay URLs from RelayManager
        let activeRelayUrls = relayManager.relays
            .filter { $0.isActive }
            .map { $0.url }
        
        let ndk = NDK(relayUrls: activeRelayUrls.isEmpty ? [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social"
        ] : activeRelayUrls)
        ndk.signer = signer
        
        self.signer = signer
        self.ndk = ndk
        
        // Update RelayManager with NDK instance
        relayManager.setNDK(ndk)
        
        // Connect to all relays
        await ndk.pool.connectAll()
        
        let user = try await signer.user()
        self.currentUser = user
        self.isAuthenticated = true
        
        saveAuthData(privateKey: privateKey)
        
        // Initialize subscription manager after successful registration
        subscriptionManager = SubscriptionManager()
        await subscriptionManager?.initialize(ndk: ndk, userPubkey: user.pubkey)
    }
    
    func logout() {
        Task {
            await subscriptionManager?.cleanup()
            subscriptionManager = nil
        }
        
        isAuthenticated = false
        currentUser = nil
        signer = nil
        ndk = nil
        clearAuthData()
    }
    
    func getNDK() -> NDK? {
        return ndk
    }
    
    func getSubscriptionManager() -> SubscriptionManager? {
        return subscriptionManager
    }
    
    func getAccountManager() -> AccountManager {
        return accountManager
    }
    
    func getRelayManager() -> RelayManager {
        return relayManager
    }
    
    private func checkAuthStatus() {
        // Check if we have an active account in AccountManager
        if let activeAccount = accountManager.activeAccount {
            Task {
                try? await login(privateKey: activeAccount.privateKey)
            }
        } else if let privateKey = UserDefaults.standard.string(forKey: "private_key") {
            // Migrate from old system
            Task {
                try? await login(privateKey: privateKey)
                UserDefaults.standard.removeObject(forKey: "private_key")
            }
        }
    }
    
    private func saveAuthData(privateKey: String) {
        // No longer save to UserDefaults - AccountManager handles persistence
    }
    
    private func clearAuthData() {
        // No longer needed - AccountManager handles persistence
    }
}

    func loginWithBunker(bunkerUrl: String) async throws {
        // Initialize bunker signer
        let bunkerSigner: NDKBunkerSigner
        
        if bunkerUrl.starts(with: "bunker://") {
            // Direct bunker URL
            bunkerSigner = try await NDKBunkerSigner.bunker(bunkerUrl: bunkerUrl)
        } else if bunkerUrl.contains("@") {
            // NIP-05 format (npub@domain.com)
            bunkerSigner = try await NDKBunkerSigner.nip05(bunkerUrl)
        } else {
            throw AuthError.invalidBunkerUrl
        }
        
        // Use relay URLs from RelayManager
        let activeRelayUrls = relayManager.relays
            .filter { $0.isActive }
            .map { $0.url }
        
        let ndk = NDK(relayUrls: activeRelayUrls.isEmpty ? [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social"
        ] : activeRelayUrls)
        ndk.signer = bunkerSigner
        
        self.signer = nil // We don't store the bunker signer directly
        self.ndk = ndk
        
        // Update RelayManager with NDK instance
        relayManager.setNDK(ndk)
        
        // Connect to all relays
        await ndk.pool.connectAll()
        
        let user = try await bunkerSigner.user()
        self.currentUser = user
        self.isAuthenticated = true
        
        // Note: We don't add bunker accounts to AccountManager as they require special handling
        
        // Initialize subscription manager after successful login
        subscriptionManager = SubscriptionManager()
        await subscriptionManager?.initialize(ndk: ndk, userPubkey: user.pubkey)
    }
}

enum AuthError: Error {
    case invalidPrivateKey
    case networkError
    case invalidBunkerUrl