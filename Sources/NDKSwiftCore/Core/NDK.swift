import Combine
import Foundation
import Observation

/// Protocol for handling relay authentication requests (NIP-42)
public protocol NDKAuthenticationDelegate: AnyObject, Sendable {
    /// Called when a relay requires authentication
    /// - Parameters:
    ///   - relay: The relay requiring authentication
    ///   - challenge: The authentication challenge from the relay
    /// - Returns: true to proceed with authentication, false to decline
    func relay(_ relay: NDKRelay, requiresAuthenticationWithChallenge challenge: String) async -> Bool
}

/// Represents a signing operation failure
public struct SigningFailure: Sendable {
    /// The error that occurred during signing
    public let error: Error

    /// The type of signer that failed (e.g., "NDKBunkerSigner", "NDKPrivateKeySigner")
    public let signerType: String

    public init(error: Error, signerType: String) {
        self.error = error
        self.signerType = signerType
    }
}

/// Main entry point for NDKSwift
@Observable
public final class NDK {
    // MARK: - Core Properties

    /// Publisher for signing failures - apps subscribe once globally
    /// Fires whenever any signing operation fails, allowing centralized error handling
    @ObservationIgnored
    public let signingFailedPublisher = PassthroughSubject<SigningFailure, Never>()

    /// Active signer for this NDK instance
    @ObservationIgnored
    public var signer: NDKSigner?

    /// Active session data for reactive filters
    @ObservationIgnored
    public var sessionData: NDKSessionData?

    /// Cache for storing events (always present, defaults to in-memory)
    @ObservationIgnored
    public let cache: NDKCache

    // MARK: - Observable Relay State

    /// Observable array of ALL relays for SwiftUI binding.
    /// This is automatically synchronized with the relay pool.
    @MainActor
    public private(set) var relays: [NDKRelay] = []

    /// Observable array of app relays only (origin: .appRelays)
    /// These are relays explicitly configured by the app, not discovered via outbox.
    @MainActor
    public private(set) var appRelays: [NDKRelay] = []

    /// Number of currently connected relays
    @MainActor
    public var connectedRelayCount: Int {
        relays.filter { $0.ui.isConnected }.count
    }

    /// Number of currently connected app relays
    @MainActor
    public var connectedAppRelayCount: Int {
        appRelays.filter { $0.ui.isConnected }.count
    }

    /// Task that observes pool changes and syncs to observable relays array
    @ObservationIgnored
    private var relayObserverTask: Task<Void, Never>?

