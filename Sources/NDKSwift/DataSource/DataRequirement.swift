import Foundation

/// Manages a single data requirement with proper filter splitting for outbox model
/// Focuses on event deduplication and relay management
actor DataRequirement {
    let filter: NDKFilter
    let subscriptionId: String
    let internalSubscription: InternalSubscription
    private let cache: any NDKCache
    private weak var ndk: NDK?
    private let closeOnEose: Bool
    let relayStrategy: InternalRelaySelectionStrategy
    private let shouldFetchFromNetwork: Bool
    
    // Event deduplication
    private var seenEventIds = Set<EventID>()
    
    // Observers
    private var observers: [(id: RequirementID, stream: AsyncStream<NDKEvent>, continuation: AsyncStream<NDKEvent>.Continuation, filter: NDKFilter)] = []
    
    // Active relay subscriptions (for outbox model)
    private var relaySubscriptions: [RelayURL: RelaySubscription] = [:]
    
    // Enhanced requirements created by NDKDataRequirementManager
    private var enhancedRequirements: [DataRequirementHandle] = []
    
    init(
        filter: NDKFilter,
        subscriptionId: String,
        internalSubscription: InternalSubscription,
        cache: any NDKCache,
        ndk: NDK,
        relays: Set<RelayURL>?,
        exclusiveRelays: Bool,
        closeOnEose: Bool,
        relayStrategy: InternalRelaySelectionStrategy,
        shouldFetchFromNetwork: Bool = true
    ) {
        self.filter = filter
        self.subscriptionId = subscriptionId
        self.internalSubscription = internalSubscription
        self.cache = cache
        self.ndk = ndk
        self.closeOnEose = closeOnEose
        self.relayStrategy = relayStrategy
        self.shouldFetchFromNetwork = shouldFetchFromNetwork
    }
    
    /// Add an observer for events matching this requirement
    func addObserver(id: RequirementID, individualFilter: NDKFilter) -> AsyncStream<NDKEvent> {
        let (stream, continuation) = AsyncStream<NDKEvent>.makeStream()
        observers.append((id: id, stream: stream, continuation: continuation, filter: individualFilter))
        return stream
    }
    
    /// Start processing events
    func startProcessing() async {
        // Set up cache observation using the new AsyncThrowingStream
        Task { [weak self] in
            guard let self = self else { return }
            
            let eventStream = await self.cache.observeEvents(
                matching: self.filter,
                includeExisting: true
            )
            
            do {
                for try await events in eventStream {
                    // Process each batch of events
                    for event in events {
                        await self.handleCacheEvent(event)
                    }
                }
            } catch {
                NDKLogger.log(.error, category: .subscription,
                             "❌ Cache observation error for '\(self.subscriptionId)': \(error)")
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
    }
    
    /// Apply the relay selection strategy
    private func applyRelayStrategy() async {
        switch relayStrategy {
        case .explicit(let relays):
            // Simple case: use explicit relays
            await createSubscriptions(for: filter, on: relays)
            
        case .outbox(let strategy):
            // Complex case: split filters by relay
            await applyOutboxStrategy(strategy)
            
        case .default(let relays):
            // Use default relays
            await createSubscriptions(for: filter, on: relays)
        }
    }
    
    /// Apply outbox strategy with filter splitting
    private func applyOutboxStrategy(_ strategy: OutboxFilterStrategy) async {
        // Create subscriptions for each relay with its specific filter
        for (relay, relayFilter) in strategy.filtersByRelay {
            await createSubscription(for: relayFilter, on: relay)
        }
        
        // If there are unknown authors, use fallback relays
        if !strategy.unknownAuthors.isEmpty {
            var fallbackFilter = filter
            fallbackFilter.authors = Array(strategy.unknownAuthors)
            
            // Get fallback relays
            if let pool = ndk?.pool {
                let fallbackRelays = await pool.connectedRelayURLs
                for relay in fallbackRelays {
                    await createSubscription(for: fallbackFilter, on: relay)
                }
            }
        }
    }
    
    /// Create subscriptions on specific relays
    private func createSubscriptions(for filter: NDKFilter, on relays: Set<RelayURL>) async {
        for relay in relays {
            await createSubscription(for: filter, on: relay)
        }
    }
    
    /// Create a subscription on a specific relay
    private func createSubscription(for filter: NDKFilter, on relayURL: RelayURL) async {
        guard let ndk = ndk else { return }
        
        // Get or create relay
        var relay = await ndk.pool.relay(for: relayURL)
        
        // If relay doesn't exist in pool, add and connect to it
        if relay == nil {
            NDKLogger.log(.info, category: .subscription,
                         "🔌 Relay not in pool, adding and connecting: \(relayURL)")
            // Try to determine origin from filter authors
            let originAuthor = filter.authors?.first ?? "unknown"
            relay = await ndk.pool.addRelayAndConnect(
                url: relayURL, 
                origin: .outbox(authorPubkey: originAuthor)
            )
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
    }
    
    /// Handle event from cache
    private func handleCacheEvent(_ event: NDKEvent) async {
        guard !seenEventIds.contains(event.id) else { return }
        seenEventIds.insert(event.id)
        
        // Notify observers whose filters match
        for (_, _, continuation, individualFilter) in observers {
            if individualFilter.matches(event: event) {
                continuation.yield(event)
            }
        }
    }
    
    /// Handle event from network
    func handleNetworkEvent(_ event: NDKEvent, from relay: NDKRelay?) async {
        guard !seenEventIds.contains(event.id) else { return }
        seenEventIds.insert(event.id)
        
        // Store in cache
        try? await cache.saveEvent(event)
        
        // Notify observers whose filters match
        for (_, _, continuation, individualFilter) in observers {
            if individualFilter.matches(event: event) {
                continuation.yield(event)
            }
        }
    }
    
    /// Handle EOSE from relay
    private func handleEOSE(from relay: NDKRelay) async {
        // Close if configured to do so
        if closeOnEose {
            await cancel()
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
    
    /// Handle newly discovered relays (for outbox model)
    func handleRelayDiscovery(authors: Set<String>, relays: Set<RelayURL>) async {
        // Only relevant if we're using outbox strategy
        guard case .outbox(let strategy) = relayStrategy else { return }
        
        // Check if any discovered authors are in our unknown authors set
        let relevantAuthors = authors.intersection(strategy.unknownAuthors)
        guard !relevantAuthors.isEmpty else { return }
        
        NDKLogger.log(.info, category: .subscription,
                     "📡 Discovered relays for \(relevantAuthors.count) authors in requirement")
        
        // According to Outbox.md, we should NOT modify this requirement
        // Instead, the NDKDataRequirementManager will create new requirements
        // This method now just logs for debugging
    }
    
    /// Add an enhanced requirement handle
    func addEnhancedRequirement(_ handle: DataRequirementHandle) {
        enhancedRequirements.append(handle)
    }
    
    /// Cancel this requirement
    func cancel() async {
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
    }
}

// MARK: - Supporting Types

/// Tracks a subscription on a specific relay
private struct RelaySubscription {
    let relay: NDKRelay
    let filter: NDKFilter
}

