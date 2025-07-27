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

/// Thread-safe actor that manages a pool of relay connections
public actor NDKPool {
    private weak var ndk: NDK?
    private var relayMap: [String: NDKRelay] = [:]

    /// Set of relay URLs that were explicitly added by the developer
    private var explicitRelayUrls: Set<String> = []

    /// Stream of relay pool changes for event-driven observation
    private let poolChangeStream: AsyncStream<NDKPoolChangeEvent>
    private let poolChangeContinuation: AsyncStream<NDKPoolChangeEvent>.Continuation

    /// Cache for blocked relays
    private var cachedBlockedRelays: Set<String> = []
    private var blockedRelaysLastFetched: Date?

    /// Subscription task for blocked relay list updates
    private var blockedRelaySubscriptionTask: Task<Void, Never>?

    init(ndk: NDK) {
        self.ndk = ndk

        // Initialize the relay change stream
        (self.poolChangeStream, self.poolChangeContinuation) = AsyncStream<NDKPoolChangeEvent>.makeStream()

        // Start monitoring blocked relay list if we have a signer
        Task {
            await startBlockedRelaySubscription()
        }
    }

    /// Public accessor for relay pool changes stream
    /// 
    /// Provides real-time notifications of relay pool state changes including additions, removals,
    /// connections, and disconnections. Use this stream to react to pool changes in your application.
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
        poolChangeStream
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
        // Force refresh by clearing cache
        blockedRelaysLastFetched = nil
        let blockedRelays = await getBlockedRelays()

        // Remove any relays that are now blocked
        for (url, _) in relayMap {
            if blockedRelays.contains(url) {
                NDKLogger.log(.info, category: .general, "Removing newly blocked relay from pool: \(url)")
                await removeRelay(url)
            }
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

            // Subscribe for blocked relay list using NDKDataSource
            blockedRelaySubscriptionTask = Task {
                let filter = NDKFilter(
                    authors: [userPubkey],
                    kinds: [EventKind.blockedRelays]
                )

                // Use NDKDataSource with 24 hour maxAge for blocked relay lists
                // This will return cached data immediately if available, then fetch updates
                let dataSource = ndk.observe(
                    filter: filter,
                    maxAge: TimeConstants.day // 24 hours
                )

                var latestEvent: NDKEvent?

                for await event in dataSource.events {
                    // Always process the latest event
                    if latestEvent == nil || event.createdAt > latestEvent!.createdAt {
                        latestEvent = event
                        await processBlockedRelayListUpdate(event)
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
    @discardableResult
    public func addRelay(_ url: RelayURL, origin: NDKRelayOrigin = .explicit) async -> NDKRelay {
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
            let blockedRelay = NDKRelay(url: normalizedUrl)
            return blockedRelay
        }

        // Create new relay
        let relay = NDKRelay(url: normalizedUrl)
        if let ndk = ndk {
            relay.setNDK(ndk)
        }
        await relay.setOrigin(origin)
        relayMap[normalizedUrl] = relay

        // Track explicit relays
        if case .explicit = origin {
            explicitRelayUrls.insert(normalizedUrl)
        }

        // Set up connection state observer to publish queued events and emit pool events
        await relay.observeConnectionState { [weak self, weak relay] state in
            guard let self = self, let relay = relay else { return }
            switch state {
            case .connected, .authenticated:
                // Emit pool connection event
                self.poolChangeContinuation.yield(.relayConnected(relay))
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
                self.poolChangeContinuation.yield(.relayDisconnected(relay))
            case .failed(let error):
                // Emit pool disconnection event
                self.poolChangeContinuation.yield(.relayDisconnected(relay))
                NDKLogger.log(.warning, category: .relay, "🔴 Relay failed: \(relay.url), error: \(error)")
            case .connecting, .disconnecting, .authRequired, .authenticating:
                // Don't emit events for transitional states
                NDKLogger.log(.trace, category: .relay, "🔄 Relay transitional state: \(state) for \(relay.url)")
                break
            }
        }

        // Emit relay added event
        poolChangeContinuation.yield(.relayAdded(relay))

        return relay
    }

    /// Remove a relay from the pool
    public func removeRelay(_ url: RelayURL) async {
        let normalizedUrl = url.normalizedRelayURL
        NDKLogger.log(.debug, category: .relay, "➖ Removing relay from pool: \(normalizedUrl)")

        if let relay = relayMap.removeValue(forKey: normalizedUrl) {
            await relay.disconnect()

            // Emit relay removed event
            poolChangeContinuation.yield(.relayRemoved(normalizedUrl))
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

    /// Get connected relay URLs
    public var connectedRelayURLs: Set<RelayURL> {
        get async {
            let connected = await connectedRelays()
            return Set(connected.map { $0.url })
        }
    }

    /// Get explicit relays (added by developer)
    public func explicitRelays() async -> [NDKRelay] {
        relayMap.values.filter { relay in
            explicitRelayUrls.contains(relay.url)
        }
    }

    /// Get connected explicit relays
    public func connectedExplicitRelays() async -> [NDKRelay] {
        await explicitRelays().asyncFilter { relay in
            await relay.connectionState == .connected
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
              let signer = ndk.signer else {
            return []
        }

        do {
            let userPubkey = try await signer.pubkey

            // Try to get the user's relay list from outbox tracker
            if let relayItem = await ndk.outboxTracker.getRelaysSyncFor(pubkey: userPubkey, type: .both) {
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
        let relayCount = relays.count

        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        try await relay.connect()
                    } catch {
                        NDKLogger.log(.error, category: .relay, "❌ Failed to connect to \(relay.url): \(error)")
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
    public func prepareRelays(_ urls: [String], autoConnect: Bool = false) async -> [NDKRelay] {
        NDKLogger.log(.debug, category: .relay, "🔧 Preparing \(urls.count) relays, autoConnect: \(autoConnect)")
        var preparedRelays: [NDKRelay] = []

        // First, ensure all relays exist in the pool
        for url in urls {
            let relay = await addRelay(url)
            preparedRelays.append(relay)
        }

        // Optionally connect to disconnected relays
        if autoConnect {
            await withTaskGroup(of: Void.self) { group in
                for relay in preparedRelays {
                    group.addTask {
                        let connectionState = await relay.connectionState
                        if connectionState != .connected && connectionState != .connecting {
                            do {
                                try await relay.connect()
                            } catch {
                                NDKLogger.log(.error, category: .relay, "[NDKPool] Failed to connect to relay \(relay.url): \(error)")
                            }
                        }
                    }
                }
            }
        }

        return preparedRelays
    }

    // MARK: - Private Helpers

    private func handleRelayConnected(_ relay: NDKRelay) async {
        guard let ndk = ndk else {
            NDKLogger.log(.warning, category: .relay, "⚠️ No NDK instance to handle relay connection")
            return
        }
        await ndk.eventManager.publishQueuedEvents(for: relay)
    }

    // MARK: - Cleanup

    /// Stop all subscriptions and clean up resources
    public func stop() async {
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