    /// Active user's public key (derived from signer)
    @ObservationIgnored
    public var activePubkey: PublicKey? {
        get async {
            guard let signer else { return nil }
            do {
                return try await signer.pubkey
            } catch {
                NDKLogger.log(.warning, category: .signer, "Failed to get active pubkey from signer: \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Whether debug mode is enabled
    @ObservationIgnored
    public let debugMode: Bool

    /// Signature verification configuration
    @ObservationIgnored
    public let signatureVerificationConfig: NDKSignatureVerificationConfig

    /// Signature verification delegate
    @ObservationIgnored
    public weak var signatureVerificationDelegate: NDKSignatureVerificationDelegate?

    /// Authentication delegate for handling relay authentication (NIP-42)
    @ObservationIgnored
    public weak var authenticationDelegate: NDKAuthenticationDelegate?

    /// Whether outbox model is enabled (default: true)
    @ObservationIgnored
    public let outboxEnabled: Bool

    /// Discovery configuration (relays for fetching user relay lists)
    @ObservationIgnored
    public let discoveryConfig: NDKDiscoveryConfig

    /// Configuration for automatic client tagging (NIP-89)
    @ObservationIgnored
    public let clientTagConfig: NDKClientTagConfig?

    /// Connection reliability configuration
    @ObservationIgnored
    public let connectionConfig: NDKConnectionConfig

    /// Telemetry configuration
    @ObservationIgnored
    public let telemetryConfig: NDKTelemetryConfig

    /// Tracer for creating telemetry spans
    @ObservationIgnored
    public private(set) lazy var tracer: NDKTracer = {
        NDKTracer(config: telemetryConfig)
    }()

    /// Track pending auth events by event ID to relay (thread-safe via actor)
    @ObservationIgnored
    private let pendingAuthEvents = PendingAuthEvents()

    private actor PendingAuthEvents {
        private var events: [EventID: NDKRelay] = [:]

        func remove(for eventId: EventID) -> NDKRelay? {
            events.removeValue(forKey: eventId)
        }

        func set(eventId: EventID, relay: NDKRelay) {
            events[eventId] = relay
        }
    }

    // MARK: - Outbox API

    /// Outbox manager - provides simplified API for outbox operations
    @ObservationIgnored
    public private(set) lazy var outbox: NDKOutboxManager = .init(ndk: self)

    // MARK: - Relay Intelligence

    /// Hint index for learning where users and events are found
    @ObservationIgnored
    public lazy var hintIndex: HintIndex = {
        HintIndex()
    }()

    // MARK: - Internal Components

    /// Event publishing and management
    @ObservationIgnored
    lazy var eventManager: NDKEventManager = {
        NDKEventManager(ndk: self, cache: self.cache)
    }()

    /// Relay pool management
    @ObservationIgnored
    public lazy var pool: NDKPool = {
        NDKPool(ndk: self, config: self.connectionConfig)
    }()

    // MARK: - Profile Cache (LRU with strong references)

    /// Maximum number of profiles to keep in cache
    private static let profileCacheLimit = 500

    /// Strong reference storage for profiles (LRU cache)
    @ObservationIgnored
    @MainActor
    private var profileCache: [PublicKey: NDKProfile] = [:]

    /// LRU access order tracking (oldest first)
    @ObservationIgnored
    @MainActor
    private var profileAccessOrder: [PublicKey] = []

    /// Get or create an observable profile for a pubkey (MainActor-bound)
    /// Returns the same NDKProfile instance for the same pubkey (reference equality)
    /// Uses LRU eviction when cache reaches capacity
    @MainActor
    internal func getOrCreateProfile(_ pubkey: PublicKey) -> NDKProfile {
        // Return existing profile if cached, updating LRU position
        if let existing = profileCache[pubkey] {
            // Move to end of access order (most recently used)
            if let index = profileAccessOrder.firstIndex(of: pubkey) {
                profileAccessOrder.remove(at: index)
            }
            profileAccessOrder.append(pubkey)
            return existing
        }

        // Evict oldest profiles if at capacity
        while profileCache.count >= Self.profileCacheLimit, let oldest = profileAccessOrder.first {
            profileCache.removeValue(forKey: oldest)
            profileAccessOrder.removeFirst()
        }

        // Create new profile and cache with strong reference
        let profile = NDKProfile(pubkey: pubkey, ndk: self)
        profileCache[pubkey] = profile
        profileAccessOrder.append(pubkey)
        return profile
    }

    /// Event tracker for managing event metadata
    @ObservationIgnored
    public let eventTracker: NDKEventTracker = .init()

    /// Internal subscription manager for NDKSubscriptionManager
    @ObservationIgnored
    lazy var internalSubscriptionManager: InternalSubscriptionManager = {
        InternalSubscriptionManager(ndk: self)
    }()

    /// Signature verification sampler
    @ObservationIgnored
    private lazy var signatureVerificationSampler: NDKSignatureVerificationSampler = {
        let sampler = NDKSignatureVerificationSampler(config: self.signatureVerificationConfig)
        // Set tracer for telemetry - tracer is already initialized by this point
        let tracerRef = self.tracer
        Task { await sampler.setTracer(tracerRef) }
        return sampler
    }()

    /// Relay coverage tracker for intelligent relay selection
    @ObservationIgnored
    public lazy var relayCoverageTracker: NDKRelayCoverageTracker = {
        NDKRelayCoverageTracker()
    }()

    /// Data requirement manager for declarative data access
    @ObservationIgnored
    lazy var dataRequirementManager: NDKSubscriptionManager = {
        NDKSubscriptionManager(ndk: self)
    }()

    /// Initial relay URLs to add after construction
    @ObservationIgnored
    private var initialRelayURLs: [RelayURL] = []

    /// Track whether connect() has been called
    /// When false, publishing will queue events instead of auto-connecting to relays
    @ObservationIgnored
    public private(set) var hasConnected = false

    /// Get the configured relay URLs (used for offline queuing before connect() is called)
    @ObservationIgnored
    public var configuredRelayURLs: [RelayURL] {
        initialRelayURLs
    }

    // MARK: - Lazy Internal Components

    @ObservationIgnored
    lazy var relayRanker: NDKRelayRanker = {
        NDKRelayRanker(ndk: self, tracker: outbox)
    }()

    @ObservationIgnored
    lazy var relaySelector: NDKRelaySelector = {
        NDKRelaySelector(ndk: self, tracker: outbox, ranker: relayRanker)
    }()

    @ObservationIgnored
    lazy var publishingStrategy: NDKPublishingStrategy = {
        NDKPublishingStrategy(ndk: self, selector: relaySelector, ranker: relayRanker)
    }()

    /// NIP-05 manager for efficient resolution and caching
    @ObservationIgnored
    public lazy var nip05Manager: NIP05Manager = {
        NIP05Manager(ndk: self)
    }()

    /// Blossom server manager for managing server lists and uploads
    @ObservationIgnored
    public lazy var blossomServerManager: NDKBlossomServerManager = {
        NDKBlossomServerManager(ndk: self)
    }()

    /// Zap manager for handling zaps and payments
    @ObservationIgnored
    public lazy var zapManager: any ZapManaging = {
        NDKZapManager(ndk: self)
    }()

    // MARK: - Initialization

    /// Initialize NDK with a custom cache instance
    /// - Parameters:
    ///   - relayURLs: Initial relay URLs to connect to
    ///   - signer: Optional signer for signing events
    ///   - cache: Custom cache instance. If nil, uses MemoryCache
    ///   - signatureVerificationConfig: Configuration for signature verification
    ///   - debugMode: Whether debug mode is enabled
    ///   - outboxEnabled: Whether outbox model is enabled
    ///   - discoveryConfig: Discovery configuration (relays for fetching user relay lists)
    ///   - clientTagConfig: Configuration for automatic client tagging
    ///   - connectionConfig: Connection reliability configuration
    public init(
        relayURLs: [RelayURL] = [],
        signer: NDKSigner? = nil,
        sessionData: NDKSessionData? = nil,
        cache: NDKCache? = nil,
        signatureVerificationConfig: NDKSignatureVerificationConfig = .default,
        debugMode: Bool = false,
        outboxEnabled: Bool = true,
        discoveryConfig: NDKDiscoveryConfig = .default,
        clientTagConfig: NDKClientTagConfig? = nil,
        connectionConfig: NDKConnectionConfig = .default,
        telemetryConfig: NDKTelemetryConfig = .disabled
    ) {
        self.signer = signer
        self.sessionData = sessionData
        self.cache = cache ?? MemoryCache()
        self.signatureVerificationConfig = signatureVerificationConfig
        self.debugMode = debugMode
        self.outboxEnabled = outboxEnabled
        self.discoveryConfig = discoveryConfig
        self.clientTagConfig = clientTagConfig
        self.connectionConfig = connectionConfig
        self.telemetryConfig = telemetryConfig

        // All managers are now lazy-initialized on first access
        // This avoids initialization order issues with 'self'

        // Set shared NDK instance for NDKEventBuilder
        NDKEventBuilder.setSharedNDK(self)

        // Store relay URLs for later initialization
        initialRelayURLs = relayURLs
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

    /// Add a relay to the pool
    ///
    /// If `connect()` has already been called, the relay will be automatically connected.
    /// Otherwise, it will be connected when `connect()` is called.
    ///
    /// - Parameters:
    ///   - url: The relay URL to add
    ///   - origin: The origin of this relay (why it's being added)
    ///   - reason: Optional human-readable reason for debugging
    @discardableResult
    public func addRelay(_ url: RelayURL, origin: NDKRelayOrigin = .appRelays, reason: String? = nil) async -> NDKRelay {
        await pool.addRelay(url, origin: origin, reason: reason)
    }

    /// Remove a relay from the pool
    public func removeRelay(_ url: RelayURL) async {
        await pool.removeRelay(url)
    }

    /// Get relays from the pool (async access for internal operations)
    @ObservationIgnored
    public var poolRelays: [NDKRelay] {
        get async {
            await pool.relays
        }
    }

    /// Stream of relay pool changes for event-driven observation
    @ObservationIgnored
    public var relayChanges: AsyncStream<NDKPoolChangeEvent> {
        get async {
            await pool.relayChanges
        }
    }

    /// Get a quick snapshot of relay connection states
    /// Useful for one-time status checks without setting up observers
    public func getRelayConnectionSummary() async -> (connected: Int, total: Int) {
        await pool.getConnectionSummary()
    }

    /// Start observing the relay pool and sync to the observable relays array
    private func startRelayObserver() {
        relayObserverTask?.cancel()
        relayObserverTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Initial load
            self.relays = await self.pool.relays
            self.appRelays = await self.pool.appRelays

            // Observe changes
            for await change in await self.pool.relayChanges {
                guard !Task.isCancelled else { break }
                switch change {
                case .relayAdded(let relay):
                    if !self.relays.contains(where: { $0.url == relay.url }) {
                        self.relays.append(relay)
                    }
                    // Check if it's an app relay
                    let origin = await relay.origin
                    if case .appRelays = origin {
                        if !self.appRelays.contains(where: { $0.url == relay.url }) {
                            self.appRelays.append(relay)
                        }
                    }
                case .relayRemoved(let url):
                    self.relays.removeAll { $0.url == url }
                    self.appRelays.removeAll { $0.url == url }
                case .relayConnected, .relayDisconnected:
                    // State changes are handled by individual relay.ui observers
                    break
                }
            }
        }
    }

    /// Connect to all configured relays
    ///
    /// Initialize relays that were passed to the constructor
    /// This should be called before connect() to ensure relays are added
    public func initializeRelays() async {
        for url in initialRelayURLs {
            await addRelay(url, reason: "initial relay from config")
        }
        initialRelayURLs.removeAll() // Clear after adding
    }

    /// Initiates WebSocket connections to all relays in the pool.
    /// Connections are managed automatically with reconnection logic.
    public func connect() async {
        // Initialize subscription manager early to start listening for discoveries
        // This prevents race condition where discoveries happen before listener starts
        _ = dataRequirementManager

        // Ensure initial relays are added first
        if !initialRelayURLs.isEmpty {
            NDKLogger.log(.info, category: .relay, "Adding \(initialRelayURLs.count) initial relay(s) from configuration")
            await initializeRelays()
        }

        // Add discovery relays from config (e.g., purplepag.es)
        if !discoveryConfig.discoveryRelays.isEmpty {
            NDKLogger.log(.info, category: .relay, "Adding \(discoveryConfig.discoveryRelays.count) discovery relay(s) from configuration")
            for relayUrl in discoveryConfig.discoveryRelays {
                await pool.addRelay(relayUrl, origin: .discovery, reason: "discovery relay from config")
            }
        }

        // Start observing relay pool changes for the observable relays array
        startRelayObserver()

        // Mark that connect has been called BEFORE connecting
        // This ensures any relays added during connectAll() will auto-connect
        hasConnected = true

        NDKLogger.log(.info, category: .relay, "Connecting to all relays in pool")
        await pool.connectAll()

        // Activate any subscriptions that were created while offline
        await dataRequirementManager.activateDeferredSubscriptions()
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
    public func publish(_ event: NDKEvent, to relayURLs: Set<String>? = nil, logRawJSON: Bool = false) async throws -> Set<NDKRelay> {
        if let relayURLs = relayURLs {
            try await eventManager.publish(event: event, to: relayURLs, logRawJSON: logRawJSON)
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
        closeOnEose: Bool? = nil,
        includeRelayUpdates: Bool = false
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
            closeOnEose: shouldCloseOnEose,
            includeRelayUpdates: includeRelayUpdates
        )
    }

    /// Subscribe to events with custom options
    public func subscribe(
        filter: NDKFilter,
        options: NDKSubscriptionOptions? = nil,
        includeRelayUpdates: Bool = false
    ) -> NDKSubscription<NDKEvent> {
        let opts = options ?? .default
        return NDKSubscription(
            ndk: self,
            filter: filter,
            options: opts,
            includeRelayUpdates: includeRelayUpdates
        )
    }

    public func subscribe<T: Sendable>(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool? = nil,
        includeRelayUpdates: Bool = false,
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
            includeRelayUpdates: includeRelayUpdates,
            transform: transform
        )
    }

    // MARK: - Public Key Parsing

    /// Parse a public key from various identifier formats
    ///
    /// Supports multiple formats:
    /// - Hex public key (64 characters)
    /// - npub bech32 format
    /// - nprofile bech32 format (extracts pubkey, ignores relay hints)
    ///
    /// - Parameter identifier: Public key in any supported format
    /// - Returns: The parsed PublicKey if the identifier is valid, nil otherwise
    public func parsePubkey(_ identifier: String) -> PublicKey? {
        // Check if it's a known nostr bech32 format
        if let hrp = Bech32.getHRP(identifier) {
            switch hrp {
            case Bech32HRP.npub:
                guard let pubkey = try? Bech32.pubkey(from: identifier) else {
                    NDKLogger.log(.warning, category: .general, "Failed to parse npub \(identifier.prefix(16))")
                    return nil
                }
                return pubkey

            case Bech32HRP.nprofile:
                guard let nprofile = try? Bech32.decodeNProfile(identifier) else {
                    NDKLogger.log(.warning, category: .general, "Failed to parse nprofile \(identifier.prefix(16))")
                    return nil
                }
                return nprofile.pubkey

            default:
                // Unknown HRP - fall through to hex parsing
                // (hex strings containing "1" may trigger getHRP)
                break
            }
        }

        // Assume hex pubkey format
        guard HexValidator.isValid32ByteHex(identifier) else {
            NDKLogger.log(.warning, category: .general, "Invalid pubkey format: \(identifier.prefix(16))")
            return nil
        }

        return identifier
    }

    /// Resolve a NIP-05 identifier to a public key
    /// - Parameters:
    ///   - nip05: The NIP-05 identifier (e.g., "alice@example.com")
    ///   - forceVerify: If true, bypasses cache and forces network verification
    /// - Returns: The PublicKey if found and verified, nil otherwise
    public func resolveNip05(_ nip05: String, forceVerify: Bool = false) async throws -> PublicKey? {
        try await nip05Manager.resolvePubkey(identifier: nip05, forceVerify: forceVerify)
    }

    // MARK: - Content Parsing (Now a utility)

    public func parseContent(
        _ content: String,
        tags: [[String]] = [],
        currentUserPubkey: PublicKey? = nil
    ) async -> NDKParsedContent {
        let result = ContentParser.parseContentWithContext(content, tags: tags, currentUserPubkey: currentUserPubkey)
        return result.parsedContent
    }

    // MARK: - Internal Methods (for relay communication)

    func processEvent(_ event: NDKEvent, subscriptionId: String, from relay: RelayProtocol) async {
        NDKLogger.log(.trace, category: .subscription,
                      "🌐 [NDK] Processing event \(event.id.prefix(8))... for subscription '\(subscriptionId)' from relay \(relay.url)")

        // SIGNATURE VERIFICATION: Check signature if not already verified
        let alreadyVerified = await signatureVerificationSampler.isEventVerified(event.id)

        if !alreadyVerified {
            // Only verify if relay is NDKRelay - otherwise skip verification but continue processing
            if let ndkRelay = relay as? NDKRelay {
                var signatureStats = await ndkRelay.getSignatureStats()

                // Verify the event signature
                let verificationResult = await signatureVerificationSampler.verifyEvent(
                    event,
                    from: relay,
                    stats: &signatureStats
                )

                // Update relay's signature stats
                await ndkRelay.updateSignatureStats { $0 = signatureStats }

                // If signature is invalid, mark relay as evil and REJECT the event
                if verificationResult == .invalid {
                    NDKLogger.log(.error, category: .security,
                                  "🚨 [SECURITY] Invalid signature detected from relay \(relay.url) for event \(event.id) - REJECTING EVENT")
                    await ndkRelay.markAsEvil(eventId: event.id)
                    return
                }

                NDKLogger.log(.trace, category: .security,
                              "✅ [SECURITY] Signature verification result: \(verificationResult) for event \(event.id)")
            } else {
                NDKLogger.log(.warning, category: .event, "⚠️ Relay is not NDKRelay type - skipping signature verification")
            }
        }

        // Track that we've seen this event on this relay
        // If this is the first time we see this event, also set it as the source relay
        let seenRelays = await eventTracker.getSeenOnRelays(eventId: event.id)
        let isFirstDelivery = seenRelays.isEmpty

        if isFirstDelivery {
            await eventTracker.setSourceRelay(eventId: event.id, relay: relay.url)
        } else {
            await eventTracker.markSeen(eventId: event.id, relay: relay.url)
        }

        // RELAY COVERAGE TRACKING: Record this delivery for coverage statistics
        let isFirst = await relayCoverageTracker.recordDelivery(eventId: event.id, relayUrl: relay.url)
        NDKLogger.log(.debug, category: .relay, "📊 [COVERAGE] Recorded delivery for event \(event.id.prefix(8)) from \(relay.url) - first: \(isFirst)")

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
        let authRelay = await pendingAuthEvents.remove(for: eventId)

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
                NostrConstants.JSONField.sig: authEvent.sig
            ]
            let authMessage: [Any] = ["AUTH", eventDict]
            let jsonData = try JSONSerialization.data(withJSONObject: authMessage, options: [.withoutEscapingSlashes])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""

            // Track pending auth event - moved inside try block after authEvent is created
            await pendingAuthEvents.set(eventId: authEvent.id, relay: ndkRelay)

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
    ///   - blocklistedRelays: Number of relays currently blocklisted due to signature failures
    public func getSignatureVerificationStats() async -> (totalVerifications: Int, failedVerifications: Int, blocklistedRelays: Int) {
        await signatureVerificationSampler.getStats()
    }

    /// Check if a relay is blocklisted due to signature verification failures
    /// - Parameter relay: The relay to check
    /// - Returns: true if the relay is blocklisted, false otherwise
    public func isRelayBlocklisted(_ relay: NDKRelay) async -> Bool {
        await signatureVerificationSampler.isRelayBlocklisted(relay.url)
    }

    /// Get the set of relay URLs that are currently blocklisted
    /// - Returns: Set of blocklisted relay URLs
    public func getBlocklistedRelays() async -> Set<String> {
        await signatureVerificationSampler.getBlocklistedRelays()
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
    /// - Returns: Array of author pubkeys that caused this relay connection (empty for app relays)
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
    /// - Returns: Array of tuples containing pubkey, NIP-05 identifier, and verification status
    public func searchNIP05(_ query: String, limit: Int = 10) async -> [(pubkey: PublicKey, nip05: String, status: NIP05VerificationStatus)] {
        let entries = await nip05Manager.search(query, limit: limit)

        var results: [(pubkey: PublicKey, nip05: String, status: NIP05VerificationStatus)] = []
        for entry in entries {
            results.append((pubkey: entry.pubkey, nip05: entry.identifier, status: entry.status))
        }
        return results
    }

    /// Verify a NIP-05 identifier for a pubkey
    /// - Parameters:
    ///   - pubkey: The public key whose NIP-05 to verify
    ///   - maxAge: Maximum age before re-verification is needed (default: 24 hours)
    /// - Returns: True if the NIP-05 is verified and belongs to this pubkey
    public func verifyNIP05(for pubkey: PublicKey, maxAge: TimeInterval = TimeConstants.day) async throws -> Bool {
        let nip05 = await MainActor.run { profile(for: pubkey).metadata?.nip05 }
        guard let nip05 else { return false }
        return try await nip05Manager.verify(identifier: nip05, expectedPubkey: pubkey, maxAge: maxAge)
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
