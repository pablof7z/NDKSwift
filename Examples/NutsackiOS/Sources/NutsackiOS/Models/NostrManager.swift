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
    var zapManager: NDKZapManager?
    
    private var ndkAuthManager: NDKAuthManager
    var cache: NDKSQLiteCache?
    
    // Default relays for the app
    let defaultRelays = [ "wss://relay.primal.net", "wss://purplepag.es" ]
    
    // Key for storing user-added relays
    private static let userRelaysKey = "UserAddedRelays"
    
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
            let allRelays = getAllRelays()
            ndk = NDK(relayUrls: allRelays, cache: cache)
            print("NDK initialized with SQLite cache and \(allRelays.count) relays: \(allRelays)")
        } catch {
            print("Failed to initialize SQLite cache: \(error). Continuing without cache.")
            // Fall back to no cache if initialization fails
            let allRelays = getAllRelays()
            ndk = NDK(relayUrls: allRelays)
            print("NDK initialized without cache and \(allRelays.count) relays: \(allRelays)")
        }
        
        // Set NDK on auth manager
        if let ndk = ndk {
            print("🏚️ [NostrManager] Setting NDK on auth manager")
            ndkAuthManager.setNDK(ndk)
            
            // Configure NIP-89 client tags for Nutsack
            ndk.clientTagConfig = NDKClientTagConfig(
                name: "Nutsack",
                relay: "wss://relay.primal.net",
                autoTag: true,
                excludedKinds: [
                    // Exclude sensitive event kinds from client tagging
                    EventKind.encryptedDirectMessage,
                    EventKind.cashuSpendingHistory,
                    EventKind.cashuToken,
                ]
            )
            print("🏚️ [NostrManager] Configured NIP-89 client tags")
            
            // Initialize zap manager
            zapManager = NDKZapManager(ndk: ndk)
            print("🏚️ [NostrManager] Zap manager initialized")
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
        
        // Zap manager gets signer from NDK automatically
        
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
                    if let _ = JSONCoding.safeDecode(NDKUserProfile.self, from: event.content) {
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
        let signer = try NDKPrivateKeySigner.generate()
        
        // Create session with auth manager
        let session = try await ndkAuthManager.createSession(
            with: signer,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Switch to this session
        print("🏚️ [NostrManager] Switching to new session...")
        try await ndkAuthManager.switchToSession(session)
        
        // Zap manager gets signer from NDK automatically
        
        // Create and publish profile
        let metadata = NDKUserProfile(
            name: displayName,
            displayName: displayName,
            about: about ?? "Nutsack wallet user"
        )
        
        if ndkAuthManager.isAuthenticated {
            print("🏚️ [NostrManager] User is authenticated, publishing metadata...")
            // Create metadata event
            let metadataContent = try JSONCoding.encodeToString(metadata)
            let metadataEvent = try await ndk.event()
                .content(metadataContent)
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
        // Clear all cached data and sessions
        Task {
            if let cache = cache {
                try? await cache.clear()
                print("Cleared all cached data")
            }
            
            // Clear all sessions from keychain to prevent "Welcome back" scenario
            for session in ndkAuthManager.availableSessions {
                try? await ndkAuthManager.deleteSession(session)
            }
        }
        
        // Clear active authentication state
        ndkAuthManager.logout()
        
        // Clear NDK signer
        ndk?.signer = nil
        
        // Clear zap manager signer
        // Zap manager gets signer from NDK automatically
        
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
    
    /// Create account using existing nsec
    func createAccountFromNsec(_ nsec: String, displayName: String) async throws -> NDKSession {
        print("🏚️ [NostrManager] createAccountFromNsec() called with displayName: \(displayName)")
        guard ndk != nil else { throw NostrError.ndkNotInitialized }
        
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        
        // Create session with auth manager
        let session = try await ndkAuthManager.createSession(
            with: signer,
            requiresBiometric: false,
            isHardwareBacked: false
        )
        
        // Switch to this session
        print("🏚️ [NostrManager] Switching to imported session...")
        try await ndkAuthManager.switchToSession(session)
        
        // Zap manager gets signer from NDK automatically
        
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
    
    // MARK: - Negentropy Sync
    
    /// Perform startup sync after wallet has loaded
    func performStartupSync() async {
        guard let ndk = ndk, isAuthenticated else {
            print("NostrManager - Cannot perform startup sync: NDK not ready or user not authenticated")
            return
        }
        
        // Check if we already have connected relays
        let (connectedCount, totalCount) = await ndk.getRelayConnectionSummary()
        print("NostrManager - Initial relay status: \(connectedCount)/\(totalCount) connected")
        
        if connectedCount > 0 {
            print("NostrManager - NDK is ready, proceeding with startup sync immediately")
        } else {
            print("NostrManager - No relays connected yet, waiting for first connection...")
            
            // Wait for the first relay to connect with timeout
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                throw CancellationError()
            }
            
            let observerTask = Task {
                let relayChanges = await ndk.relayChanges
                for await change in relayChanges {
                    switch change {
                    case .relayConnected(let relay):
                        print("NostrManager - Relay connected: \(relay.url), proceeding with startup sync")
                        return // Exit successfully
                    case .relayDisconnected(let relay):
                        print("NostrManager - Relay disconnected: \(relay.url)")
                        continue // Keep waiting
                    case .relayAdded(let relay):
                        print("NostrManager - Relay added: \(relay.url)")
                        continue // Keep waiting for connection
                    case .relayRemoved(let url):
                        print("NostrManager - Relay removed: \(url)")
                        continue // Keep waiting
                    }
                }
            }
            
            do {
                _ = try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await timeoutTask.value }
                    group.addTask { try await observerTask.value }
                    
                    // Wait for first task to complete
                    try await group.next()
                    
                    // Cancel remaining tasks
                    group.cancelAll()
                }
            } catch {
                print("NostrManager - Timeout waiting for relay connections, proceeding anyway")
            }
        }
        
        print("NostrManager - Starting negentropy sync...")
        
        // Run both syncs concurrently
        async let contactsSync = syncContactsMetadata()
        async let walletEventsSync = syncWalletEvents()
        
        // Wait for both to complete
        await contactsSync
        await walletEventsSync
        
        print("NostrManager - Startup sync completed")
    }
    
    /// Sync kind:0 metadata events for user's contacts
    private func syncContactsMetadata() async {
        guard let ndk = ndk, let signer = ndk.signer else { return }
        
        do {
            let userPubkey = try await signer.pubkey
            print("NostrManager - Syncing contacts metadata for user: \(userPubkey.prefix(8))...")
            
            // First, fetch user's contact list (kind:3)
            let contactListFilter = NDKFilter(
                authors: [userPubkey],
                kinds: [3], // Contact list events
                limit: 1
            )
            
            let contactEvents = try await ndk.fetchEvents([contactListFilter])
            guard let latestContactEvent = contactEvents.first else {
                print("NostrManager - No contact list found, skipping contacts sync")
                return
            }
            
            // Extract followed pubkeys from p tags
            let followedPubkeys = latestContactEvent.tags
                .filter { $0.count >= 2 && $0[0] == "p" }
                .map { $0[1] }
            
            guard !followedPubkeys.isEmpty else {
                print("NostrManager - No contacts found in contact list")
                return
            }
            
            print("NostrManager - Found \(followedPubkeys.count) contacts to sync metadata for")
            
            // Create filter for contacts' metadata, relay lists, and zap configs
            let contactsFilter = NDKFilter(
                authors: followedPubkeys,
                kinds: [
                    0,     // Profile metadata
                    10002, // Relay list metadata  
                    10019  // Zap configuration
                ]
            )
            
            // Sync with all connected relays (receive-only for wallet security)
            let results = try await ndk.syncWithAllRelays(filter: contactsFilter, direction: .receive)
            
            var totalDownloaded = 0
            var totalEfficiency = 0
            var eventsByKind: [Int: Int] = [:]
            
            for (relay, result) in results {
                totalDownloaded += result.downloadedEvents.count
                totalEfficiency += result.efficiencyRatio
                
                // Count events by kind for detailed logging
                for event in result.downloadedEvents {
                    eventsByKind[event.kind, default: 0] += 1
                }
                
                print("NostrManager - Contacts sync on \(relay): \(result.downloadedEvents.count) new events, \(result.efficiencyRatio)% efficient")
            }
            
            let avgEfficiency = results.isEmpty ? 0 : totalEfficiency / results.count
            let metadataCount = eventsByKind[0] ?? 0
            let relayListCount = eventsByKind[10002] ?? 0
            let zapConfigCount = eventsByKind[10019] ?? 0
            
            print("NostrManager - Contacts sync completed: \(totalDownloaded) total events (\(metadataCount) metadata, \(relayListCount) relay lists, \(zapConfigCount) zap configs), \(avgEfficiency)% avg efficiency")
            
        } catch {
            print("NostrManager - Error syncing contacts metadata: \(error)")
        }
    }
    
    /// Sync user's wallet events (kind:7376 and 9321)
    private func syncWalletEvents() async {
        guard let ndk = ndk, let signer = ndk.signer else { return }
        
        do {
            let userPubkey = try await signer.pubkey
            print("NostrManager - Syncing wallet events for user: \(userPubkey.prefix(8))...")
            
            // Create filter for user's wallet events
            let walletEventsFilter = NDKFilter(
                authors: [userPubkey],
                kinds: [
                    EventKind.cashuSpendingHistory, // 7376
                    EventKind.cashuToken            // 9321
                ]
            )
            
            // Sync with all connected relays (receive-only for wallet security)
            let results = try await ndk.syncWithAllRelays(filter: walletEventsFilter, direction: .receive)
            
            var totalDownloaded = 0
            var totalEfficiency = 0
            for (relay, result) in results {
                totalDownloaded += result.downloadedEvents.count
                totalEfficiency += result.efficiencyRatio
                print("NostrManager - Wallet events sync on \(relay): \(result.downloadedEvents.count) new events, \(result.efficiencyRatio)% efficient")
            }
            
            let avgEfficiency = results.isEmpty ? 0 : totalEfficiency / results.count
            print("NostrManager - Wallet events sync completed: \(totalDownloaded) new events, \(avgEfficiency)% avg efficiency")
            
        } catch {
            print("NostrManager - Error syncing wallet events: \(error)")
        }
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
            print("NostrManager - Relay \(relayURL) already exists")
            return
        }
        
        userRelays.append(relayURL)
        UserDefaults.standard.set(userRelays, forKey: Self.userRelaysKey)
        print("NostrManager - Added user relay: \(relayURL)")
        print("NostrManager - User relays now: \(userRelays)")
    }
    
    /// Remove a user relay and persist the change
    func removeUserRelay(_ relayURL: String) {
        var userRelays = getUserAddedRelays()
        userRelays.removeAll { $0 == relayURL }
        UserDefaults.standard.set(userRelays, forKey: Self.userRelaysKey)
        print("NostrManager - Removed user relay: \(relayURL)")
        print("NostrManager - User relays now: \(userRelays)")
    }
    
    /// Get list of user-added relays (for UI display)
    var userAddedRelays: [String] {
        return getUserAddedRelays()
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