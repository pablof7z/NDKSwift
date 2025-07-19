import Foundation

/// Main entry point for NDKSwift
public final class NDK {
    // MARK: - Core Properties
    
    /// Active signer for this NDK instance
    public var signer: NDKSigner?
    
    /// Cache for storing events (always present, defaults to in-memory)
    public let cache: NDKCache
    
    /// Active user (derived from signer)
    public var activeUser: NDKUser? {
        get async {
            guard let signer = signer else { return nil }
            return try? await signer.user()
        }
    }
    
    /// Whether debug mode is enabled
    public var debugMode: Bool = false
    
    /// Signature verification configuration
    public var signatureVerificationConfig: NDKSignatureVerificationConfig
    
    /// Signature verification delegate
    public weak var signatureVerificationDelegate: NDKSignatureVerificationDelegate?
    
    /// Whether outbox model is enabled (default: true)
    public var outboxEnabled: Bool = true
    
    /// Outbox configuration
    public var outboxConfig: NDKOutboxConfig = .default
    
    /// Configuration for optimistic publishing
    public var optimisticPublishingConfig: NDKOptimisticPublishingConfig = NDKOptimisticPublishingConfig()
    
    /// Configuration for automatic client tagging (NIP-89)
    public var clientTagConfig: NDKClientTagConfig?
    
    // MARK: - Outbox API
    
    /// Outbox manager - provides simplified API for outbox operations
    public private(set) lazy var outbox: NDKOutboxManager = {
        NDKOutboxManager(ndk: self)
    }()
    
    // MARK: - Internal Components
    
    /// Event publishing and management
    internal var eventManager: NDKEventManager!
    
    /// Relay pool management
    internal var pool: NDKPool!
    
    /// Subscription coordination
    internal var subscriptionCoordinator: NDKSubscriptionCoordinator!
    
    /// User and profile management
    internal var profileManager: NDKProfileManager!
    
    /// Event tracker for managing event metadata
    public let eventTracker: NDKEventTracker = NDKEventTracker()
    
    /// Subscription manager
    internal var subscriptionManager: NDKSubscriptionManager!
    
    /// Signature verification sampler
    private let signatureVerificationSampler: NDKSignatureVerificationSampler
    
    /// Subscription tracker for monitoring and debugging
    internal let subscriptionTracker: NDKSubscriptionTracker
    
    // MARK: - Lazy Internal Components
    
    internal var _outboxTracker: NDKOutboxTracker?
    internal var _relayRanker: NDKRelayRanker?
    internal var _relaySelector: NDKRelaySelector?
    internal var _publishingStrategy: NDKPublishingStrategy?
    internal var _fetchingStrategy: NDKFetchingStrategy?
    
    // MARK: - Computed Properties
    
    internal var relaySelector: NDKRelaySelector {
        if let existing = _relaySelector {
            return existing
        }
        let selector = NDKRelaySelector(ndk: self, tracker: outboxTracker, ranker: relayRanker)
        _relaySelector = selector
        return selector
    }
    
    private var fetchingStrategy: NDKFetchingStrategy {
        if let existing = _fetchingStrategy {
            return existing
        }
        let strategy = NDKFetchingStrategy(ndk: self, selector: self.relaySelector)
        _fetchingStrategy = strategy
        return strategy
    }
    
    // MARK: - Initialization
    
    public init(
        relayUrls: [RelayURL] = [],
        signer: NDKSigner? = nil,
        cache: NDKCache? = nil,
        signatureVerificationConfig: NDKSignatureVerificationConfig = .default,
        subscriptionTrackingConfig: SubscriptionTrackingConfig = .default
    ) {
        self.signer = signer
        self.cache = cache ?? MemoryCache()
        self.signatureVerificationConfig = signatureVerificationConfig
        self.signatureVerificationSampler = NDKSignatureVerificationSampler(config: signatureVerificationConfig)
        self.subscriptionTracker = NDKSubscriptionTracker(
            trackClosedSubscriptions: subscriptionTrackingConfig.trackClosedSubscriptions,
            maxClosedSubscriptions: subscriptionTrackingConfig.maxClosedSubscriptions
        )
        
        // Initialize subscription manager
        self.subscriptionManager = NDKSubscriptionManager(ndk: self)
        
        // Initialize managers
        self.eventManager = NDKEventManager(
            ndk: self,
            cache: self.cache,
            optimisticPublishingConfig: optimisticPublishingConfig
        )
        
        self.pool = NDKPool(
            ndk: self
        )
        
        self.subscriptionCoordinator = NDKSubscriptionCoordinator(
            ndk: self,
            subscriptionManager: subscriptionManager,
            subscriptionTracker: subscriptionTracker,
            cache: self.cache
        )
        
        self.profileManager = NDKProfileManager(
            ndk: self
        )
        
        // Set shared NDK instance for NDKEventBuilder
        NDKEventBuilder.setSharedNDK(self)
        
        // Add initial relays
        Task {
            for url in relayUrls {
                await addRelay(url)
            }
        }
    }
    
