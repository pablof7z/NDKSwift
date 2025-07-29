import Foundation
import Combine

/// A base class providing common Nostr management functionality for apps
/// This reduces duplication across apps while allowing customization
@MainActor
open class NDKNostrManager: ObservableObject {
    // MARK: - Published Properties
    @Published public private(set) var ndk: NDK?
    @Published public private(set) var isConnected = false
    @Published public private(set) var relayStatus: [String: Bool] = [:]
    @Published public private(set) var currentUserProfile: NDKUserProfile?
    @Published public private(set) var isInitialized = false
    
    // MARK: - Public Properties
    public var cache: NDKSQLiteCache?
    public var zapManager: NDKZapManager?
    
    // MARK: - Configuration
    /// Override in subclasses to provide app-specific default relays
    open var defaultRelays: [String] {
        [RelayConstants.primal, RelayConstants.damus]
    }
    
    /// Override in subclasses to provide app-specific client tag config
    open var clientTagConfig: NDKClientTagConfig? {
        nil
    }
    
    /// Override in subclasses to provide app-specific session config
    open var sessionConfiguration: NDKSessionConfiguration {
        NDKSessionConfiguration(
            dataRequirements: [.followList, .muteList],
            preloadStrategy: .progressive
        )
    }
    
    /// Key for storing app-added relays (override for app-specific key)
    open var appRelaysKey: String {
        "AppAddedRelays"
    }
    
    // MARK: - Private Properties
    private var profileObservationTask: Task<Void, Never>?
    private var relayMonitorTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    public var isAuthenticated: Bool {
        NDKAuthManager.shared.hasActiveSession
    }
    
    // MARK: - Initialization
    public init() {
        NDKLogger.log(.info, category: .general, "[\(type(of: self))] Initializing...")
        Task {
            await setupNDK()
        }
    }
    
    deinit {
        profileObservationTask?.cancel()
        relayMonitorTask?.cancel()
    }
    
    // MARK: - Setup
    /// Sets up NDK with cache, relays, and configuration
    open func setupNDK() async {
        NDKLogger.log(.info, category: .general, "[\(type(of: self))] Setting up NDK...")
        
        // Initialize SQLite cache for better performance and offline access
        do {
            cache = try await NDKSQLiteCache()
            let allRelays = getAllRelays()
            ndk = NDK(relayUrls: allRelays, cache: cache)
            NDKLogger.log(.info, category: .general, "NDK initialized with SQLite cache and \(allRelays.count) relays: \(allRelays)")
        } catch {
            NDKLogger.log(.error, category: .general, "Failed to initialize SQLite cache: \(error). Continuing without cache.")
            let allRelays = getAllRelays()
            ndk = NDK(relayUrls: allRelays)
            NDKLogger.log(.info, category: .general, "NDK initialized without cache and \(allRelays.count) relays: \(allRelays)")
        }
        
        // Set NDK on auth manager
        if let ndk = ndk {
            NDKLogger.log(.info, category: .general, "[\(type(of: self))] Setting NDK on auth manager")
            NDKAuthManager.shared.setNDK(ndk)
            
            // Configure client tags if provided
            if let config = clientTagConfig {
                ndk.clientTagConfig = config
                NDKLogger.log(.info, category: .general, "[\(type(of: self))] Configured NIP-89 client tags")
            }
            
            // Initialize zap manager
            zapManager = NDKZapManager(ndk: ndk)
            NDKLogger.log(.info, category: .general, "[\(type(of: self))] Zap manager initialized")
            
            // Initialize auth manager to restore sessions
            NDKLogger.log(.info, category: .general, "[\(type(of: self))] Initializing auth manager for session restoration")
            await NDKAuthManager.shared.initialize()
            
            // If authenticated after restore, initialize user data
            if NDKAuthManager.shared.hasActiveSession {
                if let signer = NDKAuthManager.shared.activeSigner {
                    Task {
                        let pubkey = try await signer.pubkey
                        await initializeUserData(for: pubkey)
                    }
                }
            }
        }
        
        Task {
            await connectToRelays()
        }
        
        // Mark as initialized
        isInitialized = true
        NDKLogger.log(.info, category: .general, "[\(type(of: self))] Initialization complete")
    }
    
    // MARK: - Relay Management
    
    /// Connect to all configured relays
    open func connectToRelays() async {
        guard let ndk = ndk else { return }
        
        NDKLogger.log(.info, category: .general, "[\(type(of: self))] Connecting to relays...")
        await ndk.connect()
        isConnected = true
        NDKLogger.log(.info, category: .general, "[\(type(of: self))] Connected to relays")
        
        // Monitor relay status
        relayMonitorTask?.cancel()
        relayMonitorTask = Task {
            await monitorRelayStatus()
        }
    }
    
    /// Monitor relay connection status
    private func monitorRelayStatus() async {
        guard let ndk = ndk else { return }
        
        for await change in await ndk.relayChanges {
            switch change {
            case .relayConnected(let relay):
                relayStatus[relay.url] = true
            case .relayDisconnected(let relay):
                relayStatus[relay.url] = false
            case .relayAdded(let relay):
                relayStatus[relay.url] = false
            case .relayRemoved(let url):
                relayStatus.removeValue(forKey: url)
            }
        }
    }
    
