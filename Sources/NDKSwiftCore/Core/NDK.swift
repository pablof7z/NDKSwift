import Foundation

/// Protocol for handling relay authentication requests (NIP-42)
public protocol NDKAuthenticationDelegate: AnyObject, Sendable {
    /// Called when a relay requires authentication
    /// - Parameters:
    ///   - relay: The relay requiring authentication
    ///   - challenge: The authentication challenge from the relay
    /// - Returns: true to proceed with authentication, false to decline
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool
}

/// Main entry point for NDKSwift
/// **Sendable Conformance**: Uses @unchecked Sendable because:
/// - NDK is designed as a singleton-style coordinator accessed from multiple contexts
/// - Internal state is protected by actors (PendingAuthEventsManager, etc.)
/// - Mutable properties (signer, cache, pool) are thread-safe types or accessed via MainActor
/// - Typical usage pattern: created once, configured early, then used read-only
public final class NDK: @unchecked Sendable {
    // MARK: - Core Properties

    /// Active signer for this NDK instance
    public var signer: NDKSigner?

    /// Active session data for reactive filters
    public internal(set) var sessionData: NDKSessionData?

    /// Zap manager for handling payments and zaps
    public var zapManager: (any ZapManaging)?

    /// Cache for storing events (always present, defaults to in-memory)
    public var cache: NDKCache