    // MARK: - Public Configuration
    
    public struct SubscriptionTrackingConfig {
        public var trackClosedSubscriptions: Bool
        public var maxClosedSubscriptions: Int
        
        public init(
            trackClosedSubscriptions: Bool = false,
            maxClosedSubscriptions: Int = 100
        ) {
            self.trackClosedSubscriptions = trackClosedSubscriptions
            self.maxClosedSubscriptions = maxClosedSubscriptions
        }
        
        public static let `default` = SubscriptionTrackingConfig()
    }
    
    // MARK: - Relay Management (Delegated to Pool)
    
    /// Add a relay to the pool (async version)
    @discardableResult
    public func addRelay(_ url: RelayURL) async -> NDKRelay {
        await pool.addRelay(url)
    }
    
    /// Add a relay to the pool and connect to it
    @discardableResult
    public func addRelayAndConnect(_ url: RelayURL) async -> NDKRelay? {
        await pool.addRelayAndConnect(url: url)
    }
    
    /// Remove a relay from the pool
    public func removeRelay(_ url: RelayURL) async {
        await pool.removeRelay(url)
    }
    
    public var relays: [NDKRelay] {
        get async {
            await pool.relays
        }
    }
    
    /// Stream of relay pool changes for event-driven observation
    public var relayChanges: AsyncStream<NDKPoolChangeEvent> {
        get async {
            await pool.relayChanges
        }
    }
    
    /// Get an observable relay collection for SwiftUI integration
    /// This provides a reactive view of relay states without modifying core architecture
    @MainActor
    public func createRelayCollection() -> NDKRelayCollection {
        return NDKRelayCollection(ndk: self)
    }
    
    /// Get a quick snapshot of relay connection states
    /// Useful for one-time status checks without setting up observers
    public func getRelayConnectionSummary() async -> (connected: Int, total: Int) {
        await pool.getConnectionSummary()
    }
    
    /// Connect to all configured relays
    /// 
    /// Initiates WebSocket connections to all relays in the pool.
    /// Connections are managed automatically with reconnection logic.
    public func connect() async {
        await pool.connectAll()
    }
    
    /// Disconnect from all relays
    /// 
    /// Closes all active WebSocket connections.
    /// Subscriptions will be preserved for reconnection.
    public func disconnect() async {
        await pool.disconnectAll()
    }
    
    // MARK: - Event Publishing (Delegated to EventManager)
    
    /// Publish an event to the network
    /// 
    /// The event will be published according to the configured publishing strategy.
    /// 
    /// - Parameters:
    ///   - event: The event to publish (must be signed)
    ///   - logRawJSON: If true, logs the raw JSON for debugging
    /// - Returns: Set of relays that accepted the event
    /// - Throws: NDKError if publishing fails
    public func publish(_ event: NDKEvent, logRawJSON: Bool = false) async throws -> Set<NDKRelay> {
        try await eventManager.publish(event, logRawJSON: logRawJSON)
    }
    
    public func publish(event: NDKEvent, to relayUrls: Set<String>) async throws -> Set<NDKRelay> {
        try await eventManager.publish(event: event, to: relayUrls)
    }
    
    public func publish(_ builder: (NDKEventBuilder) -> NDKEventBuilder) async throws -> (event: NDKEvent, relays: Set<NDKRelay>) {
        try await eventManager.publish(builder)
    }
    
