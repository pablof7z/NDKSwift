import Foundation

/// Protocol for handling relay authentication requests (NIP-42)
public protocol NDKAuthenticationDelegate: AnyObject {
    /// Called when a relay requires authentication
    /// - Parameters:
    ///   - relay: The relay requiring authentication
    ///   - challenge: The authentication challenge from the relay
    /// - Returns: true to proceed with authentication, false to decline
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool
}

/// Main entry point for NDKSwift
public final class NDK {
    // MARK: - Core Properties

    /// Active signer for this NDK instance
    public var signer: NDKSigner?

    /// Active session data for reactive filters
    public internal(set) var sessionData: NDKSessionData?

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

    /// Authentication delegate for handling relay authentication (NIP-42)
    public weak var authenticationDelegate: NDKAuthenticationDelegate?

    /// Whether outbox model is enabled (default: true)
    public var outboxEnabled: Bool = true

    /// Outbox configuration
    public var outboxConfig: NDKOutboxConfig = .default

    /// Configuration for automatic client tagging (NIP-89)
    public var clientTagConfig: NDKClientTagConfig?

    /// Track pending auth events by event ID to relay
    private var pendingAuthEvents: [EventID: NDKRelay] = [:]

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
    public private(set) var profileManager: NDKProfileManager!

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
    internal var _nip05Manager: NIP05Manager?

    // MARK: - Computed Properties

    /// Helper to lazily initialize properties
    internal func lazyInit<T>(_ storage: inout T?, creator: () -> T) -> T {
        if let existing = storage {
            return existing
        }
        let newValue = creator()
        storage = newValue
        return newValue
    }

    internal var relaySelector: NDKRelaySelector {
        lazyInit(&_relaySelector) {
            NDKRelaySelector(ndk: self, tracker: outboxTracker, ranker: relayRanker)
        }
    }

