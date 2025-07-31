import Foundation

/// Manages user relay lists with automatic persistence to Nostr (NIP-65, kind 10002)
/// and local storage for default relays
public class NDKRelayListManager: ObservableObject {
    @Published public private(set) var relayList: NDKRelayList?
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    
    private let ndk: NDK
    private let defaultRelays: [String]
    private let userDefaultsKey: String
    private var observationTask: Task<Void, Never>?
    
    /// Initialize relay list manager
    /// - Parameters:
    ///   - ndk: NDK instance
    ///   - defaultRelays: Default relays to use if no user list exists
    ///   - appIdentifier: Unique identifier for UserDefaults storage
    public init(ndk: NDK, defaultRelays: [String], appIdentifier: String) {
        self.ndk = ndk
        self.defaultRelays = defaultRelays
        self.userDefaultsKey = "\(appIdentifier)_UserAddedRelays"
        
        Task {
            await loadRelayList()
        }
    }
    
    deinit {
        observationTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Get all relay URLs (user's relay list + locally stored additions)
    public func getAllRelays() async -> [String] {
        // Get relays from the user's relay list
        let relayListRelays = relayList?.relayURLs ?? []
        
        // Get locally stored user-added relays
        let userAddedRelays = getUserAddedRelays()
        
        // Combine and deduplicate
        let allRelays = Set(relayListRelays + userAddedRelays + defaultRelays)
        return Array(allRelays)
    }
    
    /// Add a relay to the user's list
    public func addRelay(_ url: String, access: Set<NDKRelayAccess> = [.read, .write]) async {
        // Add to local storage
        var userRelays = getUserAddedRelays()
        if !userRelays.contains(url) {
            userRelays.append(url)
            saveUserAddedRelays(userRelays)
        }
        
        // Add to NDK
        _ = await ndk.addRelay(url)
        
        // Update relay list event
        await updateRelayList()
    }
    
    /// Remove a relay from the user's list
    public func removeRelay(_ url: String) async {
        // Remove from local storage
        var userRelays = getUserAddedRelays()
        userRelays.removeAll { $0 == url }
        saveUserAddedRelays(userRelays)
        
        // Remove from NDK
        await ndk.removeRelay(url)
        
        // Update relay list event
        await updateRelayList()
    }
    
    /// Reset to default relays
    public func resetToDefaults() async {
        // Clear local storage
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        
        // Disconnect from all current relays
        for relay in await ndk.pool.relays {
            await ndk.removeRelay(relay.url)
        }
        
        // Add default relays
        for relayURL in defaultRelays {
            _ = await ndk.addRelay(relayURL)
        }
        
        // Update relay list event
        await updateRelayList()
    }
    
    // MARK: - Private Methods
    
    private func loadRelayList() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let signer = ndk.signer else {
            // No signer, use local defaults
            await connectToLocalRelays()
            return
        }
        
        do {
            let pubkey = try await signer.pubkey
            
            // Fetch user's relay list
            let filter = NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.relayList],
                limit: 1
            )
            
            let dataSource = ndk.subscribe(filter: filter, maxAge: 300, cachePolicy: .cacheWithNetwork)
            
            for await event in dataSource.events {
                self.relayList = NDKRelayList.fromEvent(event, ndk: ndk)
                
                // Connect to relays from the list
                await connectToRelayList()
                break
            }
            
            // If no relay list found, create one
            if relayList == nil {
                await createInitialRelayList()
            }
        } catch {
            self.error = error
            await connectToLocalRelays()
        }
    }
    
    private func connectToRelayList() async {
        guard let relayList = relayList else { return }
        
        // Connect to all relays in the list
        for entry in relayList.relayEntries {
            _ = await ndk.addRelay(entry.relay.url)
        }
        
        // Also connect to any locally added relays
        for url in getUserAddedRelays() {
            _ = await ndk.addRelay(url)
        }
    }
    
    private func connectToLocalRelays() async {
        // Connect to default relays and any user-added ones
        let allRelays = Set(defaultRelays + getUserAddedRelays())
        for url in allRelays {
            _ = await ndk.addRelay(url)
        }
    }
    
    private func createInitialRelayList() async {
        guard ndk.signer != nil else { return }
        
        do {
            let relayList = NDKRelayList(ndk: ndk)
            
            // Add default relays and any user-added ones
            let allRelays = Set(defaultRelays + getUserAddedRelays())
            for url in allRelays {
                relayList.addRelay(url, access: [.read, .write])
            }
            
            // Sign and publish
            try await relayList.sign()
            _ = try await ndk.publishRelayList(relayList)
            
            self.relayList = relayList
        } catch {
            self.error = error
        }
    }
    
    private func updateRelayList() async {
        guard ndk.signer != nil else { return }
        
        do {
            let newRelayList = NDKRelayList(ndk: ndk)
            
            // Get all current relays from NDK
            let currentRelays = await ndk.pool.relays
            
            // Add each relay to the list
            for relay in currentRelays {
                newRelayList.addRelay(relay.url, access: [.read, .write])
            }
            
            // Sign and publish
            try await newRelayList.sign()
            _ = try await ndk.publishRelayList(newRelayList)
            
            self.relayList = newRelayList
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Local Storage
    
    private func getUserAddedRelays() -> [String] {
        UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
    }
    
    private func saveUserAddedRelays(_ relays: [String]) {
        UserDefaults.standard.set(relays, forKey: userDefaultsKey)
    }
    
    /// Get user-added relays (for UI display)
    public var userAddedRelays: [String] {
        getUserAddedRelays()
    }
    
    /// Check if a relay is user-added
    public func isUserAddedRelay(_ url: String) -> Bool {
        getUserAddedRelays().contains(url)
    }
}