    /// Retry publishing events that failed to publish
    /// 
    /// Attempts to republish events from the optimistic publishing queue.
    /// 
    /// - Parameters:
    ///   - maxAge: Maximum age of events to retry in seconds (default: 1 hour)
    ///   - limit: Maximum number of events to retry (nil for all)
    /// - Returns: Array of successfully republished events and their relays
    /// - Throws: NDKError if retry fails
    public func retryUnpublishedEvents(maxAge: TimeInterval = 3600, limit: Int? = nil) async throws -> [(event: NDKEvent, relays: Set<NDKRelay>)] {
        try await eventManager.retryUnpublishedEvents(maxAge: maxAge, limit: limit)
    }
    
    // MARK: - Subscriptions (Delegated to SubscriptionCoordinator)
    
    /// Subscribe to events matching the provided filters
    /// - Parameters:
    ///   - filters: Array of filters to match events against
    ///   - relays: Specific relays to use (nil uses default relay selection)
    ///   - id: Custom subscription ID (auto-generated if nil)
    ///   - closeOnEose: Whether to close subscription after receiving EOSE
    ///   - groupingDelay: Time to wait for batching subscriptions (default: 0.1s, set to 0 to disable)
    /// - Returns: An NDKSubscription that can be iterated over as an AsyncSequence
    public func subscribe(
        filters: [NDKFilter],
        relays: Set<RelayURL>? = nil,
        id: String? = nil,
        closeOnEose: Bool = false,
        groupingDelay: TimeInterval? = nil
    ) async -> NDKSubscription {
        await subscriptionCoordinator.subscribe(filters: filters, relays: relays, id: id, closeOnEose: closeOnEose, groupingDelay: groupingDelay)
    }
    
    /// Fetch events matching the given filters
    /// 
    /// This is a one-shot query that returns after receiving EOSE from relays.
    /// For continuous event streams, use `subscribe` instead.
    /// 
    /// - Parameters:
    ///   - filters: Array of filters to match events against
    ///   - relays: Specific relays to query (nil uses relay selection strategy)
    ///   - timeoutSeconds: Maximum time to wait for responses (default: 5s)
    /// - Returns: Array of events matching the filters
    /// - Throws: NDKError if the query times out or fails
    public func fetchEvents(
        _ filters: [NDKFilter],
        relays: Set<RelayURL>? = nil,
        timeoutSeconds: Int = 5
    ) async throws -> [NDKEvent] {
        try await subscriptionCoordinator.fetchEvents(filters, relays: relays, timeoutSeconds: timeoutSeconds)
    }
    
    /// Fetch a single event by its ID
    /// 
    /// - Parameters:
    ///   - id: The event ID to fetch
    ///   - relays: Specific relays to query (nil uses relay selection strategy)
    ///   - timeoutSeconds: Maximum time to wait for response (default: 5s)
    /// - Returns: The event if found, nil otherwise
    /// - Throws: NDKError if the query fails
    public func fetchEvent(
        id: EventID,
        relays: Set<RelayURL>? = nil,
        timeoutSeconds: Int = 5
    ) async throws -> NDKEvent? {
        print("[NDK.fetchEvent] Starting fetch for event ID: \(id), relays: \(relays?.joined(separator: ", ") ?? "nil"), timeout: \(timeoutSeconds)s")
        do {
            let result = try await subscriptionCoordinator.fetchEvent(id: id, relays: relays, timeoutSeconds: timeoutSeconds)
            print("[NDK.fetchEvent] Completed fetch for event ID: \(id), result: \(result != nil ? "found" : "not found")")
            return result
        } catch {
            print("[NDK.fetchEvent] Error fetching event ID: \(id), error: \(error)")
            throw error
        }
    }
    
    /// Fetch a single event matching the given filter
    /// 
    /// Returns the first event that matches the filter criteria.
    /// 
    /// - Parameters:
    ///   - filter: Filter criteria to match
    ///   - relays: Specific relays to query (nil uses relay selection strategy)
    ///   - timeoutSeconds: Maximum time to wait for response (default: 5s)
    /// - Returns: The first matching event if found, nil otherwise
    /// - Throws: NDKError if the query fails
    public func fetchEvent(
        _ filter: NDKFilter,
        relays: Set<RelayURL>? = nil,
        timeoutSeconds: Int = 5
    ) async throws -> NDKEvent? {
        print("[NDK.fetchEvent] Starting fetch with filter, relays: \(relays?.joined(separator: ", ") ?? "nil"), timeout: \(timeoutSeconds)s")
        do {
            let result = try await subscriptionCoordinator.fetchEvent(filter, relays: relays, timeoutSeconds: timeoutSeconds)
            print("[NDK.fetchEvent] Completed fetch with filter, result: \(result != nil ? "found" : "not found")")
            return result
        } catch {
            print("[NDK.fetchEvent] Error fetching with filter, error: \(error)")
            throw error
        }
    }
    
