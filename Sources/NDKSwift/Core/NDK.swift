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
    private var subscriptionManager: NDKSubscriptionManager!
    
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
        
        // Initialize subscription manager after all properties are set
        self.subscriptionManager = NDKSubscriptionManager(ndk: self)
        
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
        
        // Store in cache if available
        if let cache = cacheAdapter {
            await cache.setEvent(event, filters: [], relay: nil)
        }
        
        // Publish to relays
        let publishedRelays = await relayPool.publishEvent(event)
        
        if debugMode {
            let noteId = (try? Bech32.note(from: event.id ?? "")) ?? event.id ?? "unknown"
            let relayUrls = publishedRelays.map { $0.url }.joined(separator: ", ")
            print("📝 Published note \(noteId) to \(publishedRelays.count) relay(s): \(relayUrls)")
        }
        
        return publishedRelays
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
        
        // Use advanced subscription manager for optimized handling
        Task {
            await subscriptionManager.addSubscription(subscription)
        }
        
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
    
    // MARK: - Subscription Manager Integration
    
    /// Process an event received from a relay (called by relay connections)
    internal func processEvent(_ event: NDKEvent, from relay: NDKRelay) {
        Task {
            await subscriptionManager.processEvent(event, from: relay)
        }
    }
    
    /// Process EOSE received from a relay (called by relay connections)
    internal func processEOSE(subscriptionId: String, from relay: NDKRelay) {
        Task {
            await subscriptionManager.processEOSE(subscriptionId: subscriptionId, from: relay)
        }
    }
    
    /// Get subscription manager statistics
    public func getSubscriptionStats() async -> NDKSubscriptionManager.SubscriptionStats {
        return await subscriptionManager.getStats()
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
    
    /// Publish an event to all connected relays
    func publishEvent(_ event: NDKEvent) async -> Set<NDKRelay> {
        let connectedRelays = self.connectedRelays()
        var publishedRelays: Set<NDKRelay> = []
        
        await withTaskGroup(of: NDKRelay?.self) { group in
            for relay in connectedRelays {
                group.addTask {
                    do {
                        let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
                        try await relay.send(eventMessage.serialize())
                        return relay
                    } catch {
                        // Failed to send to this relay
                        return nil
                    }
                }
            }
            
            for await result in group {
                if let relay = result {
                    publishedRelays.insert(relay)
                }
            }
        }
        
        return publishedRelays
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