    /// NIP-05 manager for efficient resolution and caching
    public var nip05Manager: NIP05Manager {
        lazyInit(&_nip05Manager) {
            NIP05Manager(ndk: self)
        }
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

        // Initialize internal subscription manager (must be early for event routing)
        self.internalSubscriptionManager = InternalSubscriptionManager(ndk: self)

        // Initialize core managers
        // Note: These are initialized directly (not lazy) because they're essential
        // for basic NDK operation and have interdependencies during startup
        self.eventManager = NDKEventManager(
            ndk: self,
            cache: self.cache
        )

        self.pool = NDKPool(
            ndk: self
        )

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
    public func waitForRelayConnections(minimumRelays: Int = 1, timeout: TimeInterval = NetworkConstants.timeoutSubscription) async -> Int {
        NDKLogger.log(.debug, category: .relay, "Starting wait for \(minimumRelays) relays with timeout \(timeout)s")

        // Create a task that will timeout
        let timeoutTask = Task {
            NDKLogger.log(.trace, category: .relay, "Timeout task started")
            try? await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
            NDKLogger.log(.debug, category: .relay, "Timeout reached!")
            return -1 // Sentinel value for timeout
        }

        // Create a task that monitors relay connections
        let connectionTask = Task { () -> Int in
            NDKLogger.log(.trace, category: .relay, "Connection monitoring task started")
            var connectedCount = 0

            // Check initial state
            NDKLogger.log(.trace, category: .relay, "Checking initial relay state...")
            connectedCount = await pool.connectedRelays().count
            NDKLogger.log(.debug, category: .relay, "Initial connected relays: \(connectedCount)")
            if connectedCount >= minimumRelays {
                NDKLogger.log(.info, category: .relay, "Already have enough relays connected!")
                return connectedCount
            }

            // Monitor pool changes
            NDKLogger.log(.trace, category: .relay, "Starting to monitor pool changes...")
            for await change in await pool.relayChanges {
                NDKLogger.log(.trace, category: .relay, "Received pool change: \(change)")
                switch change {
                case .relayConnected:
                    connectedCount = await pool.connectedRelays().count
                    NDKLogger.log(.info, category: .relay, "Relay connected! Total: \(connectedCount)")
                    if connectedCount >= minimumRelays {
                        NDKLogger.log(.info, category: .relay, "Minimum relay count reached!")
                        return connectedCount
                    }
                case .relayDisconnected:
                    connectedCount = await pool.connectedRelays().count
                    NDKLogger.log(.info, category: .relay, "Relay disconnected! Total: \(connectedCount)")
                default:
                    NDKLogger.log(.trace, category: .relay, "Other change: \(change)")
                    break
                }
            }

            NDKLogger.log(.debug, category: .relay, "Pool changes stream ended")
            return connectedCount
        }

        // Race between timeout and connection
        NDKLogger.log(.trace, category: .relay, "Starting race between timeout and connection tasks")
        let result = await withTaskGroup(of: Int.self) { group in
            group.addTask { await timeoutTask.value }
            group.addTask { await connectionTask.value }

            NDKLogger.log(.trace, category: .relay, "Waiting for first task to complete...")
            if let firstResult = await group.next() {
                NDKLogger.log(.debug, category: .relay, "First result received: \(firstResult)")
                // Cancel the other task
                group.cancelAll()
                let finalCount = firstResult == -1 ? await pool.connectedRelays().count : firstResult
                NDKLogger.log(.debug, category: .relay, "Final count: \(finalCount)")
                return finalCount
            }

            NDKLogger.log(.warning, category: .relay, "No task completed?")
            return 0
        }

        NDKLogger.log(.debug, category: .relay, "Returning result: \(result)")
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
            NDKLogger.log(.info, category: .relay, "Adding \(initialRelayUrls.count) initial relay(s) from configuration")
            await initializeRelays()
        }

        // Add outbox relays from config
        if !outboxConfig.outboxRelays.isEmpty {
            NDKLogger.log(.info, category: .relay, "Adding \(outboxConfig.outboxRelays.count) outbox relay(s) from configuration")
            for relayUrl in outboxConfig.outboxRelays {
                await pool.addRelay(relayUrl, origin: .outboxConfig)
            }
        }

        NDKLogger.log(.info, category: .relay, "Connecting to all relays in pool")
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
    public func retryUnpublishedEvents(maxAge: TimeInterval = TimeConstants.hour, limit: Int? = nil) async throws -> [(event: NDKEvent, relays: Set<NDKRelay>)] {
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
    ///     try? JSONCoding.decode(NDKUserProfile.self, from: event.content)
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
    ///     try? JSONCoding.decode(NDKUserProfile.self, from: event.content)
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
    ///   - exclusiveRelays: If true, only process events from the specified relays (default: false).
    ///                      When false, events from any relay are processed.
    ///   - subscriptionId: Optional custom subscription ID for debugging/tracing.
    ///                     This ID will be used in REQ messages sent to relays.
    ///   - transform: Optional transform function to convert NDKEvent to custom type
    /// - Returns: A data source that can be observed for changes
    public func observe(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool? = nil
    ) -> NDKDataSource<NDKEvent> {
        // Smart default: close on EOSE if maxAge > 0, otherwise stay open
        let shouldCloseOnEose = closeOnEose ?? (maxAge > 0)
        
        return NDKDataSource(
            ndk: self,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            exclusiveRelays: exclusiveRelays,
            subscriptionId: subscriptionId,
            closeOnEose: shouldCloseOnEose
        )
    }

    public func observe<T>(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool? = nil,
        transform: @escaping (NDKEvent) -> T?
    ) -> NDKDataSource<T> {
        // Smart default: close on EOSE if maxAge > 0, otherwise stay open
        let shouldCloseOnEose = closeOnEose ?? (maxAge > 0)
        
        return NDKDataSource(
            ndk: self,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            exclusiveRelays: exclusiveRelays,
            subscriptionId: subscriptionId,
            closeOnEose: shouldCloseOnEose,
            transform: transform
        )
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
        // Track that we've seen this event on this relay
        // If this is the first time we see this event, also set it as the source relay
        let seenRelays = await eventTracker.getSeenOnRelays(eventId: event.id)
        if seenRelays.isEmpty {
            await eventTracker.setSourceRelay(eventId: event.id, relay: relay.url)
        } else {
            await eventTracker.markSeen(eventId: event.id, relay: relay.url)
        }
        
        // Process event through cache for observation
        do {
            try await cache.processEvent(event, from: relay.url, subscriptionId: subscriptionId)
        } catch {
            NDKLogger.log(.error, category: .event, "❌ Cache processing failed: \(error)")
        }

        // Also process through internal subscription manager
        if let ndkRelay = relay as? NDKRelay {
            NDKLogger.log(.trace, category: .event, "🔄 Routing to internal subscription manager")
            // Process through internal subscription manager with correct subscription ID
            await internalSubscriptionManager.processEvent(event, subscriptionId: subscriptionId, from: ndkRelay)
        } else {
            NDKLogger.log(.warning, category: .event, "⚠️ Relay is not NDKRelay type - cannot route to subscription manager")
        }
    }

    func processEOSE(subscriptionId: String, from relay: RelayProtocol) {
        Task {
            await internalSubscriptionManager.processEOSE(subscriptionId: subscriptionId, from: relay)
        }
    }

    func processOKMessage(eventId: EventID, accepted: Bool, message: String?, from relay: RelayProtocol) async {
        // Check if this is an auth event response
        if let authRelay = pendingAuthEvents.removeValue(forKey: eventId) {
            if accepted {
                // Authentication successful
                await authRelay.updateConnectionState(.authenticated)
                NDKLogger.log(.info, category: .auth, "Successfully authenticated with relay \(relay.url)")
                
                // Trigger retry of failed publishes
                await retryFailedPublishesForRelay(authRelay)
            } else {
                // Authentication failed, revert to connected state
                await authRelay.updateConnectionState(.connected)
                NDKLogger.log(.error, category: .auth, "Authentication failed for relay \(relay.url): \(message ?? "No reason given")")
            }
            return
        }
        
        // Regular event processing
        if accepted {
            // Always confirm event in cache
            do {
                try await cache.confirmEvent(eventId: eventId, onRelay: relay.url)
            } catch {
                NDKLogger.log(.warning, category: .event, "Failed to confirm event: \(error)")
            }
        } else {
            NDKLogger.log(.warning, category: .event, "Event \(eventId) rejected by relay \(relay.url): \(message ?? "No reason given")")
            
            // Check if rejection was due to auth required
            if let errorMessage = message?.lowercased(),
               (errorMessage.contains("auth") || errorMessage.contains("restricted") || errorMessage.contains("authentication")),
               let ndkRelay = relay as? NDKRelay {
                
                NDKLogger.log(.info, category: .auth, "Event \(eventId) requires authentication on \(relay.url)")
                
                // Update relay state to indicate auth is required
                // The relay should send an AUTH challenge message soon
                let currentState = await ndkRelay.connectionState
                if case .connected = currentState {
                    // Don't update if we're already in an auth flow
                    NDKLogger.log(.debug, category: .auth, "Relay \(relay.url) requires authentication for publishing")
                }
            }
        }
    }

    func processNotice(message: String, from relay: RelayProtocol) {
        NDKLogger.log(.info, category: .relay, "Notice from \(relay.url): \(message)")
    }

    func processCount(subscriptionId: String, count: Int, from relay: RelayProtocol) {
        // Count messages not supported in declarative API yet
        NDKLogger.log(.debug, category: .event, "Received COUNT from \(relay.url): \(count)")
    }

    func handleAuthChallenge(challenge: String, from relay: RelayProtocol) async {
        guard let ndkRelay = relay as? NDKRelay else {
            NDKLogger.log(.warning, category: .auth, "Cannot handle auth challenge - relay is not NDKRelay")
            return
        }

        // Update relay state to authRequired
        await ndkRelay.updateConnectionState(.authRequired(challenge: challenge))

        // Check if we should authenticate
        let shouldAuthenticate: Bool
        if let delegate = authenticationDelegate {
            shouldAuthenticate = await delegate.relay(ndkRelay, requiresAuthenticationWithChallenge: challenge)
        } else {
            // Default behavior: authenticate if we have a signer
            shouldAuthenticate = signer != nil
            NDKLogger.log(.debug, category: .auth, "No authentication delegate set, defaulting to \(shouldAuthenticate ? "authenticating" : "not authenticating")")
        }

        guard shouldAuthenticate else {
            NDKLogger.log(.info, category: .auth, "Authentication declined for relay \(relay.url)")
            return
        }

        guard let signer = signer else {
            NDKLogger.log(.warning, category: .auth, "Cannot respond to auth challenge - no signer available")
            return
        }

        // Update state to authenticating
        await ndkRelay.updateConnectionState(.authenticating)

        do {
            let authEvent = try await NDKEventBuilder(ndk: self)
                .kind(EventKind.clientAuthentication)
                .tag([NostrConstants.TagName.challenge, challenge])
                .tag([NostrConstants.TagName.relay, relay.url])
                .build(signer: signer)

            // Create auth message manually for now
            let eventDict: [String: Any] = [
                NostrConstants.JSONField.id: authEvent.id,
                NostrConstants.JSONField.pubkey: authEvent.pubkey,
                NostrConstants.JSONField.createdAt: authEvent.createdAt,
                NostrConstants.JSONField.kind: authEvent.kind,
                NostrConstants.JSONField.tags: authEvent.tags,
                NostrConstants.JSONField.content: authEvent.content,
                NostrConstants.JSONField.sig: authEvent.sig
            ]
            let authMessage: [Any] = ["AUTH", eventDict]
            let jsonData = try JSONSerialization.data(withJSONObject: authMessage, options: [.withoutEscapingSlashes])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            
            // Track pending auth event
            pendingAuthEvents[authEvent.id] = ndkRelay
            
            try await relay.send(jsonString)
            
            // The OK response will trigger state change to authenticated
        } catch {
            NDKLogger.log(.error, category: .auth, "Failed to respond to auth challenge: \(error)")
            // Revert to connected state on failure
            await ndkRelay.updateConnectionState(.connected)
        }
    }

    // MARK: - Authentication Helpers
    
    /// Notifies that a relay has been authenticated
    /// Apps can listen to relay state changes to retry failed publishes
    private func retryFailedPublishesForRelay(_ relay: NDKRelay) async {
        NDKLogger.log(.info, category: .auth, "Relay \(relay.url) is now authenticated - apps can retry failed publishes")
        // Apps should listen to relay state changes and retry publishes when state becomes .authenticated
    }

    // MARK: - Signature Verification

    /// Get statistics about signature verification performance
    /// - Returns: A tuple containing:
    ///   - totalVerifications: Total number of signature verifications performed
    ///   - failedVerifications: Number of signature verifications that failed
    ///   - blacklistedRelays: Number of relays currently blacklisted due to signature failures
    public func getSignatureVerificationStats() async -> (totalVerifications: Int, failedVerifications: Int, blacklistedRelays: Int) {
        await signatureVerificationSampler.getStats()
    }

    /// Check if a relay is blacklisted due to signature verification failures
    /// - Parameter relay: The relay to check
    /// - Returns: true if the relay is blacklisted, false otherwise
    public func isRelayBlacklisted(_ relay: NDKRelay) async -> Bool {
        await signatureVerificationSampler.isRelayBlacklisted(relay.url)
    }

    /// Get the set of relay URLs that are currently blacklisted
    /// - Returns: Set of blacklisted relay URLs
    public func getBlacklistedRelays() async -> Set<String> {
        await signatureVerificationSampler.getBlacklistedRelays()
    }

    /// Clear the signature verification cache
    /// - Note: This can be useful for testing or when you want to force re-verification
    public func clearSignatureCache() async {
        await signatureVerificationSampler.clearCache()
    }

    /// Set a custom delegate for signature verification
    /// - Parameter delegate: The delegate that will handle signature verification decisions
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
        NDKLogger.log(.debug, category: .sync, "Processing NIP-77 message from \(relay.url)")

        // Get the sync handler for this relay
        guard let handler = await pool.getSyncHandler(for: relay.url) else {
            NDKLogger.log(.warning, category: .sync, "⚠️ Received NIP-77 message but no sync handler found for \(relay.url)")
            return
        }

        NDKLogger.log(.trace, category: .sync, "Found sync handler, processing message...")

        // Process the message
        do {
            try await handler.handleMessage(message)
        } catch {
            NDKLogger.log(.error, category: .sync, "❌ Failed to handle NIP-77 message: \(error)")
        }
    }


    // MARK: - NIP-05 Search

    /// Search for NIP-05 identifiers by prefix (for autocomplete)
    /// - Parameters:
    ///   - query: The search prefix
    ///   - limit: Maximum number of results (default: 10)
    /// - Returns: Array of tuples containing user, NIP-05 identifier, and verification status
    public func searchNIP05(_ query: String, limit: Int = 10) async -> [(user: NDKUser, nip05: String, status: NIP05VerificationStatus)] {
        let entries = await nip05Manager.search(query, limit: limit)

        return entries.map { entry in
            let user = NDKUser(pubkey: entry.pubkey)
            user.ndk = self
            return (user: user, nip05: entry.identifier, status: entry.status)
        }
    }

    /// Verify a NIP-05 identifier for a user
    /// - Parameters:
    ///   - user: The user whose NIP-05 to verify
    ///   - maxAge: Maximum age before re-verification is needed (default: 24 hours)
    /// - Returns: True if the NIP-05 is verified and belongs to this user
    public func verifyNIP05(for user: NDKUser, maxAge: TimeInterval = TimeConstants.day) async throws -> Bool {
        guard let nip05 = await user.nip05 else { return false }
        return try await nip05Manager.verify(identifier: nip05, expectedPubkey: user.pubkey, maxAge: maxAge)
    }

    // MARK: - Internal Fetch Utilities

}
