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
    
    /// User and profile management
    internal var profileManager: NDKProfileManager!
    
    /// Event tracker for managing event metadata
    public let eventTracker: NDKEventTracker = NDKEventTracker()
    
    /// Internal subscription manager for DataRequirementManager
    internal var internalSubscriptionManager: InternalSubscriptionManager!
    
    /// Signature verification sampler
    private let signatureVerificationSampler: NDKSignatureVerificationSampler
    
    
    /// Data requirement manager for declarative data access
    internal var dataRequirementManager: NDKDataRequirementManager?
    
    /// Initial relay URLs to add after construction
    private var initialRelayUrls: [RelayURL] = []
    
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
        signatureVerificationConfig: NDKSignatureVerificationConfig = .default
    ) {
        self.signer = signer
        self.cache = cache ?? MemoryCache()
        self.signatureVerificationConfig = signatureVerificationConfig
        self.signatureVerificationSampler = NDKSignatureVerificationSampler(config: signatureVerificationConfig)
        
        // Initialize internal subscription manager
        self.internalSubscriptionManager = InternalSubscriptionManager(ndk: self)
        
        // Initialize managers
        self.eventManager = NDKEventManager(
            ndk: self,
            cache: self.cache
        )
        
        self.pool = NDKPool(
            ndk: self
        )
        
        // Subscription coordinator removed - using declarative API instead
        
        self.profileManager = NDKProfileManager(
            ndk: self
        )
        
        // Initialize data requirement manager for declarative API
        self.dataRequirementManager = NDKDataRequirementManager(ndk: self)
        
        // Set shared NDK instance for NDKEventBuilder
        NDKEventBuilder.setSharedNDK(self)
        
        // Store relay URLs for later initialization
        self.initialRelayUrls = relayUrls
    }
    
    
    // MARK: - Relay Management (Delegated to Pool)
    
    /// Wait for relay connections using proper async stream observation
    /// - Parameters:
    ///   - minimumRelays: Minimum number of relays to wait for (default: 1)
    ///   - timeout: Maximum time to wait in seconds (default: 5)
    /// - Returns: Number of connected relays
    @discardableResult
    public func waitForRelayConnections(minimumRelays: Int = 1, timeout: TimeInterval = 5.0) async -> Int {
        print("[waitForRelayConnections] Starting wait for \(minimumRelays) relays with timeout \(timeout)s")
        
        // Create a task that will timeout
        let timeoutTask = Task {
            print("[waitForRelayConnections] Timeout task started")
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            print("[waitForRelayConnections] Timeout reached!")
            return -1 // Sentinel value for timeout
        }
        
        // Create a task that monitors relay connections
        let connectionTask = Task { () -> Int in
            print("[waitForRelayConnections] Connection monitoring task started")
            var connectedCount = 0
            
            // Check initial state
            print("[waitForRelayConnections] Checking initial relay state...")
            connectedCount = await pool.connectedRelays().count
            print("[waitForRelayConnections] Initial connected relays: \(connectedCount)")
            if connectedCount >= minimumRelays {
                print("[waitForRelayConnections] Already have enough relays connected!")
                return connectedCount
            }
            
            // Monitor pool changes
            print("[waitForRelayConnections] Starting to monitor pool changes...")
            for await change in await pool.relayChanges {
                print("[waitForRelayConnections] Received pool change: \(change)")
                switch change {
                case .relayConnected:
                    connectedCount = await pool.connectedRelays().count
                    print("[waitForRelayConnections] Relay connected! Total: \(connectedCount)")
                    if connectedCount >= minimumRelays {
                        print("[waitForRelayConnections] Minimum relay count reached!")
                        return connectedCount
                    }
                case .relayDisconnected:
                    connectedCount = await pool.connectedRelays().count
                    print("[waitForRelayConnections] Relay disconnected! Total: \(connectedCount)")
                default:
                    print("[waitForRelayConnections] Other change: \(change)")
                    break
                }
            }
            
            print("[waitForRelayConnections] Pool changes stream ended")
            return connectedCount
        }
        
        // Race between timeout and connection
        print("[waitForRelayConnections] Starting race between timeout and connection tasks")
        let result = await withTaskGroup(of: Int.self) { group in
            group.addTask { await timeoutTask.value }
            group.addTask { await connectionTask.value }
            
            print("[waitForRelayConnections] Waiting for first task to complete...")
            if let firstResult = await group.next() {
                print("[waitForRelayConnections] First result received: \(firstResult)")
                // Cancel the other task
                group.cancelAll()
                let finalCount = firstResult == -1 ? await pool.connectedRelays().count : firstResult
                print("[waitForRelayConnections] Final count: \(finalCount)")
                return finalCount
            }
            
            print("[waitForRelayConnections] No task completed?")
            return 0
        }
        
        print("[waitForRelayConnections] Returning result: \(result)")
        return result
    }
    
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
    /// Initialize relays that were passed to the constructor
    /// This should be called before connect() to ensure relays are added
    public func initializeRelays() async {
        for url in initialRelayUrls {
            await addRelay(url)
        }
        initialRelayUrls.removeAll() // Clear after adding
    }
    
    /// Initiates WebSocket connections to all relays in the pool.
    /// Connections are managed automatically with reconnection logic.
    public func connect() async {
        // Ensure initial relays are added first
        if !initialRelayUrls.isEmpty {
            await initializeRelays()
        }
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
    public func publish(_ event: NDKEvent, to relayUrls: Set<String>? = nil, logRawJSON: Bool = false) async throws -> Set<NDKRelay> {
        if let relayUrls = relayUrls {
            try await eventManager.publish(event: event, to: relayUrls, logRawJSON: logRawJSON)
        } else {
            try await eventManager.publish(event, logRawJSON: logRawJSON)
        }
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
    
    // MARK: - Declarative Data Access
    
    /// Create a declarative data source for observing events
    /// 
    /// The returned data source automatically manages subscriptions, caching,
    /// and lifecycle. It's the primary API for accessing Nostr data.
    /// 
    /// ## Usage
    /// ```swift
    /// let profileData = NDKDataSource<NDKUserProfile>(
    ///     ndk: ndk,
    ///     filter: NDKFilter(authors: [pubkey], kinds: [0])
    /// ) { event in
    ///     // Transform event to profile
    ///     try? JSONDecoder().decode(NDKUserProfile.self, from: event.content.data(using: .utf8)!)
    /// }
    /// ```
    /// 
    /// - Parameters:
    ///   - filter: The filter to match events against
    ///   - transform: Optional transform function to convert NDKEvent to custom type
    /// - Returns: A data source that can be observed for changes
    @MainActor
    public func dataSource(
        filter: NDKFilter
    ) -> NDKDataSource<NDKEvent> {
        NDKDataSource(ndk: self, filter: filter) { $0 }
    }
    
    @MainActor
    public func dataSource<T>(
        filter: NDKFilter,
        transform: @escaping (NDKEvent) -> T?
    ) -> NDKDataSource<T> {
        NDKDataSource(ndk: self, filter: filter, transform: transform)
    }
    
    /// Observe events matching a filter with automatic subscription management
    /// 
    /// This is the primary API for declarative data access in NDKSwift.
    /// The returned data source automatically manages subscriptions, caching,
    /// and lifecycle.
    /// 
    /// ## Usage
    /// ```swift
    /// // Simple event observation
    /// let notes = ndk.observe(filter: NDKFilter(kinds: [1], limit: 20))
    /// 
    /// // With transform
    /// let profiles = ndk.observe(
    ///     filter: NDKFilter(authors: [pubkey], kinds: [0])
    /// ) { event in
    ///     try? JSONDecoder().decode(NDKUserProfile.self, from: event.content.data(using: .utf8)!)
    /// }
    /// 
    /// // With options
    /// let cachedEvents = ndk.observe(
    ///     filter: myFilter,
    ///     maxAge: 300,  // Use cache if less than 5 minutes old
    ///     cachePolicy: .cacheWithNetwork
    /// )
    /// ```
    /// 
    /// - Parameters:
    ///   - filter: The filter to match events against
    ///   - maxAge: Maximum age of cached data to consider fresh (in seconds).
    ///             0 = keep subscription open for real-time updates.
    ///             >0 = use cache if fresh enough, otherwise fetch and close after EOSE
    ///   - cachePolicy: Defines how the cache should be used for this request
    ///   - relays: Optional set of specific relay URLs to query
    ///   - transform: Optional transform function to convert NDKEvent to custom type
    /// - Returns: A data source that can be observed for changes
    public func observe(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil
    ) -> NDKDataSource<NDKEvent> {
        NDKDataSource(
            ndk: self,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays
        )
    }
    
    public func observe<T>(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        transform: @escaping (NDKEvent) -> T?
    ) -> NDKDataSource<T> {
        NDKDataSource(
            ndk: self,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            transform: transform
        )
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
    
    /// Create a reply event builder for NIP-22 comments
    /// 
    /// This method creates a properly configured event builder for replying to any event.
    /// It automatically handles:
    /// - Setting kind to 1111 (generic reply) for non-kind-1 events
    /// - Propagating uppercase tags (A, E, I, K, P) from parent comments
    /// - Adding proper lowercase tags (a, e, i, k, p) for the direct parent
    /// - Following NIP-22 threading conventions
    /// 
    /// ## Usage
    /// ```swift
    /// let comment = try await ndk.reply(to: blogPost)
    ///     .content("Great article!")
    ///     .build()
    /// ```
    /// 
    /// - Parameter event: The event to reply to
    /// - Returns: An NDKEventBuilder configured for the reply
    public func reply(to event: NDKEvent) -> NDKEventBuilder {
        let builder = NDKEventBuilder(ndk: self)
        
        // For kind 1 events, use standard kind 1 replies
        if event.kind == EventKind.textNote {
            builder.kind(EventKind.textNote)
            
            // Standard NIP-10 reply tags
            if event.tags.contains(where: { $0.first == "e" }) {
                // Copy existing e-tags and p-tags
                for tag in event.tags {
                    if tag.first == "e" || tag.first == "p" {
                        builder.tag(tag)
                    }
                }
                // Add reference to the event we're replying to
                builder.tag(["e", event.id, "", "reply"])
                builder.tag(["p", event.pubkey])
            } else {
                // This is a root event, tag it as such
                builder.tag(["e", event.id, "", "root"])
                builder.tag(["p", event.pubkey])
            }
        } else {
            // NIP-22 generic reply for all other kinds
            builder.kind(EventKind.genericReply)
            
            // Check if the parent event has uppercase tags (indicating it's a comment)
            let hasUppercaseTags = event.tags.contains { tag in
                ["A", "E", "I", "K", "P"].contains(tag.first)
            }
            
            if hasUppercaseTags {
                // Parent is a comment - copy its uppercase tags
                for tag in event.tags {
                    if ["A", "E", "I", "K", "P"].contains(tag.first) {
                        builder.tag(tag)
                    }
                }
            } else {
                // Parent is a root event - create new uppercase tags
                let tagReference = event.tagReference()
                let uppercaseTag = [tagReference[0].uppercased()] + Array(tagReference.dropFirst())
                builder.tag(uppercaseTag)
                
                // Add K tag for root kind
                builder.tag(["K", String(event.kind)])
                
                // Add P tag for root author
                builder.tag(["P", event.pubkey])
            }
            
            // Add lowercase tags for the direct parent
            let parentReference = event.tagReference()
            builder.tag(parentReference)
            
            // Add k tag for parent kind
            builder.tag(["k", String(event.kind)])
            
            // Add p tag for parent author
            builder.tag(["p", event.pubkey])
            
            // Carry over all p tags from parent
            for tag in event.tags where tag.first == "p" {
                if tag.count > 1 && tag[1] != event.pubkey {
                    builder.tag(tag)
                }
            }
        }
        
        return builder
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
    
    func processEvent(_ event: NDKEvent, subscriptionId: String, from relay: RelayProtocol) async {
        // Process event through cache for observation
        try? await cache.processEvent(event, from: relay.url, subscriptionId: subscriptionId)
        
        // Also process through internal subscription manager
        if let ndkRelay = relay as? NDKRelay {
            // Process through internal subscription manager with correct subscription ID
            await internalSubscriptionManager.processEvent(event, subscriptionId: subscriptionId, from: ndkRelay)
        }
    }
    
    func processEOSE(subscriptionId: String, from relay: RelayProtocol) {
        Task {
            await internalSubscriptionManager.processEOSE(subscriptionId: subscriptionId, from: relay)
        }
    }
    
    func processOKMessage(eventId: EventID, accepted: Bool, message: String?, from relay: RelayProtocol) async {
        if accepted {
            print("[NDK] Event \(eventId) accepted by relay \(relay.url)")
            
            // Always confirm event in cache
            do {
                try await cache.confirmEvent(eventId: eventId, onRelay: relay.url)
            } catch {
                print("[NDK] Warning: Failed to confirm event: \(error)")
            }
        } else {
            print("[NDK] Event \(eventId) rejected by relay \(relay.url): \(message ?? "No reason given")")
        }
    }
    
    func processNotice(message: String, from relay: RelayProtocol) {
        print("[NDK] Notice from \(relay.url): \(message)")
    }
    
    func processCount(subscriptionId: String, count: Int, from relay: RelayProtocol) {
        // Count messages not supported in declarative API yet
        print("[NDK] Received COUNT from \(relay.url): \(count)")
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
    
    // MARK: - Internal Fetch Utilities
    
    /// A robust internal utility for one-shot event fetching.
    /// This bypasses NDKDataSource and uses a temporary internal subscription
    /// that correctly waits for EOSE from relays.
    ///
    /// - Parameters:
    ///   - filter: The NDKFilter for the request.
    ///   - timeout: Request timeout in seconds.
    /// - Returns: An array of events matching the filter.
    internal func internalFetchEvents(
        filter: NDKFilter,
        timeout: TimeInterval = 10.0
    ) async throws -> [NDKEvent] {
        let subscriptionId = "internal-fetch-\(UUID().uuidString)"
        NDKLogger.log(.debug, category: .subscription, "[internalFetchEvents] Starting fetch with ID: \(subscriptionId), filter: \(filter.fingerprint)")
        
        // Create a temporary subscription that will close on EOSE
        let sub = await self.internalSubscriptionManager.createSubscription(
            id: subscriptionId,
            filters: [filter],
            relays: nil // Let the outbox model decide
        )
        
        var collectedEvents: [NDKEvent] = []
        var receivedEose = false
        
        // Register EOSE handler to close the subscription
        await sub.onEOSE { [weak sub] in
            NDKLogger.log(.debug, category: .subscription, "[internalFetchEvents] Received EOSE for \(subscriptionId)")
            receivedEose = true
            await sub?.close()
        }
        
        // Race the event collection against a timeout
        let result = await withTaskGroup(of: CollectionResult.self) { group in
            // Task to collect events
            group.addTask {
                // The stream will finish when the subscription is closed on EOSE
                for await (event, _) in await sub.events {
                    NDKLogger.log(.debug, category: .subscription, "[internalFetchEvents] Collected event: \(event.id)")
                    collectedEvents.append(event)
                }
                NDKLogger.log(.debug, category: .subscription, "[internalFetchEvents] Event stream ended for \(subscriptionId)")
                return CollectionResult.completed(collectedEvents)
            }
            
            // Task for timeout
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    // If we get here, timeout occurred
                    NDKLogger.log(.warning, category: .subscription, "[internalFetchEvents] Timeout reached for \(subscriptionId) after \(timeout)s")
                    return CollectionResult.timedOut
                } catch {
                    // Task was cancelled
                    return CollectionResult.cancelled
                }
            }
            
            // Wait for the first task to finish
            guard let firstResult = await group.next() else {
                return CollectionResult.cancelled
            }
            
            // Cancel the other task
            group.cancelAll()
            
            return firstResult
        }
        
        // Ensure cleanup
        if !receivedEose {
            await sub.close()
        }
        
        NDKLogger.log(.debug, category: .subscription, "[internalFetchEvents] Completed with \(collectedEvents.count) events, EOSE: \(receivedEose)")
        
        switch result {
        case .completed(let events):
            return events
        case .timedOut:
            // Return what we collected before timeout
            return collectedEvents
        case .cancelled:
            return collectedEvents
        }
    }
}

// Helper enum for task group results
private enum CollectionResult {
    case completed([NDKEvent])
    case timedOut
    case cancelled
}