    /// Fetch a user's profile metadata
    /// 
    /// Retrieves the most recent kind:0 (metadata) event for the given user.
    /// Results are cached for efficient repeated queries.
    /// 
    /// - Parameters:
    ///   - pubkey: The user's public key
    ///   - forceRefresh: If true, bypasses cache and fetches from relays
    /// - Returns: The user's profile if found, nil otherwise
    /// - Throws: NDKError if the query fails
    public func fetchProfile(
        for pubkey: PublicKey,
        forceRefresh: Bool = false
    ) async throws -> NDKUserProfile? {
        try await profileManager.fetchProfile(for: pubkey, forceRefresh: forceRefresh)
    }
    
    /// Observe profile updates for a given pubkey
    /// Returns an AsyncSequence that yields the profile immediately if cached,
    /// then yields updates as they arrive from relays
    /// - Parameters:
    ///   - pubkey: The public key to observe
    ///   - closeOnEose: If true, closes the subscription after receiving initial data (EOSE)
    public func observeProfile(for pubkey: PublicKey, closeOnEose: Bool = false) async -> AsyncStream<NDKUserProfile?> {
        await profileManager.observeProfile(for: pubkey, closeOnEose: closeOnEose)
    }
    
    /// Get current subscription statistics
    /// 
    /// Provides insight into the subscription system's current state and performance.
    /// 
    /// - Returns: Statistics including active subscriptions, event counts, and performance metrics
    public func getSubscriptionStats() async -> NDKSubscriptionManager.SubscriptionStats {
        await subscriptionCoordinator.getSubscriptionStats()
    }
    
    /// Clear the entire relay list cache
    /// 
    /// Forces fresh fetching of relay lists (kind:10002) on next access.
    /// Useful when relay configurations have changed.
    public func clearRelayListCache() async {
        await subscriptionCoordinator.clearRelayListCache()
    }
    
    /// Clear relay list cache for specific author
    public func clearRelayListCache(for author: String) async {
        await subscriptionCoordinator.clearRelayListCache(for: author)
    }
    
    // MARK: - Event Building
    
    /// Create a new event builder with full NDK context
    /// 
    /// The returned builder has access to:
    /// - Automatic relay hint detection from event tracker
    /// - Cache access for user metadata
    /// - Default signer (if available)
    /// 
    /// ## Usage
    /// ```swift
    /// let event = try await ndk.event()
    ///     .content("Hello, Nostr!")
    ///     .kind(1)
    ///     .build() // Uses ndk.signer automatically
    /// ```
    public func event() -> NDKEventBuilder {
        return NDKEventBuilder(ndk: self)
    }
    
    // MARK: - User Management
    
    /// Get or create an NDKUser instance for a public key
    /// 
    /// User instances are cached and reused for efficiency.
    /// 
    /// - Parameter pubkey: The user's public key (hex format)
    /// - Returns: An NDKUser instance
    public func getUser(_ pubkey: PublicKey) -> NDKUser {
        let user = NDKUser(pubkey: pubkey)
        user.ndk = self
        return user
    }
    
    /// Get or create an NDKUser instance from an npub
    /// 
    /// - Parameter npub: The user's public key in bech32 format
    /// - Returns: An NDKUser instance if the npub is valid, nil otherwise
    public func getUser(npub: String) -> NDKUser? {
        guard let pubkey = try? PublicKey.fromNpub(npub) else {
            return nil
        }
        let user = NDKUser(pubkey: pubkey)
        user.ndk = self
        return user
    }
    
    // MARK: - Content Parsing (Now a utility)
    
    public func parseContent(
        _ content: String,
        tags: [[String]] = [],
        currentUser: NDKUser? = nil
    ) async -> NDKParsedContent {
        let result = ContentParser.parseContentWithContext(content, tags: tags, currentUser: currentUser)
        return result.parsedContent
    }
    
    // MARK: - Internal Methods (for relay communication)
    
