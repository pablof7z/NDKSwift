import Foundation

/// Main entry point for NDKSwift
public final class NDK {
    /// Active signer for this NDK instance
    public var signer: NDKSigner?

    /// Cache for storing events
    public var cache: NDKCache?

    /// Active user (derived from signer)
    public var activeUser: NDKUser? {
        // This will need to be async or cached
        return nil
    }

    /// Relay pool
    let relayPool: NDKRelayPool

    /// Event repository
    private let eventRepository: NDKEventRepository

    /// Published events tracking (for OK message handling)
    private var publishedEvents: [EventID: NDKEvent] = [:]

    /// Subscription manager
    private var subscriptionManager: NDKSubscriptionManager!

    /// Whether debug mode is enabled
    public var debugMode: Bool = false

    /// Signature verification configuration
    public var signatureVerificationConfig: NDKSignatureVerificationConfig

    /// Signature verification sampler
    let signatureVerificationSampler: NDKSignatureVerificationSampler

    /// Signature verification delegate
    public weak var signatureVerificationDelegate: NDKSignatureVerificationDelegate?


    // MARK: - Outbox Model Support

    /// Whether outbox model is enabled (default: true)
    /// Set to false to disable outbox model and use direct relay publishing
    public var outboxEnabled: Bool = true

    /// Outbox configuration
    public var outboxConfig: NDKOutboxConfig = .default

    /// Outbox manager - provides simplified API for outbox operations
    public private(set) lazy var outbox: NDKOutboxManager = {
        NDKOutboxManager(ndk: self)
    }()

    /// Outbox tracker (lazy) - now internal
    var _outboxTracker: NDKOutboxTracker?

    /// Relay ranker (lazy) - now internal
    var _relayRanker: NDKRelayRanker?

    /// Relay selector (lazy) - now internal
    var _relaySelector: NDKRelaySelector?

    /// Publishing strategy (lazy) - now internal
    var _publishingStrategy: NDKPublishingStrategy?

    /// Fetching strategy (lazy) - now internal
    var _fetchingStrategy: NDKFetchingStrategy?
    
    /// Fetching strategy computed property
    var fetchingStrategy: NDKFetchingStrategy {
        if let existing = _fetchingStrategy {
            return existing
        }
        // Ensure we have relay selector first
        let selector = self.relaySelector
        let strategy = NDKFetchingStrategy(ndk: self, selector: selector)
        _fetchingStrategy = strategy
        return strategy
    }

    // MARK: - Subscription Tracking

    /// Subscription tracker for monitoring and debugging
    public let subscriptionTracker: NDKSubscriptionTracker

    /// Configuration for subscription tracking
    public struct SubscriptionTrackingConfig {
        /// Whether to track closed subscriptions for debugging
        public var trackClosedSubscriptions: Bool

        /// Maximum number of closed subscriptions to remember
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

    // MARK: - Profile Management
    // Profile management will be added later

    // MARK: - Initialization

