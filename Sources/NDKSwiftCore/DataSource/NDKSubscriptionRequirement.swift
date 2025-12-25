import Foundation

/// Manages a single data requirement with proper filter splitting for outbox model
/// Focuses on event deduplication and relay management
actor NDKSubscriptionRequirement {
    nonisolated let filter: NDKFilter
    nonisolated let subscriptionId: String
    nonisolated let internalSubscription: NDKSubscriptionCoordinator
    private let cache: any NDKCache
    private weak var ndk: NDK?
    private let closeOnEose: Bool
    nonisolated let relayStrategy: InternalRelaySelectionStrategy
    private let shouldFetchFromNetwork: Bool
    private let cachePolicy: CachePolicy

    // Event deduplication
    private var seenEventIds = Set<EventID>()

    // Observers - yields batches of events for efficient UI updates
    private var observers: [(id: RequirementID, stream: AsyncStream<[NDKEvent]>, continuation: AsyncStream<[NDKEvent]>.Continuation, filter: NDKFilter)] = []

    // Relay update observers
    private var relayUpdateObservers: [(id: RequirementID, stream: AsyncStream<RelayUpdate>, continuation: AsyncStream<RelayUpdate>.Continuation)] = []

    // Active relay subscriptions (for outbox model)
    private var relaySubscriptions: [RelayURL: RelaySubscription] = [:]

    // Track which authors each relay subscription covers (all relays including fallbacks)
    private var relayAuthorCoverage: [RelayURL: Set<String>] = [:]

    // Track only author-specific relay coverage (NOT fallbacks)
    // Fallback relays should NOT count toward author coverage for relay selection
    private var authorSpecificRelayCoverage: [RelayURL: Set<String>] = [:]

    // Enhanced requirements created by NDKSubscriptionManager
    private var enhancedRequirements: [NDKSubscriptionRequirementHandle] = []

    // EOSE tracking
    private let eoseTracker: EOSETracker
    private var eoseTask: Task<Void, Never>?

    init(
        filter: NDKFilter,
        subscriptionId: String,
        internalSubscription: NDKSubscriptionCoordinator,
        cache: any NDKCache,
        ndk: NDK,
        relays _: Set<RelayURL>?,
        exclusiveRelays _: Bool,
        closeOnEose: Bool,
        relayStrategy: InternalRelaySelectionStrategy,
        shouldFetchFromNetwork: Bool = true,
        cachePolicy: CachePolicy
    ) {
        self.filter = filter
        self.subscriptionId = subscriptionId
        self.internalSubscription = internalSubscription
        self.cache = cache
        self.ndk = ndk
        self.closeOnEose = closeOnEose
        self.relayStrategy = relayStrategy
        self.shouldFetchFromNetwork = shouldFetchFromNetwork
        self.cachePolicy = cachePolicy
        eoseTracker = EOSETracker(subscriptionId: subscriptionId)
    }

    /// Add an observer for events matching this requirement
    /// Returns a stream of event batches for efficient UI updates
    func addObserver(id: RequirementID, individualFilter: NDKFilter) -> AsyncStream<[NDKEvent]> {
        let (stream, continuation) = AsyncStream<[NDKEvent]>.makeStream()
        observers.append((id: id, stream: stream, continuation: continuation, filter: individualFilter))
        return stream
    }

    /// Add an observer for relay updates
    func addRelayUpdateObserver(id: RequirementID) -> AsyncStream<RelayUpdate> {
        let (stream, continuation) = AsyncStream<RelayUpdate>.makeStream()
        relayUpdateObservers.append((id: id, stream: stream, continuation: continuation))
        return stream
    }

    /// Start processing events
    func startProcessing() async {
        // Set up cache observation only if policy allows it
        if cachePolicy != .networkOnly {
            Task { [weak self] in
                guard let self = self else { return }

                let eventStream = await self.cache.observeEvents(
                    matching: self.filter,
                    includeExisting: true
                )

                do {
                    for try await events in eventStream {
                        // Yield entire batch directly - preserves cache batching
                        await self.handleCacheEvents(events)
                    }
                } catch {
                    NDKLogger.log(.error, category: .subscription,
                                  "❌ Cache observation error for '\(self.subscriptionId)': \(error)")
                }
            }
        }

        // Only set up network operations if we should fetch from network
        if shouldFetchFromNetwork {
            // Apply relay strategy
            await applyRelayStrategy()

            // Set up subscription event handling
            await internalSubscription.setOnEvent { [weak self] event, relay in
                await self?.handleNetworkEvent(event, from: relay)
            }

            await internalSubscription.setOnEOSE { [weak self] relay in
                await self?.handleEOSE(from: relay)
            }

            // Start the subscription
            await internalSubscription.start()
        } else {
            // For cache-only subscriptions, we still register with InternalSubscriptionManager
            // This allows them to receive events from network subscriptions with the same fingerprint
            await internalSubscription.setOnEvent { [weak self] event, relay in
                await self?.handleNetworkEvent(event, from: relay)
            }

            // Don't start the subscription (no network activity)
            NDKLogger.log(.debug, category: .subscription,
                          "📚 Cache-only subscription '\(subscriptionId)' created without network fetch")
        }

        // Start EOSE monitoring
        eoseTask = Task { [weak self] in
            await self?.monitorEOSE()
        }
    }

    /// Apply the relay selection strategy
    private func applyRelayStrategy() async {
        // Don't create relay subscriptions if NDK hasn't been connected yet (offline mode)
        // This prevents subscriptions from triggering relay discovery and addition before connect() is called
        guard let ndk = ndk, ndk.hasConnected else {
            NDKLogger.log(.info, category: .subscription,
                          "⏸️  Deferring relay subscription creation for '\(subscriptionId)' - NDK not connected yet (offline mode). Subscriptions will be created when connect() is called.")
            return
        }

        switch relayStrategy {
        case let .explicit(relays):
            // Simple case: use explicit relays
            await eoseTracker.setExpectedRelays(relays)
            await createSubscriptions(for: filter, on: relays)

        case let .outbox(strategy):
            // Complex case: split filters by relay
            // First apply the strategy (which may add fallback relays for unknown authors)
            await applyOutboxStrategy(strategy)
            // Then set expected relays to ALL relays where subscriptions were created
            // This includes both outbox-specific relays AND fallback relays
            await eoseTracker.setExpectedRelays(Set(relaySubscriptions.keys))

        case let .default(relays):
            // Use default relays
            await eoseTracker.setExpectedRelays(relays)
            await createSubscriptions(for: filter, on: relays)
        }
    }

    /// Apply outbox strategy with filter splitting
    private func applyOutboxStrategy(_ strategy: OutboxFilterStrategy) async {
        // Create subscriptions for each relay with its specific filter
        // These are AUTHOR-SPECIFIC relays (from their kind:10002) - NOT fallbacks
        for (relay, relayFilter) in strategy.filtersByRelay {
            await createSubscription(for: relayFilter, on: relay, isFallback: false)
        }

        // If there are unknown authors, use fallback relays
        // These are FALLBACK relays - they should NOT count toward author coverage
        if !strategy.unknownAuthors.isEmpty {
            var fallbackFilter = filter
            fallbackFilter.authors = Array(strategy.unknownAuthors)

            // Get fallback relays (app relays, not discovery relays)
            if let pool = ndk?.pool {
                let allConnectedRelays = await pool.connectedRelayURLs
                // Normalize discovery relay URLs to match the format of connected relays
                let normalizedDiscoveryRelays = Set((ndk?.discoveryConfig.discoveryRelays ?? []).map { $0.normalizedRelayURL })
                var fallbackRelayURLs = allConnectedRelays.subtracting(normalizedDiscoveryRelays)

                // If no relays are connected (offline mode), use configured relay URLs
                // This ensures subscriptions are registered for replay when relays connect
                if fallbackRelayURLs.isEmpty {
                    // First try app relays in the pool
                    let configuredRelays = await pool.appRelays
                    fallbackRelayURLs = Set(configuredRelays.map { $0.url }).subtracting(normalizedDiscoveryRelays)

                    // If pool is empty (connect() not called yet), use the initial relay URLs
                    if fallbackRelayURLs.isEmpty, let ndk = ndk {
                        fallbackRelayURLs = Set(ndk.configuredRelayURLs.map { $0.normalizedRelayURL }).subtracting(normalizedDiscoveryRelays)
                    }

                    if fallbackRelayURLs.isEmpty {
                        // No fallback relays configured - unknown authors won't be queried until their relays are discovered
                        NDKLogger.log(.info, category: .subscription,
                                      "📍 No fallback relays configured, \(strategy.unknownAuthors.count) unknown authors will be queried when their relays are discovered")
                    } else {
                        NDKLogger.log(.debug, category: .subscription,
                                      "📍 No connected relays, using \(fallbackRelayURLs.count) configured relays for \(strategy.unknownAuthors.count) unknown authors")
                    }
                } else {
                    NDKLogger.log(.debug, category: .subscription,
                                  "📍 Using \(fallbackRelayURLs.count) fallback relays for \(strategy.unknownAuthors.count) unknown authors")
                }

                for relay in fallbackRelayURLs {
                    // Mark these as fallback relays - they should NOT count toward author coverage
                    await createSubscription(for: fallbackFilter, on: relay, isFallback: true)
                }
            }
        }
    }

    /// Create subscriptions on specific relays
    /// - Parameter isFallback: If true, these are fallback relays that should NOT count toward author coverage
    private func createSubscriptions(for filter: NDKFilter, on relays: Set<RelayURL>, isFallback: Bool = false) async {
        for relay in relays {
            await createSubscription(for: filter, on: relay, isFallback: isFallback)
        }
    }

    /// Create a subscription on a specific relay
    /// - Parameter isFallback: If true, this is a fallback relay that should NOT count toward author coverage
    private func createSubscription(for filter: NDKFilter, on relayURL: RelayURL, isFallback: Bool = false) async {
        guard let ndk = ndk else { return }

        // Get or create relay
        var relay = await ndk.pool.relay(for: relayURL)

        // If relay doesn't exist in pool, add and connect to it
        if relay == nil {
            NDKLogger.log(.info, category: .subscription,
                          "🔌 Relay not in pool, adding and connecting: \(relayURL)")
            // Determine the correct origin - fallbacks use appRelays, otherwise track the author
            let origin: NDKRelayOrigin = isFallback
                ? .appRelays
                : .outbox(authorPubkey: filter.authors?.first ?? "unknown")
            relay = await ndk.pool.addRelay(relayURL, origin: origin)
        }

        guard let relay = relay else {
            NDKLogger.log(.warning, category: .subscription,
                          "⚠️ Failed to add relay to pool: \(relayURL)")
            return
        }

        // Add subscription to relay using relay-level grouping
        await relay.addSubscription(internalSubscription, filters: [filter])

        // Update the InternalSubscriptionManager's relay mapping for subscription replay
        await ndk.internalSubscriptionManager.updateRelayAssociation(subscription: internalSubscription, relay: relayURL)

        // Track this relay subscription
        relaySubscriptions[relayURL] = RelaySubscription(relay: relay, filter: filter)

        // Track which authors this relay subscription covers
        if let authors = filter.authors {
            // Always track in the general coverage (for all relay purposes)
            relayAuthorCoverage[relayURL] = Set(authors)

            // Only track in author-specific coverage if NOT a fallback relay
            // Fallback relays should NOT count toward author coverage for relay selection
            if !isFallback {
                authorSpecificRelayCoverage[relayURL] = Set(authors)
                NDKLogger.log(.debug, category: .subscription,
                              "📊 Relay \(relayURL) now covers \(authors.count) authors (author-specific): \(authors.prefix(3).joined(separator: ", "))\(authors.count > 3 ? "..." : "")")
            } else {
                NDKLogger.log(.debug, category: .subscription,
                              "📍 Relay \(relayURL) is a FALLBACK for \(authors.count) authors (does NOT count toward coverage): \(authors.prefix(3).joined(separator: ", "))\(authors.count > 3 ? "..." : "")")
            }

            // Notify relay update observers about subscription activation
            let kinds = filter.kinds ?? []
            NDKLogger.log(.debug, category: .subscription,
                          "🔔 Yielding subscriptionActivated to \(relayUpdateObservers.count) observers for relay \(relayURL) with \(authors.count) authors")
            for (_, _, continuation) in relayUpdateObservers {
                continuation.yield(.subscriptionActivated(relay: relayURL, kinds: kinds, authorCount: authors.count))
            }
        }
    }

    /// Handle batch of events from cache
    /// Yields entire batch to observers for efficient UI updates
    private func handleCacheEvents(_ events: [NDKEvent]) async {
        // Filter out already-seen events
        let newEvents = events.filter { !seenEventIds.contains($0.id) }
        guard !newEvents.isEmpty else { return }

        // Mark all as seen
        for event in newEvents {
            seenEventIds.insert(event.id)
        }

        // Notify observers with filtered batch
        for (_, _, continuation, individualFilter) in observers {
            let matching = newEvents.filter { individualFilter.matches(event: $0) }
            if !matching.isEmpty {
                continuation.yield(matching)
            }
        }
    }

    /// Handle event from network
    /// Yields as single-element array for consistent batch semantics
    func handleNetworkEvent(_ event: NDKEvent, from relay: NDKRelay?) async {
        // Update EOSE tracker
        await eoseTracker.trackEventReceived()

        guard !seenEventIds.contains(event.id) else {
            NDKLogger.log(.trace, category: .subscription, "⏭️ Skipping duplicate event \(event.id.prefix(8)) kind:\(event.kind)")
            return
        }
        seenEventIds.insert(event.id)

        // Store in cache
        do {
            try await cache.saveEvent(event)
        } catch {
            NDKLogger.log(.warning, category: .cache, "Failed to save event \(event.id.prefix(8)) to cache: \(error.localizedDescription)")
        }

        // Record hint in HintIndex - learn where this author's events are found
        if let relay = relay, let ndk = ndk {
            await ndk.hintIndex.recordEventObservation(pubkey: event.pubkey, eventId: event.id, relay: relay.url)
        }

        // Notify relay update observers if we have relay info
        if let relay = relay {
            for (_, _, continuation) in relayUpdateObservers {
                continuation.yield(.event(event, relay: relay.url))
            }
        }

        // Notify observers with single-element batch
        for (_, _, continuation, individualFilter) in observers where individualFilter.matches(event: event) {
            continuation.yield([event])
        }
    }

    /// Handle EOSE from relay
    private func handleEOSE(from relay: NDKRelay) async {
        // First, notify relay update observers about individual EOSE
        for (_, _, continuation) in relayUpdateObservers {
            continuation.yield(.eose(relay: relay.url))
        }

        await eoseTracker.trackEOSE(from: relay.url)

        // Check if we should emit aggregated EOSE
        if await eoseTracker.shouldEmitEOSE(events: seenEventIds, filter: filter) {
            // Notify all relay update observers about aggregated EOSE
            for (_, _, continuation) in relayUpdateObservers {
                continuation.yield(.aggregatedEose)
            }

            // Close if configured to do so
            if closeOnEose {
                await cancel()
            }
        }
    }

    /// Get the observer count for this requirement
    func getObserverCount() -> Int {
        return observers.count
    }

    /// Get the active relays being used by this requirement
    func getActiveRelays() -> Set<RelayURL> {
        return Set(relaySubscriptions.keys)
    }

    /// Get relays that are serving specific authors
    /// IMPORTANT: Only returns author-specific relays, NOT fallback relays
    /// Fallback relays should NOT count toward author coverage for relay selection
    func getRelaysServingAuthors(_ authors: Set<String>) -> Set<RelayURL> {
        var servingRelays = Set<RelayURL>()

        // Use authorSpecificRelayCoverage, NOT relayAuthorCoverage
        // This ensures fallback relays are NOT counted as serving authors
        for (relay, coveredAuthors) in authorSpecificRelayCoverage {
            let intersection = authors.intersection(coveredAuthors)
            if !intersection.isEmpty {
                servingRelays.insert(relay)
            }
        }

        NDKLogger.log(.debug, category: .subscription,
                      "🎯 Found \(servingRelays.count) author-specific relays serving authors \(authors.prefix(3).joined(separator: ", ")): \(servingRelays)")

        return servingRelays
    }

    /// Handle newly discovered relays (for outbox model)
    func handleRelayDiscovery(authors: Set<String>, relays _: Set<RelayURL>) async {
        // Only relevant if we're using outbox strategy
        guard case let .outbox(strategy) = relayStrategy else { return }

        // Check if any discovered authors are in our unknown authors set
        let relevantAuthors = authors.intersection(strategy.unknownAuthors)
        guard !relevantAuthors.isEmpty else { return }

        NDKLogger.log(.info, category: .subscription,
                      "📡 Discovered relays for \(relevantAuthors.count) authors in requirement")

        // According to Outbox.md, we should NOT modify this requirement
        // Instead, the NDKSubscriptionManager will create new requirements
        // This method now just logs for debugging
    }

    /// Add an enhanced requirement handle
    func addEnhancedRequirement(_ handle: NDKSubscriptionRequirementHandle) {
        enhancedRequirements.append(handle)
    }

    /// Forward events from enhanced requirements to this requirement's observers
    /// This ensures events from discovered relays flow to the original subscription
    func forwardEventsFromEnhanced(_ events: [NDKEvent]) {
        // Deduplicate events we've already seen
        let newEvents = events.filter { !seenEventIds.contains($0.id) }
        guard !newEvents.isEmpty else { return }

        // Mark all as seen
        for event in newEvents {
            seenEventIds.insert(event.id)
        }

        NDKLogger.log(.debug, category: .subscription,
                      "📬 Forwarding \(newEvents.count) new events (from \(events.count) total) to \(observers.count) observers")

        // Notify observers with filtered batch
        for (_, _, continuation, individualFilter) in observers {
            let matching = newEvents.filter { individualFilter.matches(event: $0) }
            if !matching.isEmpty {
                continuation.yield(matching)
            }
        }
    }

    /// Monitor EOSE status and emit when appropriate
    private func monitorEOSE() async {
        for await shouldEmit in eoseTracker.eoseUpdates {
            if shouldEmit {
                // The shouldEmit flag from eoseTracker already reflects
                // the full decision (all relays EOSEd, query satisfied, or timeout)
                let filterDescription = filter.description
                let relayCount = relaySubscriptions.count
                let activeRelays = Array(relaySubscriptions.keys).sorted()

                NDKLogger.log(.info, category: .subscription,
                              "📊 Emitting aggregated EOSE for requirement | ID: '\(subscriptionId)' | Filter: \(filterDescription) | Active relays: \(relayCount) \(activeRelays)")

                // Notify all relay update observers about aggregated EOSE
                for (_, _, continuation) in relayUpdateObservers {
                    continuation.yield(.aggregatedEose)
                }

                if closeOnEose {
                    await cancel()
                }
                break
            }
        }
    }

    /// Cancel this requirement
    func cancel() async {
        // Cancel EOSE monitoring
        eoseTask?.cancel()

        // Cancel internal subscription
        await internalSubscription.close()

        // Cancel all enhanced requirements
        for handle in enhancedRequirements {
            await handle.cancel()
        }
        enhancedRequirements.removeAll()

        // Finish all observer streams
        for (_, _, continuation, _) in observers {
            continuation.finish()
        }
        observers.removeAll()

        // Finish all relay update observer streams
        for (_, _, continuation) in relayUpdateObservers {
            continuation.finish()
        }
        relayUpdateObservers.removeAll()
    }

    /// Activate relay subscriptions that were deferred due to offline mode
    /// This is called when connect() is called after subscriptions were created offline
    func activateRelayStrategy() async {
        // Only activate if we should fetch from network and haven't already created relay subscriptions
        guard shouldFetchFromNetwork, relaySubscriptions.isEmpty else {
            return
        }

        NDKLogger.log(.info, category: .subscription,
                      "▶️  Activating deferred relay strategy for '\(subscriptionId)'")

        // Apply the relay strategy now that we're connected
        await applyRelayStrategy()

        // Start the internal subscription if it hasn't been started yet
        await internalSubscription.start()
    }

    // MARK: - Test Introspection

    /// Get the expected relays from the EOSE tracker (for testing)
    func getExpectedRelaysForTesting() async -> Set<RelayURL> {
        await eoseTracker.getExpectedRelays()
    }

    /// Get the relays that have sent EOSE (for testing)
    func getEOSEsSeenForTesting() async -> Set<RelayURL> {
        await eoseTracker.getEOSEsSeen()
    }
}

// MARK: - Supporting Types

/// Tracks a subscription on a specific relay
private struct RelaySubscription {
    let relay: NDKRelay
    let filter: NDKFilter
}