    /// Active user (derived from signer)
    public var activeUser: NDKUser? {
        get async {
            guard let signer = signer else { return nil }
            do {
                return try await signer.user()
            } catch {
                NDKLogger.log(.warning, category: .signer, "Failed to get active user from signer: \(error.localizedDescription)")
                return nil
            }
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

    /// Actor to manage thread-safe access to pending auth events
    private actor PendingAuthEventsManager {
        private var pendingAuthEvents: [EventID: NDKRelay] = [:]

        func setPendingAuthEvent(eventId: EventID, relay: NDKRelay) {
            pendingAuthEvents[eventId] = relay
        }

        func removePendingAuthEvent(for eventId: EventID) -> NDKRelay? {
            return pendingAuthEvents.removeValue(forKey: eventId)
        }
    }

    /// Track pending auth events by event ID to relay
    private let pendingAuthEventsManager = PendingAuthEventsManager()

    // MARK: - Outbox API

    /// Outbox manager - provides simplified API for outbox operations
    public private(set) lazy var outbox: NDKOutboxManager = .init(ndk: self)

    // MARK: - Internal Components

    /// Event publishing and management
    var eventManager: NDKEventManager!

    /// Relay pool management
    public var pool: NDKPool!

    /// User and profile management
    public private(set) var profileManager: NDKProfileManager!

    /// Event tracker for managing event metadata
    public let eventTracker: NDKEventTracker = .init()

    /// Internal subscription manager for NDKSubscriptionManager
    var internalSubscriptionManager: InternalSubscriptionManager!

    /// Signature verification sampler
    private let signatureVerificationSampler: NDKSignatureVerificationSampler

    /// Data requirement manager for declarative data access
    var dataRequirementManager: NDKSubscriptionManager?

    /// Initial relay URLs to add after construction
    private var initialRelayUrls: [RelayURL] = []

    /// Track whether connect() has been called
    private var hasConnected = false

    // MARK: - Lazy Internal Components

    var _relayRanker: NDKRelayRanker?
    var _relaySelector: NDKRelaySelector?
    var _publishingStrategy: NDKPublishingStrategy?
    var _nip05Manager: NIP05Manager?
    var _blossomServerManager: NDKBlossomServerManager?

    // MARK: - Computed Properties

    /// Helper to lazily initialize properties
    func lazyInit<T>(_ storage: inout T?, creator: () -> T) -> T {
        if let existing = storage {
            return existing
        }
        let newValue = creator()
        storage = newValue
        return newValue
    }

    var relaySelector: NDKRelaySelector {
        lazyInit(&_relaySelector) {
            NDKRelaySelector(ndk: self, tracker: outbox, ranker: relayRanker)
        }
    }

    /// NIP-05 manager for efficient resolution and caching
    public var nip05Manager: NIP05Manager {
        lazyInit(&_nip05Manager) {
            NIP05Manager(ndk: self)
        }
    }

    /// Blossom server manager for managing server lists and uploads
    public var blossomServerManager: NDKBlossomServerManager {
        lazyInit(&_blossomServerManager) {
            NDKBlossomServerManager(ndk: self)
        }
    }

    // MARK: - Initialization

    /// Initialize NDK with a custom cache instance
    /// - Parameters:
    ///   - relayUrls: Initial relay URLs to connect to
    ///   - signer: Optional signer for signing events
    ///   - cache: Custom cache instance. If nil, uses MemoryCache
    ///   - signatureVerificationConfig: Configuration for signature verification
    public init(
        relayUrls: [RelayURL] = [],
        signer: NDKSigner? = nil,
        cache: NDKCache? = nil,
        signatureVerificationConfig: NDKSignatureVerificationConfig = .default
    ) {
        self.signer = signer
        self.cache = cache ?? MemoryCache()
        self.signatureVerificationConfig = signatureVerificationConfig
        signatureVerificationSampler = NDKSignatureVerificationSampler(config: signatureVerificationConfig)

        // Auth manager is now lazy-initialized on first access from MainActor

        // Initialize internal subscription manager (must be early for event routing)
        internalSubscriptionManager = InternalSubscriptionManager(ndk: self)

        // Initialize core managers
        // Note: These are initialized directly (not lazy) because they're essential
        // for basic NDK operation and have interdependencies during startup
        eventManager = NDKEventManager(
            ndk: self,
            cache: self.cache
        )

        pool = NDKPool(
            ndk: self
        )

        profileManager = NDKProfileManager(
            ndk: self
        )

        // Initialize data requirement manager for declarative API
        dataRequirementManager = NDKSubscriptionManager(ndk: self)

        // Set shared NDK instance for NDKEventBuilder
        NDKEventBuilder.setSharedNDK(self)

        // Store relay URLs for later initialization
        initialRelayUrls = relayUrls
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
    public func addRelay(_ url: RelayURL, origin: NDKRelayOrigin = .explicit) async -> NDKRelay {
        let relay = await pool.addRelay(url, origin: origin)

        if hasConnected {
            // Auto-connect the relay since connect() has already been called
            NDKLogger.log(.info, category: .relay, "Auto-connecting relay \(url) since connect() has been called")
            do {
                try await relay.connect()
            } catch {
                NDKLogger.log(.error, category: .relay, "Failed to auto-connect relay \(url): \(error)")
            }
        } else {
            // Warn that the relay won't be connected until connect() is called
            NDKLogger.log(.warning, category: .relay, "⚠️ Relay \(url) added but not connected. Call connect() to establish connections to all relays.")
        }

        return relay
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

        // Mark that connect has been called
        hasConnected = true
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

    public func publish(_ builder: @Sendable (NDKEventBuilder) -> NDKEventBuilder) async throws -> (event: NDKEvent, relays: Set<NDKRelay>) {
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
    /// let profileData = NDKSubscription<NDKUserMetadata>(
    ///     ndk: ndk,
    ///     filter: NDKFilter(authors: [pubkey], kinds: [0])
    /// ) { event in
    ///     // Transform event to metadata
    ///     NDKUserMetadata(event: event)
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
    ) -> NDKSubscription<NDKEvent> {
        NDKSubscription(ndk: self, filter: filter) { $0 }
    }

    @MainActor
    public func dataSource<T>(
        filter: NDKFilter,
        transform: @escaping @Sendable (NDKEvent) -> T?
    ) -> NDKSubscription<T> {
        NDKSubscription(ndk: self, filter: filter, transform: transform)
    }

    /// Observe events matching a filter with automatic subscription management
    ///
    /// This is the primary API for declarative data access in NDKSwift.
    /// The returned data source automatically manages subscriptions, caching,
    /// and lifecycle.
    ///
    /// ## Usage
    /// ```swift
    /// // Simple event subscription
    /// let notes = ndk.subscribe(filter: NDKFilter(kinds: [1], limit: 20))
    ///
    /// // With transform
    /// let profiles = ndk.subscribe(
    ///     filter: NDKFilter(authors: [pubkey], kinds: [0])
    /// ) { event in
    ///     NDKUserMetadata(event: event)
    /// }
    ///
    /// // With options
    /// let cachedEvents = ndk.subscribe(
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
    /// - Returns: A subscription that can be observed for changes
    public func subscribe(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool? = nil
    ) -> NDKSubscription<NDKEvent> {
        // Smart default: close on EOSE if maxAge > 0, otherwise stay open
        let shouldCloseOnEose = closeOnEose ?? (maxAge > 0)

        return NDKSubscription(
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

    /// Subscribe to events with custom options
    public func subscribe(
        filter: NDKFilter,
        options: NDKSubscriptionOptions? = nil
    ) -> NDKSubscription<NDKEvent> {
        let opts = options ?? .default
        return NDKSubscription(
            ndk: self,
            filter: filter,
            options: opts
        )
    }

    public func subscribe<T>(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool? = nil,
        transform: @escaping @Sendable (NDKEvent) -> T?
    ) -> NDKSubscription<T> {
        // Smart default: close on EOSE if maxAge > 0, otherwise stay open
        let shouldCloseOnEose = closeOnEose ?? (maxAge > 0)

        return NDKSubscription(
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
    public func getUser(_ pubkey: PublicKey) async -> NDKUser {
        let user = NDKUser(pubkey: pubkey)
        await user.setNdk(self)
        return user
    }

    /// Get or create an NDKUser instance from an npub
    ///
    /// - Parameter npub: The user's public key in bech32 format
    /// - Returns: An NDKUser instance if the npub is valid, nil otherwise
    public func getUser(npub: String) async -> NDKUser? {
        let pubkey: PublicKey
        do {
            guard let pk = try PublicKey.fromNpub(npub) else {
                NDKLogger.log(.warning, category: .event, "Failed to parse npub \(npub.prefix(16)): returned nil")
                return nil
            }
            pubkey = pk
        } catch {
            NDKLogger.log(.warning, category: .event, "Failed to parse npub \(npub.prefix(16)): \(error.localizedDescription)")
            return nil
        }
        let user = NDKUser(pubkey: pubkey)
        await user.setNdk(self)
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
        NDKLogger.log(.trace, category: .subscription,
                      "🌐 [NDK] Processing event \(event.id.prefix(8))... for subscription '\(subscriptionId)' from relay \(relay.url)")

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
            // Process through internal subscription manager with correct subscription ID
            NDKLogger.log(.trace, category: .subscription,
                          "🔄 [NDK] Forwarding to InternalSubscriptionManager with subscription '\(subscriptionId)'")
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
        let authRelay = await pendingAuthEventsManager.removePendingAuthEvent(for: eventId)

        if let authRelay = authRelay {
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
        }
    }

    func processNotice(message: String, from relay: RelayProtocol) {
        NDKLogger.log(.info, category: .relay, "Notice from \(relay.url): \(message)")
    }

    func processCount(subscriptionId _: String, count: Int, from relay: RelayProtocol) {
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
                NostrConstants.JSONField.sig: authEvent.sig,
            ]
            let authMessage: [Any] = ["AUTH", eventDict]
            let jsonData = try JSONSerialization.data(withJSONObject: authMessage, options: [.withoutEscapingSlashes])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""

            // Track pending auth event - moved inside try block after authEvent is created
            await pendingAuthEventsManager.setPendingAuthEvent(eventId: authEvent.id, relay: ndkRelay)

            try await relay.send(jsonString)

            // The OK response will trigger state change to authenticated
        } catch {
            NDKLogger.log(.error, category: .auth, "Failed to respond to auth challenge: \(error)")
            // Revert to connected state on failure
            await ndkRelay.updateConnectionState(.connected)
        }
    }

    // MARK: - Authentication Helpers

    /// Retry failed publishes after successful authentication
    private func retryFailedPublishesForRelay(_ relay: NDKRelay) async {
        await eventManager.retryAuthenticatedEvents(for: relay)
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
        signatureVerificationDelegate = delegate
    }

    // MARK: - Advanced Pool Access (for internal use)

    /// Get connected relays
    public func connectedRelays() async -> [NDKRelay] {
        await pool.connectedRelays()
    }

    /// Get a specific relay - primarily for internal use
    func getRelay(for url: RelayURL) async -> NDKRelay? {
        await pool.getRelay(for: url)
    }

    /// Get the authors that caused us to connect to each relay through the outbox model
    /// - Returns: Dictionary mapping relay URLs to the authors whose relay lists included them
    public func getRelayAuthorMapping() async -> [RelayURL: [String]] {
        await pool.getRelayAuthorMapping()
    }

    /// Get the authors that caused us to connect to a specific relay
    /// - Parameter url: The relay URL to check
    /// - Returns: Array of author pubkeys that caused this relay connection (empty for explicit relays)
    public func getAuthorsForRelay(_ url: RelayURL) async -> [String] {
        await pool.getAuthorsForRelay(url)
    }

    // MARK: - NIP-77 Support

    /// Process NIP-77 Negentropy message from relay
    func processNIP77Message(_ message: NostrMessage, from relay: NDKRelay) async {
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

        var results: [(user: NDKUser, nip05: String, status: NIP05VerificationStatus)] = []
        for entry in entries {
            let user = NDKUser(pubkey: entry.pubkey)
            await user.setNdk(self)
            results.append((user: user, nip05: entry.identifier, status: entry.status))
        }
        return results
    }

    /// Verify a NIP-05 identifier for a user
    /// - Parameters:
    ///   - user: The user whose NIP-05 to verify
    ///   - maxAge: Maximum age before re-verification is needed (default: 24 hours)
    /// - Returns: True if the NIP-05 is verified and belongs to this user
    public func verifyNIP05(for user: NDKUser, maxAge: TimeInterval = TimeConstants.day) async throws -> Bool {
        var metadata: NDKUserMetadata?
        for await m in await profileManager.subscribe(for: user.pubkey, maxAge: maxAge) {
            metadata = m
            break
        }
        guard let nip05 = metadata?.nip05 else { return false }
        return try await nip05Manager.verify(identifier: nip05, expectedPubkey: user.pubkey, maxAge: maxAge)
    }

    // MARK: - Internal Fetch Utilities

    // MARK: - Subscription Metrics

    /// Get current subscription grouping metrics
    public func getSubscriptionMetrics() async -> MetricsSnapshot {
        await NDKSubscriptionMetrics.getSnapshot()
    }

    /// Reset subscription grouping metrics
    public func resetSubscriptionMetrics() async {
        await NDKSubscriptionMetrics.reset()
    }
}
