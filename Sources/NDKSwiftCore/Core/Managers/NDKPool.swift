import Foundation

/// Represents a change in the relay pool state
/// Used to notify observers about relay additions, removals, and connection state changes
public enum NDKPoolChangeEvent: Sendable {
    /// A new relay was added to the pool
    case relayAdded(NDKRelay)
    /// A relay was removed from the pool
    case relayRemoved(RelayURL)
    /// A relay successfully connected
    case relayConnected(NDKRelay)
    /// A relay disconnected or failed to connect
    case relayDisconnected(NDKRelay)
}

/// Represents a publish event notification from a relay
/// Used to notify observers about per-relay publish success/failure
public struct NDKRelayPublishEvent: Sendable {
    /// The event ID that was published
    public let eventId: EventID
    /// The relay URL that accepted or rejected the event
    public let relayUrl: RelayURL
    /// Whether the relay accepted the event
    public let success: Bool
    /// Optional error message from the relay (when success is false)
    public let message: String?
    /// Timestamp when the publish result was received
    public let timestamp: Date

    public init(
        eventId: EventID,
        relayUrl: RelayURL,
        success: Bool,
        message: String? = nil,
        timestamp: Date = Date()
    ) {
        self.eventId = eventId
        self.relayUrl = relayUrl
        self.success = success
        self.message = message
        self.timestamp = timestamp
    }
}

