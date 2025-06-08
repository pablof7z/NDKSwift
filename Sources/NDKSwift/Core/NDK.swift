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

    // MARK: - Outbox Model Support

    /// Outbox configuration
    public var outboxConfig: NDKOutboxConfig = .default

    /// Outbox tracker (lazy)
    var _outboxTracker: NDKOutboxTracker?

    /// Relay ranker (lazy)
    var _relayRanker: NDKRelayRanker?

    /// Relay selector (lazy)
    var _relaySelector: NDKRelaySelector?

    /// Publishing strategy (lazy)
    var _publishingStrategy: NDKPublishingStrategy?

    /// Fetching strategy (lazy)
    var _fetchingStrategy: NDKFetchingStrategy?

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
        relay.observeConnectionState { [weak self] state in
            if case .connected = state {
                Task { [weak self] in
                    await self?.publishQueuedEvents(for: relay)
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
            guard signer != nil else {
                throw NDKError.crypto("no_signer", "No signer configured")
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
            // TODO: Handle unpublished events tracking
            // The new cache doesn't have unpublished event tracking yet
            
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
                    if relay.connectionState != .connected {
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

        // Store the subscription immediately in a sync manner to avoid race conditions
        subscription.registrationTask = Task {
            await subscriptionManager.addSubscription(subscription)
        }

        return subscription
    }

    /// Fetch events matching the given filters (one-shot query)
    public func fetchEvents(
        filters: [NDKFilter],
        relays: Set<NDKRelay>? = nil,
        cacheStrategy: NDKCacheStrategy = .cacheFirst
    ) async throws -> Set<NDKEvent> {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        options.relays = relays
        options.cacheStrategy = cacheStrategy

        let subscription = subscribe(filters: filters, options: options)
        
        var events: [NDKEvent] = []
        
        // Collect events until EOSE
        for await update in subscription.updates {
            switch update {
            case .event(let event):
                events.append(event)
            case .eose:
                break
            case .error(let error):
                throw error
            }
        }

        return Set(events)
    }
    
    /// Fetch events matching a single filter (one-shot query)
    public func fetchEvents(
        _ filter: NDKFilter,
        relays: Set<NDKRelay>? = nil,
        cacheStrategy: NDKCacheStrategy = .cacheFirst
    ) async throws -> Set<NDKEvent> {
        return try await fetchEvents(filters: [filter], relays: relays, cacheStrategy: cacheStrategy)
    }

    /// Fetch a single event by ID (hex or bech32 format)
    public func fetchEvent(
        _ idOrBech32: String,
        relays: Set<NDKRelay>? = nil,
        cacheStrategy: NDKCacheStrategy = .cacheFirst
    ) async throws -> NDKEvent? {
        let filter = try NostrIdentifier.createFilter(from: idOrBech32)
        let events = try await fetchEvents(filters: [filter], relays: relays, cacheStrategy: cacheStrategy)
        return events.first
    }

    /// Fetch a single event matching the filter
    public func fetchEvent(
        _ filter: NDKFilter,
        relays: Set<NDKRelay>? = nil,
        cacheStrategy: NDKCacheStrategy = .cacheFirst
    ) async throws -> NDKEvent? {
        let events = try await fetchEvents(filters: [filter], relays: relays, cacheStrategy: cacheStrategy)
        return events.first
    }
    
    /// Fetch a user's profile (metadata event)
    public func fetchProfile(
        _ pubkey: String,
        relays: Set<NDKRelay>? = nil,
        cacheStrategy: NDKCacheStrategy = .cacheFirst
    ) async throws -> NDKUserProfile? {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.metadata]
        )
        
        if let metadataEvent = try await fetchEvent(filter, relays: relays, cacheStrategy: cacheStrategy) {
            return NDKUserProfile.from(metadataEvent: metadataEvent)
        }
        
        return nil
    }

    // MARK: - Subscription Manager Integration

    /// Process an event received from a relay (called by relay connections)
    func processEvent(_ event: NDKEvent, from relay: NDKRelay) {
        // Mark event as seen on this relay
        event.markSeenOn(relay: relay.url)

        Task {
            // Get current stats
            var currentStats = relay.getSignatureStats()

            // Verify signature with sampling
            let verificationResult = await signatureVerificationSampler.verifyEvent(
                event,
                from: relay,
                stats: &currentStats
            )

            // Update stats back to relay
            relay.updateSignatureStats { stats in
                stats = currentStats
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
    func processEOSE(subscriptionId: String, from relay: NDKRelay) {
        Task {
            await subscriptionManager.processEOSE(subscriptionId: subscriptionId, from: relay)
        }
    }

    /// Get subscription manager statistics
    public func getSubscriptionStats() async -> NDKSubscriptionManager.SubscriptionStats {
        return await subscriptionManager.getStats()
    }

    /// Process OK message from relay (called by relay connections)
    func processOKMessage(eventId: EventID, accepted: Bool, message: String?, from relay: NDKRelay) {
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
        // TODO: Handle queued events with new cache
        // The new cache doesn't have unpublished event tracking yet
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