    func processEvent(_ event: NDKEvent, from relay: RelayProtocol) async {
        await subscriptionCoordinator.processEvent(event, from: relay)
    }
    
    func processEOSE(subscriptionId: String, from relay: RelayProtocol) {
        Task {
            await subscriptionCoordinator.processEOSE(subscriptionId: subscriptionId, from: relay)
        }
    }
    
    func processOKMessage(eventId: EventID, accepted: Bool, message: String?, from relay: RelayProtocol) async {
        if accepted {
            print("[NDK] Event \(eventId) accepted by relay \(relay.url)")
            
            // Confirm event if optimistic publishing is enabled
            if optimisticPublishingConfig.enabled {
                do {
                    try await cache.confirmEvent(eventId: eventId, onRelay: relay.url)
                } catch {
                    print("[NDK] Warning: Failed to confirm event: \(error)")
                }
            }
        } else {
            print("[NDK] Event \(eventId) rejected by relay \(relay.url): \(message ?? "No reason given")")
        }
    }
    
    func processNotice(message: String, from relay: RelayProtocol) {
        print("[NDK] Notice from \(relay.url): \(message)")
    }
    
    func processCount(subscriptionId: String, count: Int, from relay: RelayProtocol) {
        Task {
            await subscriptionCoordinator.processCount(subscriptionId: subscriptionId, count: count, from: relay)
        }
    }
    
    func handleAuthChallenge(challenge: String, from relay: RelayProtocol) async {
        guard let signer = signer else {
            print("[NDK] Cannot respond to auth challenge - no signer available")
            return
        }
        
        do {
            let authEvent = try await self.event()
                .kind(EventKind.clientAuthentication)
                .tag(["challenge", challenge])
                .tag(["relay", relay.url])
                .build(signer: signer)
            
            // Create auth message manually for now
            let eventDict: [String: Any] = [
                "id": authEvent.id,
                "pubkey": authEvent.pubkey,
                "created_at": authEvent.createdAt,
                "kind": authEvent.kind,
                "tags": authEvent.tags,
                "content": authEvent.content,
                "sig": authEvent.sig
            ]
            let authMessage: [Any] = ["AUTH", eventDict]
            let jsonData = try JSONSerialization.data(withJSONObject: authMessage, options: [.withoutEscapingSlashes])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            try await relay.send(jsonString)
        } catch {
            print("[NDK] Failed to respond to auth challenge: \(error)")
        }
    }
    
    // MARK: - Signature Verification
    
    public func getSignatureVerificationStats() async -> (totalVerifications: Int, failedVerifications: Int, blacklistedRelays: Int) {
        await signatureVerificationSampler.getStats()
    }
    
    public func isRelayBlacklisted(_ relay: NDKRelay) async -> Bool {
        await signatureVerificationSampler.isRelayBlacklisted(relay.url)
    }
    
    public func getBlacklistedRelays() async -> Set<String> {
        await signatureVerificationSampler.getBlacklistedRelays()
    }
    
    public func clearSignatureCache() async {
        await signatureVerificationSampler.clearCache()
    }
    
    public func setSignatureVerificationDelegate(_ delegate: NDKSignatureVerificationDelegate) async {
        self.signatureVerificationDelegate = delegate
    }
    
    // MARK: - Advanced Pool Access (for internal use)
    
    /// Get connected relays - primarily for internal use
    internal func connectedRelays() async -> [NDKRelay] {
        await pool.connectedRelays()
    }
    
    /// Get a specific relay - primarily for internal use
    internal func getRelay(for url: RelayURL) async -> NDKRelay? {
        await pool.getRelay(for: url)
    }
    
    // MARK: - NIP-77 Support
    
    /// Process NIP-77 Negentropy message from relay
    internal func processNIP77Message(_ message: NostrMessage, from relay: NDKRelay) async {
        print("[NDK] Processing NIP-77 message from \(relay.url)")
        
        // Get the sync handler for this relay
        guard let handler = await pool.getSyncHandler(for: relay.url) else {
            print("⚠️ Received NIP-77 message but no sync handler found for \(relay.url)")
            return
        }
        
        print("[NDK] Found sync handler, processing message...")
        
        // Process the message
        do {
            try await handler.handleMessage(message)
        } catch {
            print("❌ Failed to handle NIP-77 message: \(error)")
        }
    }
}