/// Thread-safe actor that manages a pool of relay connections
public actor NDKPool {
    private weak var ndk: NDK?
    private var relayMap: [String: NDKRelay] = [:]
    private nonisolated let config: NDKConnectionConfig

    /// Set of relay URLs that were added as app relays
    private var appRelayUrls: Set<String> = []

    /// Whether connectAll() has been called - new relays will auto-connect after this
    private var hasStartedConnecting = false

    /// NIP-77 sync handlers indexed by normalized relay URL
    /// This must be an instance property (not static) to benefit from actor isolation
    var syncHandlers: [String: NIP77SyncHandler] = [:]

    /// Continuations for relay pool change subscribers (supports multiple consumers)
    private var poolChangeContinuations: [UUID: AsyncStream<NDKPoolChangeEvent>.Continuation] = [:]

    /// Stream of relay publish events for event-driven observation
    private let publishEventStream: AsyncStream<NDKRelayPublishEvent>
    private let publishEventContinuation: AsyncStream<NDKRelayPublishEvent>.Continuation

    /// Cache for blocked relays
    private var cachedBlockedRelays: Set<String> = []
    private var blockedRelaysLastFetched: Date?

    /// Subscription task for blocked relay list updates
    private var blockedRelaySubscriptionTask: Task<Void, Never>?

    /// Connection lifecycle monitor
    private let connectionMonitor: NDKConnectionMonitor

    /// Network connectivity monitor
    private let networkMonitor: NDKNetworkMonitor

    init(ndk: NDK, config: NDKConnectionConfig = .default) {
        self.ndk = ndk
        self.config = config
        self.connectionMonitor = NDKConnectionMonitor()
        self.networkMonitor = NDKNetworkMonitor()

        // Initialize the publish event stream
        (publishEventStream, publishEventContinuation) = AsyncStream<NDKRelayPublishEvent>.makeStream()

        // Start monitoring blocked relay list if we have a signer
        Task {
            await startBlockedRelaySubscription()
            await setupMonitors()
        }
    }

    /// Create a new relay pool changes stream for a subscriber
    ///
    /// Each call creates a new stream that receives all pool change events.
    /// Multiple consumers can subscribe and each will receive all events.
    ///
    /// Example:
    /// ```swift
    /// for await change in await pool.relayChanges {
    ///     switch change {
    ///     case .relayAdded(let relay):
    ///         print("New relay added: \(relay.url)")
    ///     case .relayConnected(let relay):
    ///         print("Relay connected: \(relay.url)")
    ///     // ... handle other cases
    ///     }
    /// }
    /// ```
    public var relayChanges: AsyncStream<NDKPoolChangeEvent> {
        let id = UUID()
        // Use makeStream() for proper actor isolation - the continuation is stored
        // directly on the actor rather than inside a non-isolated closure
        let (stream, continuation) = AsyncStream<NDKPoolChangeEvent>.makeStream()
        poolChangeContinuations[id] = continuation

        // Set up termination handler to clean up the continuation when stream ends
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { [weak self] in
                await self?.removePoolChangeSubscriber(id)
            }
        }

        return stream
    }

    /// Remove a pool change subscriber
    private func removePoolChangeSubscriber(_ id: UUID) {
        poolChangeContinuations.removeValue(forKey: id)
    }

    /// Emit a pool change event to all subscribers
    private func emitPoolChange(_ event: NDKPoolChangeEvent) {
        for continuation in poolChangeContinuations.values {
            continuation.yield(event)
        }
    }

    /// Public accessor for relay publish events stream
    ///
    /// Provides real-time notifications when events are published to relays, including
    /// per-relay success/failure status and error messages.
    ///
    /// Example:
    /// ```swift
    /// for await publishEvent in await pool.publishEvents {
    ///     if publishEvent.success {
    ///         print("Event \(publishEvent.eventId) published to \(publishEvent.relayUrl)")
    ///     } else {
    ///         print("Failed to publish \(publishEvent.eventId) to \(publishEvent.relayUrl): \(publishEvent.message ?? "Unknown error")")
    ///     }
    /// }
    /// ```
    public var publishEvents: AsyncStream<NDKRelayPublishEvent> {
        publishEventStream
    }

    // MARK: - Publish Event Management

    /// Emit a publish event notification
    ///
    /// Called internally when an event is published to a relay with success or failure.
    /// This method yields the publish event to the stream for observers.
    ///
    /// - Parameters:
    ///   - eventId: The event ID that was published
    ///   - relayUrl: The relay URL that accepted or rejected the event
    ///   - success: Whether the relay accepted the event
    ///   - message: Optional error message from the relay (when success is false)
    func emitPublishEvent(eventId: EventID, relayUrl: RelayURL, success: Bool, message: String? = nil) {
        let publishEvent = NDKRelayPublishEvent(
            eventId: eventId,
            relayUrl: relayUrl,
            success: success,
            message: message
        )
        publishEventContinuation.yield(publishEvent)
    }

    // MARK: - Blocked Relay Management

    /// Get the set of blocked relay URLs from the user's blocked relay list
    private func getBlockedRelays() async -> Set<String> {
        // Always return cached value immediately for non-blocking operation
        // The background subscription will keep it updated
        return cachedBlockedRelays
    }

    /// Refresh the blocked relay list and remove any currently connected relays that are now blocked
    ///
    /// Forces an immediate refresh of the user's blocked relay list (kind 10013 events) and removes
    /// any currently connected relays that appear on the updated block list. This is useful when
    /// you know the block list has been updated and want to apply changes immediately.
    ///
    /// - Note: The blocked relay list is automatically monitored in the background, so manual
    ///   refresh is typically not necessary unless you need immediate updates.
    public func refreshBlockedRelays() async {
        guard let ndk = ndk, let signer = ndk.signer else {
            return
        }

        do {
            let userPubkey = try await signer.pubkey

            // Fetch the latest blocked relay list from cache
            let filter = NDKFilter(
                authors: [userPubkey],
                kinds: [EventKind.blockedRelays]
            )

            let events = try await ndk.cache.queryEvents(filter)
            if let latestEvent = events.sorted(by: { $0.createdAt > $1.createdAt }).first {
                await processBlockedRelayListUpdate(latestEvent)
            }
        } catch {
            NDKLogger.log(.error, category: .general, "Failed to refresh blocked relays: \(error)")
        }
    }

    /// Start subscription for blocked relay list updates
    private func startBlockedRelaySubscription() async {
        // Cancel any existing subscription
        blockedRelaySubscriptionTask?.cancel()

        guard let ndk = ndk, let signer = ndk.signer else {
            return
        }

        do {
            let userPubkey = try await signer.pubkey

            // Subscribe for blocked relay list using NDKSubscription
            blockedRelaySubscriptionTask = Task {
                let filter = NDKFilter(
                    authors: [userPubkey],
                    kinds: [EventKind.blockedRelays]
                )

                // Use NDKSubscription with 24 hour maxAge for blocked relay lists
                // This will return cached data immediately if available, then fetch updates
                let dataSource = ndk.subscribe(
                    filter: filter,
                    maxAge: TimeConstants.day // 24 hours
                )

                var latestEvent: NDKEvent?

                for await batch in dataSource.events {
                    for event in batch {
                        // Always process the latest event
                        if latestEvent == nil || event.createdAt > (latestEvent?.createdAt ?? 0) {
                            latestEvent = event
                            await processBlockedRelayListUpdate(event)
                        }
                    }
                }
            }
        } catch {
            NDKLogger.log(.error, category: .general, "Failed to start blocked relay subscription: \(error)")
        }
    }

    /// Process a blocked relay list update event
    private func processBlockedRelayListUpdate(_ event: NDKEvent) async {
        NDKLogger.log(.info, category: .general, "Processing blocked relay list update")

        let blockedRelayList = NDKList.from(event, ndk: ndk)
        let newBlockedRelays = Set(blockedRelayList.blockedRelays.map { $0.normalizedRelayURL })
        let oldBlockedRelays = cachedBlockedRelays

        cachedBlockedRelays = newBlockedRelays
        blockedRelaysLastFetched = Date()

        // Find newly blocked relays
        let newlyBlocked = newBlockedRelays.subtracting(oldBlockedRelays)

        if !newlyBlocked.isEmpty {
            NDKLogger.log(.info, category: .general, "Found \(newlyBlocked.count) newly blocked relays")

            // Remove any newly blocked relays from pool
            for blockedUrl in newlyBlocked {
                if relayMap[blockedUrl] != nil {
                    NDKLogger.log(.warning, category: .general, "Removing newly blocked relay from pool: \(blockedUrl)")
                    await removeRelay(blockedUrl)
                }
            }
        }
    }

    // MARK: - Relay Management

    /// Add a relay to the pool
    /// - Parameters:
    ///   - url: The relay URL to add
    ///   - origin: The origin of this relay (why it's being added)
    ///   - reason: Optional human-readable reason for debugging (e.g., "subscription for kinds 1,6")
    @discardableResult
    public func addRelay(_ url: RelayURL, origin: NDKRelayOrigin = .appRelays, reason: String? = nil) async -> NDKRelay {
        let normalizedUrl = url.normalizedRelayURL

        // Check if already exists
        if let existing = relayMap[normalizedUrl] {
            return existing
        }

        // Check if relay is blocked
        let blockedRelays = await getBlockedRelays()
        if blockedRelays.contains(normalizedUrl) {
            NDKLogger.log(.warning, category: .general, "Attempted to add blocked relay: \(normalizedUrl)")
            // Create a disconnected relay instance to return (won't be added to pool)
            let blockedRelay = NDKRelay(url: normalizedUrl, config: config)
            return blockedRelay
        }

        // Create new relay with connection config
        let relay = NDKRelay(url: normalizedUrl, config: config)
        if let ndk = ndk {
            await relay.setNDK(ndk)
        }
        await relay.setOrigin(origin)

        // Set persistence based on origin
        // App and discovery relays are persistent (never evicted)
        // Outbox-discovered relays are not persistent (can be evicted when idle)
        switch origin {
        case .appRelays, .discovery:
            await relay.setPersistent(true)
        case .outbox:
            await relay.setPersistent(false)
        }

        relayMap[normalizedUrl] = relay

        // Log pool size on addition (helps debug connection explosion)
        let originStr: String
        switch origin {
        case .appRelays: originStr = "appRelays"
        case .discovery: originStr = "discovery"
        case let .outbox(pubkey): originStr = "outbox(\(pubkey.prefix(8)))"
        }
        let reasonStr = reason.map { " | reason: \($0)" } ?? ""
        NDKLogger.log(.info, category: .relay,
                      "📊 Pool: ADDING relay \(normalizedUrl) | origin: \(originStr)\(reasonStr) | pool size: \(relayMap.count)")

        // Log warning if pool is growing too large
        if relayMap.count > 50 {
            NDKLogger.log(.warning, category: .relay,
                          "⚠️ Pool size exceeds 50 relays (\(relayMap.count)) - potential connection explosion")
        }

        // Track app relays
        if case .appRelays = origin {
            appRelayUrls.insert(normalizedUrl)
        }

        // Set up connection state observer to publish queued events and emit pool events
        await relay.observeConnectionState { [weak self, weak relay] state in
            guard let self = self, let relay = relay else { return }
            switch state {
            case .connected, .authenticated:
                // Emit pool connection event
                Task {
                    await self.emitPoolChange(.relayConnected(relay))
                }
                if case .authenticated = state {
                    NDKLogger.log(.info, category: .relay, "🔐 Relay authenticated: \(relay.url)")
                    // Also retry any auth-failed events when transitioning to authenticated
                    Task {
                        if let ndk = await self.ndk {
                            await ndk.eventManager.retryAuthenticatedEvents(for: relay)
                        }
                    }
                } else {
                    NDKLogger.log(.info, category: .relay, "🟢 Relay connected: \(relay.url)")
                }
                Task {
                    await self.handleRelayConnected(relay)
                }
            case .disconnected:
                // Emit pool disconnection event
                Task {
                    await self.emitPoolChange(.relayDisconnected(relay))
                }
            case let .failed(error):
                // Emit pool disconnection event
                Task {
                    await self.emitPoolChange(.relayDisconnected(relay))
                }
                Task {
                    let shouldLog = await connectionErrorRateLimiter.shouldLogError(for: relay.url, errorType: "relayFailed")
                    if shouldLog {
                        NDKLogger.log(.warning, category: .relay, "🔴 Relay failed: \(relay.url), error: \(error)")
                    }
                }
            case .connecting, .disconnecting, .authRequired, .authenticating:
                // Don't emit events for transitional states
                NDKLogger.log(.trace, category: .relay, "🔄 Relay transitional state: \(state) for \(relay.url)")
            }
        }

        // Emit relay added event
        emitPoolChange(.relayAdded(relay))

        // Auto-connect if pool has already started connecting
        if hasStartedConnecting {
            NDKLogger.log(.info, category: .relay, "🔌 Auto-connecting relay \(normalizedUrl) (pool already connecting)")
            do {
                try await relay.connect()
            } catch {
                NDKLogger.log(.error, category: .relay, "❌ Failed to auto-connect relay \(normalizedUrl): \(error)")
            }
        }

        return relay
    }

    /// Remove a relay from the pool
    public func removeRelay(_ url: RelayURL) async {
        let normalizedUrl = url.normalizedRelayURL
        NDKLogger.log(.debug, category: .relay, "➖ Removing relay from pool: \(normalizedUrl)")

        if let relay = relayMap.removeValue(forKey: normalizedUrl) {
            await relay.disconnect()

            // Emit relay removed event
            emitPoolChange(.relayRemoved(normalizedUrl))
            NDKLogger.log(.info, category: .relay, "✅ Removed relay from pool: \(normalizedUrl), remaining relays: \(relayMap.count)")
        } else {
            NDKLogger.log(.warning, category: .relay, "⚠️ Attempted to remove non-existent relay: \(normalizedUrl)")
        }
    }

    /// Get all relays
    public var relays: [NDKRelay] {
        Array(relayMap.values)
    }

    /// Get connected relays
    ///
    /// Returns an array of all relays that are currently in the connected state.
    /// This method filters the relay pool to include only relays with an active WebSocket connection.
    ///
    /// - Returns: Array of connected `NDKRelay` instances
    ///
    /// Example:
    /// ```swift
    /// let connected = await pool.connectedRelays()
    /// print("Connected to \(connected.count) relays")
    /// ```
    public func connectedRelays() async -> [NDKRelay] {
        await relays.asyncFilter { relay in
            let state = await relay.connectionState
            return state == .connected || state == .authenticated
        }
    }

    /// Get the authors that caused us to connect to a specific relay
    public func getAuthorsForRelay(_ url: RelayURL) async -> [String] {
        let normalizedUrl = url.normalizedRelayURL
        guard let relay = relayMap[normalizedUrl] else { return [] }

        let origin = await relay.origin
        switch origin {
        case let .outbox(authorPubkey):
            return [authorPubkey]
        case .appRelays, .discovery:
            return []
        }
    }

    /// Get a mapping of relays to the authors that caused us to connect to them
    public func getRelayAuthorMapping() async -> [RelayURL: [String]] {
        var mapping: [RelayURL: [String]] = [:]

        for (url, relay) in relayMap {
            let origin = await relay.origin
            switch origin {
            case let .outbox(authorPubkey):
                mapping[url] = [authorPubkey]
            case .appRelays, .discovery:
                // These relays weren't added because of specific authors
                mapping[url] = []
            }
        }

        return mapping
    }

    /// Get connected relay URLs
    public var connectedRelayURLs: Set<RelayURL> {
        get async {
            let connected = await connectedRelays()
            return Set(connected.map { $0.url })
        }
    }

    /// Get app relays (added by app/developer)
    public var appRelays: [NDKRelay] {
        relayMap.values.filter { relay in
            appRelayUrls.contains(relay.url)
        }
    }

    /// Get connected app relays
    public func connectedAppRelays() async -> [NDKRelay] {
        await appRelays.asyncFilter { relay in
            await relay.connectionState == .connected
        }
    }

    /// Get relays filtered by origin
    public func relays(withOrigin origin: NDKRelayOrigin) async -> [NDKRelay] {
        await relays.asyncFilter { relay in
            await relay.origin == origin
        }
    }

    /// Get a specific relay by URL
    public func getRelay(for url: RelayURL) async -> NDKRelay? {
        let normalizedUrl = url.normalizedRelayURL
        return relayMap[normalizedUrl]
    }

    /// Get current user's relays from their relay list
    ///
    /// Fetches the relay URLs from the current user's relay list (NIP-65, kind 10002 events).
    /// This includes both read and write relays configured by the user.
    ///
    /// - Returns: Set of relay URLs from the user's relay list, or empty set if:
    ///   - No signer is configured
    ///   - User has no relay list published
    ///   - An error occurs during fetching
    ///
    /// - Note: This method uses the outbox tracker cache for efficient retrieval
    public func getCurrentUserRelayUrls() async -> Set<String> {
        guard let ndk = ndk,
              let signer = ndk.signer
        else {
            return []
        }

        do {
            let userPubkey = try await signer.pubkey

            // Try to get the user's relay list from outbox manager
            if let relayItem = await ndk.outbox.getRelaysSyncFor(pubkey: userPubkey, type: .both) {
                var userRelays = Set<String>()

                // Add both read and write relays
                userRelays.formUnion(relayItem.readRelays.map { $0.url })
                userRelays.formUnion(relayItem.writeRelays.map { $0.url })

                return userRelays
            }
        } catch {
            NDKLogger.log(.debug, category: .general, "Failed to get current user pubkey: \(error)")
        }

        return []
    }

    /// Get a snapshot of all relay states for quick status checks
    ///
    /// Provides a complete overview of the connection state for all relays in the pool.
    /// Useful for displaying relay status in UI or monitoring connection health.
    ///
    /// - Returns: Dictionary mapping relay URLs to their current connection states
    ///
    /// Example:
    /// ```swift
    /// let snapshot = await pool.getRelayStateSnapshot()
    /// for (url, state) in snapshot {
    ///     print("\(url): \(state)")
    /// }
    /// ```
    public func getRelayStateSnapshot() async -> [RelayURL: NDKRelayConnectionState] {
        var snapshot: [RelayURL: NDKRelayConnectionState] = [:]
        for relay in relays {
            snapshot[relay.url] = await relay.connectionState
        }
        return snapshot
    }

    /// Get connection summary (connected count, total count)
    ///
    /// Provides a quick summary of relay pool connectivity status.
    ///
    /// - Returns: Tuple containing:
    ///   - connected: Number of relays currently connected
    ///   - total: Total number of relays in the pool
    ///
    /// Example:
    /// ```swift
    /// let summary = await pool.getConnectionSummary()
    /// print("Connected to \(summary.connected)/\(summary.total) relays")
    /// ```
    public func getConnectionSummary() async -> (connected: Int, total: Int) {
        let states = await getRelayStateSnapshot()
        let connected = states.values.filter { $0 == .connected || $0 == .authenticated }.count
        return (connected: connected, total: states.count)
    }

    /// Connect to all relays
    ///
    /// Attempts to establish connections to all relays in the pool concurrently.
    /// Connection attempts are made in parallel for efficiency. Failed connections
    /// are logged but don't prevent other relays from connecting.
    ///
    /// - Note: This method returns after all connection attempts complete, regardless
    ///   of success or failure. Check connection states afterwards if needed.
    ///
    /// Example:
    /// ```swift
    /// await pool.connectAll()
    /// let summary = await pool.getConnectionSummary()
    /// print("Connected to \(summary.connected) relays")
    /// ```
    public func connectAll() async {
        // Mark that connecting has started - new relays will auto-connect from now on
        hasStartedConnecting = true

        let relayCount = relays.count

        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        try await relay.connect()
                    } catch {
                        Task {
                            let shouldLog = await connectionErrorRateLimiter.shouldLogError(for: relay.url, errorType: "connectFailed")
                            if shouldLog {
                                NDKLogger.log(.error, category: .relay, "❌ Failed to connect to \(relay.url): \(error)")
                            }
                        }
                    }
                }
            }
        }

        let connectedCount = await connectedRelays().count
        NDKLogger.log(.info, category: .relay, "✅ Connection attempt complete - connected: \(connectedCount)/\(relayCount)")
    }

    /// Disconnect from all relays
    ///
    /// Gracefully disconnects from all relays in the pool concurrently.
    /// All active WebSocket connections are closed and resources are cleaned up.
    ///
    /// - Note: This method waits for all disconnections to complete before returning
    ///
    /// Example:
    /// ```swift
    /// await pool.disconnectAll()
    /// ```
    public func disconnectAll() async {
        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    await relay.disconnect()
                }
            }
        }
    }

    /// Prepare relays for use by ensuring they exist in the pool and optionally connecting them
    ///
    /// This method is useful for pre-loading relays before performing operations. It ensures
    /// the specified relays are added to the pool and can optionally establish connections.
    ///
    /// - Parameters:
    ///   - urls: The relay URLs to prepare
    ///   - autoConnect: Whether to automatically connect to disconnected relays (default: false)
    ///   - origin: The origin to use when adding new relays (default: .outbox with empty pubkey)
    ///
    /// - Returns: Array of prepared relay instances
    ///
    /// - Note: Blocked relays will be created but not added to the pool or connected
    ///
    /// Example:
    /// ```swift
    /// // Just ensure relays exist in pool
    /// let relays = await pool.prepareRelays(["wss://relay1.com", "wss://relay2.com"])
    ///
    /// // Ensure relays exist and connect them
    /// let connectedRelays = await pool.prepareRelays(
    ///     ["wss://relay1.com", "wss://relay2.com"],
    ///     autoConnect: true
    /// )
    /// ```
    public func prepareRelays(_ urls: [String], autoConnect: Bool = false, origin: NDKRelayOrigin? = nil) async -> [NDKRelay] {
        NDKLogger.log(.debug, category: .relay, "🔧 Preparing \(urls.count) relays, autoConnect: \(autoConnect)")
        var preparedRelays: [NDKRelay] = []

        // First, ensure all relays exist in the pool
        // Use provided origin or default to outbox (not appRelays) to avoid polluting app relay list
        let relayOrigin = origin ?? .outbox(authorPubkey: "")
        for url in urls {
            let relay = await addRelay(url, origin: relayOrigin)
            preparedRelays.append(relay)
        }

        // Optionally connect to disconnected relays
        if autoConnect {
            await withTaskGroup(of: Void.self) { group in
                for relay in preparedRelays {
                    group.addTask {
                        let connectionState = await relay.connectionState
                        if connectionState != .connected, connectionState != .connecting {
                            do {
                                try await relay.connect()
                            } catch {
                                Task {
                                    let shouldLog = await connectionErrorRateLimiter.shouldLogError(for: relay.url, errorType: "poolConnectFailed")
                                    if shouldLog {
                                        NDKLogger.log(.error, category: .relay, "[NDKPool] Failed to connect to relay \(relay.url): \(error)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return preparedRelays
    }

    // MARK: - Idle Relay Eviction

    /// Evict idle non-persistent relays from the pool
    ///
    /// Removes relays that:
    /// - Are not persistent (isPersistent == false)
    /// - Have been idle for longer than the threshold
    ///
    /// - Parameter idleThreshold: Time in seconds after which a relay is considered idle
    /// - Returns: Set of relay URLs that were evicted
    public func evictIdleRelays(idleThreshold: TimeInterval) async -> Set<RelayURL> {
        var evictedUrls = Set<RelayURL>()

        for relay in relays {
            // Skip persistent relays
            let isPersistent = await relay.isPersistent
            if isPersistent {
                continue
            }

            // Check idle time
            let idleTime = await relay.idleTime
            if idleTime >= idleThreshold {
                evictedUrls.insert(relay.url)
            }
        }

        // Remove evicted relays
        for url in evictedUrls {
            await removeRelay(url)
            NDKLogger.log(.info, category: .relay, "🗑️ Evicted idle relay: \(url)")
        }

        if !evictedUrls.isEmpty {
            NDKLogger.log(.info, category: .relay, "🧹 Evicted \(evictedUrls.count) idle relays")
        }

        return evictedUrls
    }

    // MARK: - Private Helpers

    private func handleRelayConnected(_ relay: NDKRelay) async {
        guard let ndk = ndk else {
            NDKLogger.log(.warning, category: .relay, "⚠️ No NDK instance to handle relay connection")
            return
        }
        await ndk.eventManager.publishQueuedEvents(for: relay)

        // Retry any pending outbox discoveries that failed when no relays were connected
        Task {
            await ndk.outbox.retryPendingDiscoveries()
        }
    }

    // MARK: - Connection Monitoring

    /// Setup lifecycle and network monitors
    private func setupMonitors() async {
        // Setup connection monitor delegate
        await connectionMonitor.setDelegate(self)

        // Setup network monitor delegate
        await networkMonitor.setDelegate(self)

        // Start monitors if enabled
        if config.enableLifecycleMonitoring {
            await connectionMonitor.startMonitoring()
        }

        if config.enableNetworkMonitoring {
            await networkMonitor.startMonitoring()
        }
    }

    /// Reconnect all relays
    private func reconnectAll() async {
        NDKLogger.log(.info, category: .connection, "🔄 Reconnecting all relays...")

        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        // First disconnect if connected
                        let state = await relay.connectionState
                        if state == .connected || state == .authenticated {
                            await relay.disconnect()
                        }

                        // Small delay to ensure clean disconnect
                        try? await Task.sleep(nanoseconds: UInt64(0.1 * Double(TimeConstants.nanosecondsPerSecond)))

                        // Then reconnect
                        try await relay.connect()
                    } catch {
                        Task {
                            let shouldLog = await connectionErrorRateLimiter.shouldLogError(for: relay.url, errorType: "reconnectFailed")
                            if shouldLog {
                                NDKLogger.log(.error, category: .relay, "❌ Failed to reconnect to \(relay.url): \(error)")
                            }
                        }
                    }
                }
            }
        }

        let connectedCount = await connectedRelays().count
        NDKLogger.log(.info, category: .relay, "✅ Reconnection complete - connected: \(connectedCount)/\(relays.count)")
    }

    // MARK: - Cleanup

    /// Stop all subscriptions and clean up resources
    public func stop() async {
        // Stop monitors
        await connectionMonitor.stopMonitoring()
        await networkMonitor.stopMonitoring()

        // Cancel blocked relay subscription
        blockedRelaySubscriptionTask?.cancel()
        blockedRelaySubscriptionTask = nil

        // Clear cached data
        cachedBlockedRelays = []
        blockedRelaysLastFetched = nil
    }

    deinit {
        // Cancel subscription if not already done
        blockedRelaySubscriptionTask?.cancel()
    }
}

// MARK: - NDKConnectionMonitorDelegate

extension NDKPool: NDKConnectionMonitorDelegate {
    nonisolated public func connectionMonitorDidEnterBackground() {
        NDKLogger.log(.info, category: .connection, "📱 App entered background - pausing connection monitoring")
        // Don't disconnect, but monitoring tasks will naturally pause
    }

    nonisolated public func connectionMonitorDidEnterForeground() {
        NDKLogger.log(.info, category: .connection, "📱 App entering foreground - checking connections")
        Task {
            guard self.config.autoReconnectOnForeground else { return }
            await self.reconnectAll()

            // Retry unpublished events - this will connect to their target relays via prepareRelays
            if let ndk = await self.ndk {
                _ = try? await ndk.eventManager.retryUnpublishedEvents()
            }
        }
    }

    nonisolated public func connectionMonitorDidBecomeActive() {
        NDKLogger.log(.debug, category: .connection, "📱 App became active")
    }

    nonisolated public func connectionMonitorWillResignActive() {
        NDKLogger.log(.debug, category: .connection, "📱 App will resign active")
    }
}

// MARK: - NDKNetworkMonitorDelegate

extension NDKPool: NDKNetworkMonitorDelegate {
    nonisolated public func networkMonitorDidGainConnectivity() {
        NDKLogger.log(.info, category: .connection, "🌐 Network connectivity gained - reconnecting")
        Task {
            guard self.config.autoReconnectOnNetworkChange else { return }
            await self.reconnectAll()

            // Retry unpublished events - this will connect to their target relays via prepareRelays
            if let ndk = await self.ndk {
                _ = try? await ndk.eventManager.retryUnpublishedEvents()
            }
        }
    }

    nonisolated public func networkMonitorDidLoseConnectivity() {
        NDKLogger.log(.warning, category: .connection, "🌐 Network connectivity lost")
        // Don't disconnect - let health checks and reconnection handle it
    }

    nonisolated public func networkMonitorDidChangeNetworkType() {
        NDKLogger.log(.info, category: .connection, "🌐 Network type changed - reconnecting")
        Task {
            guard self.config.autoReconnectOnNetworkChange else { return }
            // Small delay to let network stabilize
            try? await Task.sleep(nanoseconds: UInt64(1.0 * Double(TimeConstants.nanosecondsPerSecond)))
            await self.reconnectAll()
        }
    }
}
