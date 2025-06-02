import Foundation

/// Main entry point for NDKSwift
public final class NDK {
    /// Active signer for this NDK instance
    public var signer: NDKSigner?
    
    /// Cache adapter for storing events
    public var cacheAdapter: NDKCacheAdapter?
    
    /// Active user (derived from signer)
    public var activeUser: NDKUser? {
        // This will need to be async or cached
        return nil
    }
    
    /// Relay pool
    private let relayPool: NDKRelayPool
    
    /// Event repository
    private let eventRepository: NDKEventRepository
    
    /// Subscription manager
    private let subscriptionManager: NDKSubscriptionManager
    
    /// Whether debug mode is enabled
    public var debugMode: Bool = false
    
    /// Payment router for handling zaps and payments
    public var paymentRouter: NDKPaymentRouter?
    
    /// Wallet configuration
    public var walletConfig: NDKWalletConfig? {
        didSet {
            if let config = walletConfig {
                paymentRouter = NDKPaymentRouter(ndk: self, walletConfig: config)
            } else {
                paymentRouter = nil
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(
        relayUrls: [RelayURL] = [],
        signer: NDKSigner? = nil,
        cacheAdapter: NDKCacheAdapter? = nil
    ) {
        self.signer = signer
        self.cacheAdapter = cacheAdapter
        self.relayPool = NDKRelayPool()
        self.eventRepository = NDKEventRepository()
        self.subscriptionManager = NDKSubscriptionManager()
        
        // Add initial relays
        for url in relayUrls {
            addRelay(url)
        }
    }
    
    // MARK: - Relay Management
    
    /// Add a relay to the pool
    @discardableResult
    public func addRelay(_ url: RelayURL) -> NDKRelay {
        return relayPool.addRelay(url)
    }
    
    /// Remove a relay from the pool
    public func removeRelay(_ url: RelayURL) {
        relayPool.removeRelay(url)
    }
    
    /// Get all relays
    public var relays: [NDKRelay] {
        return relayPool.relays
    }
    
    /// Connect to all relays
    public func connect() async {
        await relayPool.connectAll()
    }
    
    /// Disconnect from all relays
    public func disconnect() async {
        await relayPool.disconnectAll()
    }
    
    /// Get pool of relays
    public var pool: NDKRelayPool {
        return relayPool
    }
    
    // MARK: - Event Publishing
    
    /// Publish an event
    @discardableResult
    public func publish(_ event: NDKEvent) async throws -> Set<NDKRelay> {
        // Sign event if not already signed
        if event.sig == nil {
            guard let signer = signer else {
                throw NDKError.signingFailed
            }
            
            // Generate ID if needed
            if event.id == nil {
                _ = try event.generateID()
            }
            
            // Sign the event
            event.sig = try await signer.sign(event)
        }
        
        // Validate event
        try event.validate()
        
        // TODO: Implement relay selection and publishing
        // For now, return empty set
        return []
    }
    
    // MARK: - Subscriptions
    
    /// Subscribe to events matching the given filters
    public func subscribe(
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions()
    ) -> NDKSubscription {
        var subscriptionOptions = options
        subscriptionOptions.relays = subscriptionOptions.relays ?? Set(relays)
        
        let subscription = NDKSubscription(
            filters: filters,
            options: subscriptionOptions,
            ndk: self
        )
        
        subscription.start()
        
        return subscription
    }
    
    /// Fetch events matching the given filters
    public func fetchEvents(
        filters: [NDKFilter],
        relays: Set<NDKRelay>? = nil
    ) async throws -> Set<NDKEvent> {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        options.relays = relays
        
        let subscription = subscribe(filters: filters, options: options)
        
        // Wait for EOSE using the new callback-based approach
        await subscription.waitForEOSE()
        
        return Set(subscription.events)
    }
    
    /// Fetch a single event by ID
    public func fetchEvent(_ id: EventID, relays: Set<NDKRelay>? = nil) async throws -> NDKEvent? {
        let filter = NDKFilter(ids: [id])
        let events = try await fetchEvents(filters: [filter], relays: relays)
        return events.first
    }
    
    /// Fetch a single event matching the filter
    public func fetchEvent(_ filter: NDKFilter, relays: Set<NDKRelay>? = nil) async throws -> NDKEvent? {
        let events = try await fetchEvents(filters: [filter], relays: relays)
        return events.first
    }
    
    // MARK: - User Management
    
    /// Get a user by public key
    public func getUser(_ pubkey: PublicKey) -> NDKUser {
        let user = NDKUser(pubkey: pubkey)
        user.ndk = self
        return user
    }
    
    /// Get a user from npub
    public func getUser(npub: String) -> NDKUser? {
        guard let user = NDKUser(npub: npub) else { return nil }
        user.ndk = self
        return user
    }
}

// MARK: - Relay Pool Implementation

public class NDKRelayPool {
    private var relaysByUrl: [RelayURL: NDKRelay] = [:]
    
    func addRelay(_ url: RelayURL) -> NDKRelay {
        // Normalize the URL before storing
        let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        
        if let existing = relaysByUrl[normalizedUrl] {
            return existing
        }
        let relay = NDKRelay(url: normalizedUrl)
        relaysByUrl[normalizedUrl] = relay
        return relay
    }
    
    func removeRelay(_ url: RelayURL) {
        // Normalize the URL before removing
        let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(url) ?? url
        relaysByUrl.removeValue(forKey: normalizedUrl)
    }
    
    var relays: [NDKRelay] {
        return Array(relaysByUrl.values)
    }
    
    /// Get currently connected relays
    public func connectedRelays() -> [NDKRelay] {
        return relays.filter { $0.connectionState == .connected }
    }
    
    func connectAll() async {
        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    try? await relay.connect()
                }
            }
        }
    }
    
    func disconnectAll() async {
        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    await relay.disconnect()
                }
            }
        }
    }
}

// MARK: - Event Repository Implementation

class NDKEventRepository {
    private var events: [EventID: NDKEvent] = [:]
    private let queue = DispatchQueue(label: "com.ndkswift.eventrepository", attributes: .concurrent)
    
    func addEvent(_ event: NDKEvent) {
        guard let eventId = event.id else { return }
        
        queue.async(flags: .barrier) { [weak self] in
            self?.events[eventId] = event
        }
    }
    
    func getEvent(_ eventId: EventID) -> NDKEvent? {
        return queue.sync {
            return events[eventId]
        }
    }
    
    func getAllEvents() -> [NDKEvent] {
        return queue.sync {
            return Array(events.values)
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.events.removeAll()
        }
    }
}

// MARK: - Subscription Manager Implementation

class NDKSubscriptionManager {
    private var activeSubscriptions: [String: NDKSubscription] = [:]
    private let queue = DispatchQueue(label: "com.ndkswift.subscriptionmanager", attributes: .concurrent)
    
    func addSubscription(_ subscription: NDKSubscription) {
        queue.async(flags: .barrier) { [weak self] in
            self?.activeSubscriptions[subscription.id] = subscription
        }
    }
    
    func removeSubscription(_ subscriptionId: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.activeSubscriptions.removeValue(forKey: subscriptionId)
        }
    }
    
    func getSubscription(_ subscriptionId: String) -> NDKSubscription? {
        return queue.sync {
            return activeSubscriptions[subscriptionId]
        }
    }
    
    func getAllSubscriptions() -> [NDKSubscription] {
        return queue.sync {
            return Array(activeSubscriptions.values)
        }
    }
}