    /// Get all relays (default + app added)
    open func getAllRelays() -> [String] {
        let appRelays = UserDefaults.standard.stringArray(forKey: appRelaysKey) ?? []
        return Array(Set(defaultRelays + appRelays))
    }
    
    /// Get app-added relays
    public var appAddedRelays: [String] {
        UserDefaults.standard.stringArray(forKey: appRelaysKey) ?? []
    }
    
    /// Add an app relay
    /// 
    /// Adds a relay to this app's connection pool. This relay will be connected to
    /// whenever the app launches, in addition to the default relays.
    /// 
    /// **Important**: This does NOT modify the user's NIP-65 relay list. The relay
    /// is only stored locally for this app and won't affect the user's relay
    /// preferences in other Nostr clients.
    /// 
    /// - Parameter relayURL: The WebSocket URL of the relay to add (e.g., "wss://relay.example.com")
    public func addAppRelay(_ relayURL: String) async {
        guard let ndk = ndk else { return }
        
        var appRelays = appAddedRelays
        if !appRelays.contains(relayURL) && !defaultRelays.contains(relayURL) {
            appRelays.append(relayURL)
            UserDefaults.standard.set(appRelays, forKey: appRelaysKey)
            
            // Add to NDK and connect
            let relay = await ndk.addRelayAndConnect(relayURL)
            if relay != nil {
                NDKLogger.log(.info, category: .general, "Added and connected to relay: \(relayURL)")
            }
        }
    }
    
    /// Remove an app relay
    /// 
    /// Removes a relay from this app's connection pool. The relay will be disconnected
    /// and won't be connected to on future app launches.
    /// 
    /// **Important**: This does NOT modify the user's NIP-65 relay list. It only
    /// removes the relay from this app's local storage.
    /// 
    /// - Parameter relayURL: The WebSocket URL of the relay to remove
    /// - Note: Default relays cannot be removed using this method
    public func removeAppRelay(_ relayURL: String) async {
        guard let ndk = ndk else { return }
        
        var appRelays = appAddedRelays
        appRelays.removeAll { $0 == relayURL }
        UserDefaults.standard.set(appRelays, forKey: appRelaysKey)
        
        // Don't remove if it's a default relay
        if !defaultRelays.contains(relayURL) {
            await ndk.removeRelay(relayURL)
            NDKLogger.log(.info, category: .general, "Removed relay: \(relayURL)")
        }
    }
    
    // MARK: - Authentication
    
    /// Login with private key (hex or nsec format)
    public func login(with privateKey: String) async throws {
        guard let ndk = ndk else { throw NDKError.notConfigured("NDK not initialized") }
        
        let signer: NDKPrivateKeySigner
        if privateKey.hasPrefix("nsec1") {
            signer = try NDKPrivateKeySigner(nsec: privateKey)
        } else {
            signer = try NDKPrivateKeySigner(privateKey: privateKey)
        }
        
        // Create session via NDKAuthManager for proper persistence
        _ = try await NDKAuthManager.shared.addSession(
            signer,
            requiresBiometric: false
        )
        
        // Start session with app-specific configuration
        try await ndk.startSession(
            signer: signer,
            config: sessionConfiguration
        )
        
        // Initialize user data
        let pubkey = try await signer.pubkey
        await initializeUserData(for: pubkey)
    }
    
    /// Create a new account
    public func createNewAccount(displayName: String, about: String? = nil, picture: String? = nil) async throws -> NDKSession {
        guard let ndk = ndk else { throw NDKError.notConfigured("NDK not initialized") }
        
        // Generate new private key signer
        let signer = try NDKPrivateKeySigner.generate()
        
        // Create session via NDKAuthManager
        let session = try await NDKAuthManager.shared.addSession(
            signer,
            requiresBiometric: false
        )
        
        // Start session
        try await ndk.startSession(
            signer: signer,
            config: sessionConfiguration
        )
        
        // Initialize user data first
        let pubkey = try await signer.pubkey
        await initializeUserData(for: pubkey)
        
        // Create and save profile
        var profile = NDKUserProfile()
        profile.displayName = displayName
        profile.name = displayName
        if let about = about {
            profile.about = about
        }
        if let picture = picture {
            profile.picture = picture
        }
        
        await ndk.profileManager.saveProfile(profile, for: pubkey)
        
        return session
    }
    
    /// Logout current user
    public func logout() {
        NDKAuthManager.shared.logout()
        profileObservationTask?.cancel()
        profileObservationTask = nil
        currentUserProfile = nil
    }
    
    // MARK: - User Data
    
    /// Initialize user-specific data after authentication
    /// Override in subclasses to add app-specific initialization
    open func initializeUserData(for pubkey: String) async {
        // Observe current user's profile
        profileObservationTask?.cancel()
        profileObservationTask = Task {
            guard let ndk = ndk else { return }
            
            for await profile in await ndk.profileManager.observe(for: pubkey) {
                self.currentUserProfile = profile
            }
        }
    }
}