    public init(
        relayUrls: [RelayURL] = [],
        signer: NDKSigner? = nil,
        cache: NDKCache? = nil,
        signatureVerificationConfig: NDKSignatureVerificationConfig = .default,
        subscriptionTrackingConfig: SubscriptionTrackingConfig = .default
    ) {
        self.signer = signer
        self.cache = cache
        self.relayPool = NDKRelayPool()
        self.eventRepository = NDKEventRepository()
        self.signatureVerificationConfig = signatureVerificationConfig
        self.signatureVerificationSampler = NDKSignatureVerificationSampler(config: signatureVerificationConfig)
        self.subscriptionTracker = NDKSubscriptionTracker(
            trackClosedSubscriptions: subscriptionTrackingConfig.trackClosedSubscriptions,
            maxClosedSubscriptions: subscriptionTrackingConfig.maxClosedSubscriptions
        )
        // Profile manager will be initialized later

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
        let relay = relayPool.addRelay(url)
        relay.ndk = self

        // Set up connection state observer to publish queued events
        Task {
            await relay.observeConnectionState { [weak self] state in
                if case .connected = state {
                    Task { [weak self] in
                        await self?.publishQueuedEvents(for: relay)
                    }
                }
            }
        }

        return relay
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
        print("[NDK] Connecting to all relays...")
        await relayPool.connectAll()
        print("[NDK] connectAll() completed")
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

    /// Publish an event to relays
    /// 
    /// Signs the event (if not already signed) and publishes it using the configured strategy.
    /// By default, uses the outbox model (NIP-65) for optimal relay selection.
    /// 
    /// - Parameter event: The event to publish. Will be signed automatically if needed.
    /// 
    /// - Returns: Set of relays that successfully accepted the event
    /// 
    /// - Throws: 
    ///   - `NDKError.notConfigured` if no signer is available and event is unsigned
    ///   - `NDKError.validation` if the event structure is invalid
    ///   - Publishing errors from the outbox model or relay pool
    /// 
    /// - Note: The event's `relayPublishStatuses` property tracks per-relay results
    /// 
    /// ## Example
    /// ```swift
    /// let event = NDKEvent(content: "Hello!", kind: 1)
    /// let successfulRelays = try await ndk.publish(event)
    /// print("Published to \(successfulRelays.count) relays")
    /// ```
    @discardableResult
    public func publish(_ event: NDKEvent) async throws -> Set<NDKRelay> {
        // Sign event if not already signed
        if event.sig == nil {
            guard signer != nil else {
                throw NDKError.notConfigured("No signer configured")
            }

            // Set NDK instance and sign (this will also generate content tags)
            event.ndk = self
            try await event.sign()
        }

        // Validate event
        try event.validate()

        // Store in cache if available
        if let cache = cache {
            try? await cache.saveEvent(event)
        }

        // Use outbox model if enabled
        if outboxEnabled {
            let successfulRelays = try await outbox.publish(event)
            // Convert URLs back to NDKRelay objects for backward compatibility
            return Set(successfulRelays.compactMap { url in
                relayPool.relaysByUrl[url]
            })
        }

        // Fallback to direct publishing if outbox is disabled
        // Track this event for OK message handling
        if let eventId = event.id {
            publishedEvents[eventId] = event
        }

        // Get all relays we want to publish to
        let targetRelays = relayPool.relays

        // Publish to connected relays
        let publishedRelays = await relayPool.publishEvent(event)

        // Update event's relay publish statuses
        for relay in publishedRelays {
            event.updatePublishStatus(relay: relay.url, status: .succeeded)
        }

        // Find relays that weren't connected or failed
        let unpublishedRelayUrls = targetRelays
            .filter { !publishedRelays.contains($0) }
            .map { $0.url }

        // Store unpublished event for later retry when relays connect
        if !unpublishedRelayUrls.isEmpty {
            // Mark these relays as pending
            for relayUrl in unpublishedRelayUrls {
                event.updatePublishStatus(relay: relayUrl, status: .pending)
            }
        }

        if debugMode {
            let noteId = (try? Bech32.note(from: event.id ?? "")) ?? event.id ?? "unknown"
            if publishedRelays.isEmpty {
                print("📝 Event \(noteId) created but not published to any relays. Will retry when relays connect.")
            } else {
                let relayUrls = publishedRelays.map { $0.url }.joined(separator: ", ")
                print("📝 Published note \(noteId) to \(publishedRelays.count) relay(s): \(relayUrls)")
                if !unpublishedRelayUrls.isEmpty {
                    print("📝 Queued for \(unpublishedRelayUrls.count) disconnected relay(s)")
                }
            }
        }

        return publishedRelays
    }

    /// Publish an event to specific relays by URL
    public func publish(event: NDKEvent, to relayUrls: Set<String>) async throws -> Set<NDKRelay> {
        // Sign the event if needed
        if event.sig == nil {
            event.ndk = self
            try await event.sign()
        }

        // Use relays from the pool or add them if needed
        var targetRelays: Set<NDKRelay> = []
        for url in relayUrls {
            let normalizedUrl = URLNormalizer.tryNormalizeRelayUrl(url) ?? url

            // Check if relay is already in the pool
            if let existingRelay = relayPool.relaysByUrl[normalizedUrl] {
                targetRelays.insert(existingRelay)
            } else {
                // Add relay to pool
                let relay = addRelay(normalizedUrl)
                targetRelays.insert(relay)
            }
        }

        // Connect to relays that aren't already connected
        await withTaskGroup(of: Void.self) { group in
            for relay in targetRelays {
                group.addTask {
                    let state = await relay.connectionState
                    if state != .connected {
                        try? await relay.connect()
                    }
                }
            }
        }

        // Publish to the specific relays
        var publishedRelays: Set<NDKRelay> = []

        await withTaskGroup(of: NDKRelay?.self) { group in
            for relay in targetRelays {
                group.addTask {
                    do {
                        let eventMessage = NostrMessage.event(subscriptionId: nil, event: event)
                        try await relay.send(eventMessage.serialize())
                        event.updatePublishStatus(relay: relay.url, status: .succeeded)
                        return relay
                    } catch {
                        event.updatePublishStatus(relay: relay.url, status: .failed(.connectionFailed))
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

    // MARK: - Subscriptions

    /// Subscribe to events matching the given filters
    /// 
    /// Creates a subscription that continuously receives events matching the provided filters.
    /// Uses the outbox model (NIP-65) by default for optimal relay selection.
    /// 
    /// - Parameters:
    ///   - filters: Array of filters defining which events to receive
    ///   - options: Configuration options for the subscription (relays, caching, etc.)
    /// 
    /// - Returns: An `NDKSubscription` that acts as an AsyncSequence of events
    /// 
    /// ## Example
    /// ```swift
    /// // Subscribe to text notes from specific authors
    /// let filter = NDKFilter(authors: [pubkey], kinds: [1])
    /// let subscription = ndk.subscribe(filters: [filter])
    /// 
    /// for await event in subscription {
    ///     print("New note: \(event.content)")
    /// }
    /// ```
    /// 
    /// - Note: The subscription automatically starts when you begin iterating.
    ///         Call `subscription.stop()` to manually stop receiving events.
    public func subscribe(
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions()
    ) -> NDKSubscription {
        var subscriptionOptions = options
        
        // Determine which relays to use
        if subscriptionOptions.relays == nil {
            // No specific relays requested - use outbox model or all relays
            if outboxEnabled {
                // Start with empty relay set - will be populated by outbox model
                subscriptionOptions.relays = Set<NDKRelay>()
            } else {
                // Use all configured relays when outbox is disabled
                subscriptionOptions.relays = Set(relays)
            }
        }
        
        let subscription = NDKSubscription(
            filters: filters,
            options: subscriptionOptions,
            ndk: self
        )
        
        // Log subscription creation with filters
        if debugMode {
            print("🔔 Creating subscription \(subscription.id):")
            for (index, filter) in filters.enumerated() {
                if let filterData = try? JSONEncoder().encode(filter),
                   let filterJSON = String(data: filterData, encoding: .utf8) {
                    print("   Filter \(index + 1): \(filterJSON)")
                }
            }
            if let relays = subscriptionOptions.relays, !relays.isEmpty {
                print("   Target relays: \(relays.map { $0.url }.joined(separator: ", "))")
            } else {
                print("   Target relays: Will be determined by outbox model" + (outboxEnabled ? "" : " (all relays)"))
            }
        }
        
        // Register subscription and handle outbox relay selection
        let registrationTask = Task { [weak self, weak subscription] in
            guard let self = self else { return }
            guard let subscription = subscription else { return }
            
            // If outbox is enabled and no specific relays were provided, select them now
            if self.outboxEnabled && options.relays == nil {
                // Get recommended relays for these filters
                var allRelays = Set<String>()
                for filter in filters {
                    let result = await self.relaySelector.selectRelaysForFetching(
                        filter: filter,
                        config: FetchingConfig(maxRelayCount: 10)
                    )
                    allRelays.formUnion(result.relays)
                }
                
                // Convert URLs to NDKRelay objects
                let relayObjects = allRelays.compactMap { url in
                    self.relayPool.relaysByUrl[url] ?? self.addRelay(url)
                }
                
                // Update subscription with selected relays
                await subscription.updateRelays(Set(relayObjects))
            }
            
            await self.subscriptionManager.addSubscription(subscription)
        }
        
        // Store the registration task in the subscription's actor
        Task {
            await subscription.stateActor.setRegistrationTask(registrationTask)
        }
        
        return subscription
    }

    /// Fetch events matching the given filters (one-shot query)
    /// 
    /// Performs a one-time query for events, automatically closing the subscription
    /// after receiving all matching events (EOSE). Uses outbox model by default.
    /// 
    /// - Parameters:
    ///   - filters: Array of filters defining which events to fetch
    ///   - relays: Optional specific relays to query. If nil, uses outbox model or all relays.
    ///   - useCache: Whether to include cached events in the results (default: true)
    /// 
    /// - Returns: Set of events matching the filters
    /// 
    /// - Throws: Errors from the underlying subscription
    /// 
    /// ## Example
    /// ```swift
    /// // Fetch the last 20 notes
    /// let filter = NDKFilter(kinds: [1], limit: 20)
    /// let events = try await ndk.fetchEvents(filters: [filter])
    /// 
    /// for event in events {
    ///     print("Note: \(event.content)")
    /// }
    /// ```
    public func fetchEvents(
        filters: [NDKFilter],
        relays: Set<NDKRelay>? = nil,
        useCache: Bool = true
    ) async throws -> Set<NDKEvent> {
        // Create subscription with closeOnEose
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        options.relays = relays
        options.useCache = useCache

        let subscription = subscribe(filters: filters, options: options)
        
        var events: [NDKEvent] = []
        
        // Collect events until EOSE (subscription will auto-close)
        do {
            for try await event in subscription {
                events.append(event)
            }
        } catch {
            // Subscription completed or failed
            throw error
        }

        return Set(events)
    }
    
    /// Fetch events matching a single filter (one-shot query)
    public func fetchEvents(
        _ filter: NDKFilter,
        relays: Set<NDKRelay>? = nil,
        useCache: Bool = true
    ) async throws -> Set<NDKEvent> {
        return try await fetchEvents(filters: [filter], relays: relays, useCache: useCache)
    }

    /// Fetch a single event by ID (hex or bech32 format)
    public func fetchEvent(
        _ idOrBech32: String,
        relays: Set<NDKRelay>? = nil,
        useCache: Bool = true
    ) async throws -> NDKEvent? {
        let filter = try NostrIdentifier.createFilter(from: idOrBech32)
        let events = try await fetchEvents(filters: [filter], relays: relays, useCache: useCache)
        return events.first
    }

    /// Fetch a single event matching the filter
    public func fetchEvent(
        _ filter: NDKFilter,
        relays: Set<NDKRelay>? = nil,
        useCache: Bool = true
    ) async throws -> NDKEvent? {
        let events = try await fetchEvents(filters: [filter], relays: relays, useCache: useCache)
        return events.first
    }
    
    /// Fetch a user's profile (metadata event)
    public func fetchProfile(
        _ pubkey: String,
        relays: Set<NDKRelay>? = nil,
        useCache: Bool = true
    ) async throws -> NDKUserProfile? {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.metadata]
        )
        
        if let metadataEvent = try await fetchEvent(filter, relays: relays, useCache: useCache) {
            // Parse the profile from the event content
            guard let profileData = metadataEvent.content.data(using: .utf8),
                  let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) else {
                return nil
            }
            return profile
        }
        
        return nil
    }

    // MARK: - Subscription Manager Integration

    /// Process an event received from a relay (called by relay connections)
    func processEvent(_ event: NDKEvent, from relay: RelayProtocol) {
        // Mark event as seen on this relay
        event.markSeenOn(relay: relay.url)

        Task {
            // Get current stats
            let initialStats = await relay.getSignatureStats()
            var currentStats = initialStats

            // Verify signature with sampling
            let verificationResult = await signatureVerificationSampler.verifyEvent(
                event,
                from: relay,
                stats: &currentStats
            )

            // Update stats back to relay
            let finalStats = currentStats
            await relay.updateSignatureStats { stats in
                stats = finalStats
            }

            switch verificationResult {
            case .invalid:
                // Invalid signature - don't process this event
                if debugMode {
                    print("❌ Event \(event.id ?? "unknown") from \(relay.url) has invalid signature")
                }
                return
            case .valid:
                if debugMode {
                    print("✅ Event \(event.id ?? "unknown") signature verified from \(relay.url)")
                }
            case .cached:
                // Already verified
                break
            case .skipped:
                // Skipped due to sampling
                if debugMode {
                    print("⏭️ Event \(event.id ?? "unknown") signature verification skipped (sampling) from \(relay.url)")
                }
            }

            // Process the event
            await subscriptionManager.processEvent(event, from: relay)
        }
    }

    /// Process EOSE received from a relay (called by relay connections)
    func processEOSE(subscriptionId: String, from relay: RelayProtocol) {
        Task {
            await subscriptionManager.processEOSE(subscriptionId: subscriptionId, from: relay)
        }
    }

    /// Get subscription manager statistics
    public func getSubscriptionStats() async -> NDKSubscriptionManager.SubscriptionStats {
        return await subscriptionManager.getStats()
    }

    /// Process OK message from relay (called by relay connections)
    func processOKMessage(eventId: EventID, accepted: Bool, message: String?, from relay: RelayProtocol) {
        // Find the event in our published events
        if let event = publishedEvents[eventId] {
            // Store the OK message
            event.addOKMessage(relay: relay.url, accepted: accepted, message: message)

            // Update publish status based on OK response
            if accepted {
                event.updatePublishStatus(relay: relay.url, status: .succeeded)
            } else {
                let reason = message ?? "Rejected by relay"
                event.updatePublishStatus(relay: relay.url, status: .failed(.custom(reason)))
            }
        }
    }
    
    /// Process NOTICE message from relay (called by relay connections)
    func processNotice(message: String, from relay: RelayProtocol) {
        // Emit notice event for any listeners
        if debugMode {
            print("📢 Notice from \(relay.url): \(message)")
        }
        
        // Could emit an event or notification here if needed
        // For now, just logging when debug mode is enabled
    }
    
    /// Process COUNT message from relay (called by relay connections)
    func processCount(subscriptionId: String, count: Int, from relay: RelayProtocol) {
        Task {
            await subscriptionManager.processCount(subscriptionId: subscriptionId, count: count, from: relay)
        }
    }
    
    /// Handle AUTH challenge from relay (NIP-42)
    func handleAuthChallenge(challenge: String, from relay: RelayProtocol) async {
        guard signer != nil else {
            if debugMode {
                print("⚠️ Cannot handle auth challenge - no signer configured")
            }
            return
        }
        
        // Create auth event (kind 22242)
        let authEvent = NDKEvent()
        authEvent.kind = 22242
        authEvent.tags = [
            ["relay", relay.url],
            ["challenge", challenge]
        ]
        authEvent.ndk = self
        
        do {
            // Sign the auth event
            try await authEvent.sign()
            
            // Send AUTH response (as an EVENT message containing the signed auth event)
            let authMessage = NostrMessage.event(subscriptionId: nil, event: authEvent)
            if let ndkRelay = relay as? NDKRelay {
                try await ndkRelay.send(authMessage.serialize())
            }
        } catch {
            if debugMode {
                print("❌ Failed to handle auth challenge: \(error)")
            }
        }
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

    // MARK: - Queued Events

    /// Publish events that were queued while relay was disconnected
    private func publishQueuedEvents(for relay: NDKRelay) async {
        // Queued events are handled by the outbox model
        return
    }

    // MARK: - Signature Verification

    /// Get signature verification statistics
    public func getSignatureVerificationStats() async -> (totalVerifications: Int, failedVerifications: Int, blacklistedRelays: Int) {
        return await signatureVerificationSampler.getStats()
    }

    /// Check if a relay is blacklisted
    public func isRelayBlacklisted(_ relay: NDKRelay) async -> Bool {
        return await signatureVerificationSampler.isBlacklisted(relay: relay)
    }

    /// Get all blacklisted relay URLs
    public func getBlacklistedRelays() async -> Set<String> {
        return await signatureVerificationSampler.getBlacklistedRelays()
    }

    /// Clear the signature verification cache
    public func clearSignatureCache() async {
        await signatureVerificationSampler.clearCache()
    }

    /// Set the signature verification delegate
    public func setSignatureVerificationDelegate(_ delegate: NDKSignatureVerificationDelegate) async {
        await signatureVerificationSampler.setDelegate(delegate)
    }
}

// MARK: - Relay Pool Implementation

public class NDKRelayPool {
    var relaysByUrl: [RelayURL: NDKRelay] = [:]

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
    public func connectedRelays() async -> [NDKRelay] {
        var connected: [NDKRelay] = []
        for relay in relays {
            let state = await relay.connectionState
            if state == .connected {
                connected.append(relay)
            }
        }
        return connected
    }

    func connectAll() async {
        print("[NDKRelayPool] connectAll() called with \(relays.count) relays")
        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                print("[NDKRelayPool] Starting connection task for \(relay.url)")
                group.addTask {
                    do {
                        try await relay.connect()
                        print("[NDKRelayPool] Connected to \(relay.url)")
                    } catch {
                        print("[NDKRelayPool] Failed to connect to \(relay.url): \(error)")
                    }
                }
            }
            print("[NDKRelayPool] Waiting for all connection tasks...")
        }
        print("[NDKRelayPool] All connection tasks completed")
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
        let connectedRelays = await self.connectedRelays()
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
            events[eventId]
        }
    }

    func getAllEvents() -> [NDKEvent] {
        return queue.sync {
            Array(events.values)
        }
    }

    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.events.removeAll()
        }
    }
}
