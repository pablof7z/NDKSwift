import Foundation

/// Manages data requirements from multiple components
/// Handles temporal grouping, deduplication, and lifecycle management
actor NDKSubscriptionManager {
    private let ndk: NDK
    private let groupingWindow: TimeInterval = NetworkConstants.dataGroupingWindow

    // Active requirements tracked by ID
    private var activeRequirements: [RequirementID: NDKSubscriptionRequirement] = [:]

    // MARK: - Relay Discovery Batching
    // Batch relay discoveries to enable smart relay selection (overlap optimization)

    /// Pending discoveries waiting for debounce
    private var pendingDiscoveries: [String: (readRelays: Set<RelayURL>, writeRelays: Set<RelayURL>)] = [:]

    /// Debounce task for batched processing
    private var discoveryDebounceTask: Task<Void, Never>?

    /// Debounce window for relay discoveries (100ms)
    private let discoveryDebounceInterval: UInt64 = 100_000_000

    init(ndk: NDK) {
        self.ndk = ndk
        NDKLogger.log(.trace, category: .subscription, "🏗️ NDKSubscriptionManager initialized")

        // Listen for relay discoveries
        Task {
            await listenForRelayDiscoveries()
        }
    }

    /// Register a new data requirement
    /// - Parameters:
    ///   - filter: The filter defining what data is needed
    ///   - observer: The observer to notify when data arrives
    ///   - maxAge: Maximum age of cached data to consider fresh (0 = live subscription)
    ///   - cachePolicy: How to handle cache vs network
    ///   - relays: Optional set of specific relay URLs to query
    ///   - subscriptionId: Optional custom subscription ID (for debugging/tracing)
    /// - Returns: Handle for managing the requirement lifecycle and event/relay update streams
    func registerRequirement(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool? = nil,
        isGroupable: Bool = true,
        groupableDelay: TimeInterval? = nil,
        groupableDelayType: NDKSubscriptionDelayType? = nil
    ) async -> (handle: NDKSubscriptionRequirementHandle, events: AsyncStream<[NDKEvent]>, relayUpdates: AsyncStream<RelayUpdate>) {
        let requirementId = RequirementID()
        let correlationId = requirementId.uuidString.prefix(8)

        NDKLogger.log(.info, category: .subscription, "📥 [DataReqManager] registerRequirement - filter: \(filter), maxAge: \(maxAge), policy: \(cachePolicy), subscriptionId: \(subscriptionId ?? "auto")", correlationId: String(correlationId))

        // Note: NDKSubscriptionRequirement will set up its own cache observation
        // This ensures proper lifecycle management

        // For cache-only policy, we still create a NDKSubscriptionRequirement
        // This allows cache-only subscriptions to participate in the reactive system
        // and receive events from network subscriptions with the same fingerprint

        // Determine if this group needs a live subscription
        let shouldCloseOnEose = closeOnEose ?? (maxAge > 0)

        // Check if we should fetch from network
        var shouldFetchFromNetwork = true

        // Cache-only policy never fetches from network
        if cachePolicy == .cacheOnly {
            shouldFetchFromNetwork = false
        }
        // Check cache freshness if maxAge > 0 and cachePolicy allows it
        else if maxAge > 0, cachePolicy == .cacheWithNetwork {
            // Check if we have fresh data in cache
            if let lastFetchTime = await ndk.cache.getLastFetchTime(for: filter) {
                let age = Date().timeIntervalSince(lastFetchTime)
                if age <= maxAge {
                    NDKLogger.log(.info, category: .subscription, "✅ Cache is fresh (age: \(Int(age))s, maxAge: \(Int(maxAge))s) - skipping network fetch")
                    shouldFetchFromNetwork = false
                }
            }
        }

        // Always create the data requirement, even for cache-only
        // This ensures all subscriptions participate in the reactive system

        // Create the data requirement and get the streams
        let (requirement, eventStream, relayUpdateStream) = await createRequirement(
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            exclusiveRelays: exclusiveRelays,
            subscriptionId: subscriptionId,
            closeOnEose: shouldCloseOnEose,
            requirementId: requirementId,
            shouldFetchFromNetwork: shouldFetchFromNetwork,
            isGroupable: isGroupable,
            groupableDelay: groupableDelay,
            groupableDelayType: groupableDelayType
        )

        // Store active requirement if it's not close-on-EOSE
        if !shouldCloseOnEose {
            activeRequirements[requirementId] = requirement
        }

        // Start processing asynchronously - don't block the return
        // This allows relay update forwarding to start immediately while subscriptions are being created
        Task {
            await requirement.startProcessing()
        }

        return (
            handle: NDKSubscriptionRequirementHandle(
                id: requirementId,
                manager: self,
                requirement: requirement
            ),
            events: eventStream,
            relayUpdates: relayUpdateStream
        )
    }

    /// Create a data requirement with proper filter splitting for outbox model
    private func createRequirement(
        filter: NDKFilter,
        maxAge _: TimeInterval,
        cachePolicy: CachePolicy,
        relays: Set<RelayURL>?,
        exclusiveRelays: Bool,
        subscriptionId: String?,
        closeOnEose: Bool,
        requirementId: RequirementID,
        shouldFetchFromNetwork: Bool,
        isGroupable: Bool,
        groupableDelay: TimeInterval?,
        groupableDelayType: NDKSubscriptionDelayType?
    ) async -> (NDKSubscriptionRequirement, AsyncStream<[NDKEvent]>, AsyncStream<RelayUpdate>) {
        // Optimize filter for cache - remove event IDs we already have
        let optimizedFilter = await optimizeFilterForCache(filter) ?? filter

        // Determine relay selection strategy
        let relayStrategy = await determineRelayStrategy(
            filter: optimizedFilter,
            explicitRelays: relays,
            exclusiveRelays: exclusiveRelays
        )

        // Create internal subscription
        let subId = subscriptionId ?? generateSubscriptionId(for: optimizedFilter)
        let fingerprint = [optimizedFilter].toFingerprint(closeOnEose: closeOnEose)

        NDKLogger.log(.debug, category: .subscription,
                      "🆕 [DataReqManager] Creating internal subscription with ID '\(subId)' and fingerprint '\(fingerprint)'")
        let internalSubscription = await ndk.internalSubscriptionManager.createSubscription(
            id: subId,
            filters: [optimizedFilter],
            relays: nil, // Will be set by NDKSubscriptionRequirement based on strategy
            fingerprint: fingerprint,
            closeOnEose: closeOnEose,
            autoStart: false,
            isGroupable: isGroupable,
            groupableDelay: groupableDelay,
            groupableDelayType: groupableDelayType
        )

        // Create data requirement
        let requirement = NDKSubscriptionRequirement(
            filter: optimizedFilter,
            subscriptionId: internalSubscription.id,
            internalSubscription: internalSubscription,
            cache: ndk.cache,
            ndk: ndk,
            relays: relays,
            exclusiveRelays: exclusiveRelays,
            closeOnEose: closeOnEose,
            relayStrategy: relayStrategy,
            shouldFetchFromNetwork: shouldFetchFromNetwork,
            cachePolicy: cachePolicy
        )

        // Add observer and get the event stream
        let eventStream = await requirement.addObserver(id: requirementId, individualFilter: filter)
        let relayUpdateStream = await requirement.addRelayUpdateObserver(id: requirementId)

        // Record fetch time
        await ndk.cache.recordFetchTime(for: optimizedFilter, timestamp: Date())

        return (requirement, eventStream, relayUpdateStream)
    }

    /// Determine relay selection strategy based on filter and configuration
    private func determineRelayStrategy(
        filter: NDKFilter,
        explicitRelays: Set<RelayURL>?,
        exclusiveRelays _: Bool
    ) async -> InternalRelaySelectionStrategy {
        // If explicit relays are provided, use them
        if let relays = explicitRelays {
            return .explicit(relays: relays)
        }

        // If outbox is enabled and filter has authors, use outbox strategy
        if ndk.outboxEnabled, let authors = filter.authors, !authors.isEmpty {
            let outboxStrategy = await ndk.outbox.getOutboxStrategy(for: filter)

            // Start background discovery if needed
            if !outboxStrategy.authorsToDiscover.isEmpty {
                NDKLogger.log(.info, category: .subscription, "🔍 Triggering background relay discovery for \(outboxStrategy.authorsToDiscover.count) authors")
                Task {
                    await ndk.outbox.discoverRelaysInBackground(for: outboxStrategy.authorsToDiscover)
                }
            }

            return .outbox(strategy: outboxStrategy)
        }

        // Otherwise use the app's configured relays
        let appRelays = await ndk.pool.appRelays
        let appRelayURLs = Set(appRelays.map { $0.url })

        if appRelayURLs.isEmpty {
            NDKLogger.log(.warning, category: .subscription,
                          "⚠️ No relays specified and no app relays configured in the pool. Add relays to the pool before creating subscriptions.")
        } else {
            NDKLogger.log(.debug, category: .subscription,
                          "📡 Using \(appRelayURLs.count) app relays for subscription")
        }

        return .default(relays: appRelayURLs)
    }

    /// Generate a subscription ID for a filter
    private func generateSubscriptionId(for filter: NDKFilter) -> String {
        var parts: [String] = []

        // Add kind info (abbreviated)
        if let kinds = filter.kinds {
            let kindStr = kinds.count == 1 ? "k\(kinds[0])" : "k\(kinds.count)"
            parts.append(kindStr)
        }

        // Add author info (abbreviated)
        if let authors = filter.authors {
            let authorStr = authors.count == 1 ? String(authors[0].prefix(4)) : "a\(authors.count)"
            parts.append(authorStr)
        }

        // Add tag info
        if let tags = filter.tags, !tags.isEmpty {
            parts.append("t\(tags.count)")
        }

        // Add random component
        parts.append(String(UUID().uuidString.prefix(4)))

        return parts.joined(separator: "_")
    }

    /// Cancel a requirement
    func cancelRequirement(id: RequirementID) async {
        activeRequirements.removeValue(forKey: id)
    }

    /// Optimize filter by removing already-cached event IDs
    private func optimizeFilterForCache(_ filter: NDKFilter) async -> NDKFilter? {
        // If filter requests specific event IDs, check if we already have them
        guard let requestedIds = filter.ids, !requestedIds.isEmpty else {
            return filter
        }

        let cachedIdsDict = await ndk.cache.hasEvents(ids: requestedIds)
        let cachedIds = Set(cachedIdsDict.compactMap { $0.value ? $0.key : nil })
        let missingIds = requestedIds.filter { !cachedIds.contains($0) }

        if missingIds.isEmpty {
            // All requested events are already cached
            return nil
        }

        if missingIds.count == requestedIds.count {
            // None are cached, return original filter
            return filter
        }

        // Some are cached, create filter for only missing ones
        var optimizedFilter = filter
        optimizedFilter.ids = missingIds
        return optimizedFilter
    }

    /// Listen for relay discoveries and update active requirements
    /// Batches discoveries with 100ms debounce to enable smart relay selection
    private func listenForRelayDiscoveries() async {
        NDKLogger.log(.info, category: .subscription, "🎧 Started listening for relay discoveries")
        for await discovery in ndk.outbox.relayDiscoveries {
            // Accumulate discovery
            pendingDiscoveries[discovery.pubkey] = (
                readRelays: discovery.readRelays,
                writeRelays: discovery.writeRelays
            )

            NDKLogger.log(.debug, category: .subscription,
                          "📋 Accumulated discovery for \(discovery.pubkey.prefix(8))... (\(pendingDiscoveries.count) pending)")

            // Cancel existing debounce and start new one
            discoveryDebounceTask?.cancel()
            discoveryDebounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: self?.discoveryDebounceInterval ?? 100_000_000)
                guard !Task.isCancelled else { return }
                await self?.processBatchedDiscoveries()
            }
        }
        NDKLogger.log(.warning, category: .subscription, "⚠️ Relay discovery stream ended")
    }

    /// Process all accumulated relay discoveries as a batch
    private func processBatchedDiscoveries() async {
        guard !pendingDiscoveries.isEmpty else { return }

        // Collect all authors and relays from pending discoveries
        let authors = Set(pendingDiscoveries.keys)
        let allRelays = Set(pendingDiscoveries.values.flatMap { $0.readRelays.union($0.writeRelays) })

        NDKLogger.log(.info, category: .subscription,
                      "📡 Processing batched relay discoveries: \(authors.count) authors, \(allRelays.count) relays")

        // Clear pending before processing (so new discoveries during processing start a new batch)
        pendingDiscoveries.removeAll()

        // Process the batch
        await handleRelayDiscovery(authors: authors, relays: allRelays)
    }

    /// Handle newly discovered relays for authors
    private func handleRelayDiscovery(authors: Set<String>, relays: Set<RelayURL>) async {
        NDKLogger.log(.info, category: .subscription, "📡 Relay discovery: \(relays.count) relays for \(authors.count) authors")
        NDKLogger.log(.debug, category: .subscription, "   Active requirements: \(activeRequirements.count)")

        // According to Outbox.md: Create NEW NDKSubscriptionRequirements for discovered relays
        // and attach them to the same observers as the original subscription

        // Create relay selection strategy
        let relaySelector = OverlapOptimizedRelaySelector(tracker: ndk.outbox)

        // Find requirements that need enhancement with these relays
        for (requirementId, requirement) in activeRequirements {
            // Get the relay strategy to check if this requirement has unknown authors
            let filter = requirement.filter
            let relayStrategy = requirement.relayStrategy
            guard case let .outbox(strategy) = relayStrategy else {
                NDKLogger.log(.trace, category: .subscription, "   Requirement not using outbox strategy, skipping")
                continue
            }

            // Check if any discovered authors are in this requirement's unknown authors
            let relevantAuthors = authors.intersection(strategy.unknownAuthors)
            guard !relevantAuthors.isEmpty else {
                NDKLogger.log(.trace, category: .subscription, "   No relevant authors (discovered authors not in unknown set)")
                continue
            }

            NDKLogger.log(.info, category: .subscription,
                          "🎯 Evaluating enhanced requirements for \(relevantAuthors.count) authors")

            // Check if the requirement has observers
            let observerCount = await requirement.getObserverCount()
            guard observerCount > 0 else {
                NDKLogger.log(.warning, category: .subscription, "   Req has no observers, skipping enhancement")
                continue
            }

            // Get relays that are already serving these specific authors
            let existingRelays = await requirement.getRelaysServingAuthors(relevantAuthors)
            let connectedRelays = await ndk.pool.connectedRelayURLs

            NDKLogger.log(.debug, category: .subscription,
                          "📊 Requirement status - existing relays: \(existingRelays), connected pool relays: \(connectedRelays.count)")

            // Use relay selector to choose which relays to connect to
            let selectedRelays = await relaySelector.selectRelaysToConnect(
                discoveredRelays: relays,
                for: relevantAuthors,
                existingRelays: existingRelays,
                connectedRelays: connectedRelays,
                maxRelays: OutboxConstants.relaysPerAuthorForFetching
            )

            guard !selectedRelays.isEmpty else {
                NDKLogger.log(.debug, category: .subscription,
                              "📊 No additional relays needed for requirement \(requirementId)")
                continue
            }

            NDKLogger.log(.info, category: .subscription,
                          "🎯 Selected \(selectedRelays.count) relays for enhancement: \(selectedRelays)")

            // Connect to selected relays that aren't already connected
            for relayURL in selectedRelays {
                if await ndk.pool.getRelay(for: relayURL) == nil {
                    let originAuthor = relevantAuthors.first ?? "unknown"
                    let kindsStr = filter.kinds?.map { "\($0)" }.joined(separator: ",") ?? "all"
                    let reason = "discovered relay for \(relevantAuthors.count) authors, requirement '\(requirement.subscriptionId)' kinds [\(kindsStr)]"

                    NDKLogger.log(.info, category: .subscription,
                                  "🔌 Adding discovered relay: \(relayURL) | \(reason)")

                    // Use ndk.addRelay instead of pool.addRelay to ensure auto-connect happens
                    await ndk.addRelay(relayURL, origin: .outbox(authorPubkey: originAuthor), reason: reason)
                }
            }

            // Create a new filter for just the relevant authors
            var enhancedFilter = filter
            enhancedFilter.authors = Array(relevantAuthors)

            // Create new requirements for each selected relay with the enhanced filter
            for relayURL in selectedRelays {
                // Create a unique subscription ID for this enhancement
                let relaySuffix = relayURL.replacingOccurrences(of: "wss://", with: "")
                    .replacingOccurrences(of: "ws://", with: "")
                    .replacingOccurrences(of: "/", with: "_")
                    .prefix(12)
                let enhancedSubscriptionId = "\(requirement.subscriptionId)_enhanced_\(relaySuffix)"

                // Create enhanced requirement for this specific relay
                // This follows the outbox model: create a new requirement for discovered relays
                let enhancedRequirementId = UUID()
                let (enhancedRequirement, enhancedEventStream, _) = await createRequirement(
                    filter: enhancedFilter,
                    maxAge: 0, // Enhanced requirements are live subscriptions
                    cachePolicy: .networkOnly, // Fetch fresh data from discovered relays
                    relays: Set([relayURL]),
                    exclusiveRelays: true, // Use only this specific relay
                    subscriptionId: enhancedSubscriptionId,
                    closeOnEose: false, // Keep live subscription open
                    requirementId: enhancedRequirementId,
                    shouldFetchFromNetwork: true, // Always fetch from discovered relays
                    isGroupable: true,
                    groupableDelay: nil,
                    groupableDelayType: nil
                )

                // Create handle for the enhanced requirement
                let enhancedHandle = NDKSubscriptionRequirementHandle(
                    id: enhancedRequirementId,
                    manager: self,
                    requirement: enhancedRequirement
                )

                // Track the enhanced requirement
                await requirement.addEnhancedRequirement(enhancedHandle)

                // Store in active requirements
                activeRequirements[enhancedRequirementId] = enhancedRequirement

                NDKLogger.log(.info, category: .subscription,
                              "✅ Created enhanced requirement '\(enhancedSubscriptionId)' for relay \(relayURL)")

                // Start processing the enhanced requirement
                Task {
                    await enhancedRequirement.startProcessing()
                }

                // Forward events from enhanced requirement to original requirement's observers
                // This ensures events from discovered relays flow to the original subscription
                Task {
                    for await batch in enhancedEventStream {
                        if !batch.isEmpty {
                            NDKLogger.log(.debug, category: .subscription,
                                          "📬 Forwarding \(batch.count) events from enhanced requirement '\(enhancedSubscriptionId)' to original")
                            await requirement.forwardEventsFromEnhanced(batch)
                        }
                    }
                }
            }
        }
    }

    /// Activate all deferred subscriptions after connect() is called
    /// This is called when NDK transitions from offline to online mode
    func activateDeferredSubscriptions() async {
        NDKLogger.log(.info, category: .subscription,
                      "🔄 Activating deferred subscriptions for \(activeRequirements.count) active requirements")

        for (_, requirement) in activeRequirements {
            await requirement.activateRelayStrategy()
        }
    }
}

// MARK: - Requirement Handle

/// Actor to store weak references thread-safely
private actor HandleStateActor {
    weak var manager: NDKSubscriptionManager?
    weak var requirement: NDKSubscriptionRequirement?

    init(manager: NDKSubscriptionManager?, requirement: NDKSubscriptionRequirement?) {
        self.manager = manager
        self.requirement = requirement
    }

    func getManager() -> NDKSubscriptionManager? { manager }
    func getRequirement() -> NDKSubscriptionRequirement? { requirement }
}

/// Handle for managing a data requirement lifecycle
public final class NDKSubscriptionRequirementHandle: Sendable {
    let id: RequirementID
    private let state: HandleStateActor

    init(id: RequirementID, manager: NDKSubscriptionManager?, requirement: NDKSubscriptionRequirement? = nil) {
        self.id = id
        state = HandleStateActor(manager: manager, requirement: requirement)
    }

    /// Cancel this requirement
    public func cancel() async {
        if let manager = await state.getManager() {
            await manager.cancelRequirement(id: id)
        }
        if let requirement = await state.getRequirement() {
            await requirement.cancel()
        }
    }
}

// MARK: - Supporting Types

typealias RequirementID = UUID

/// Relay selection strategy for internal use
enum InternalRelaySelectionStrategy {
    case explicit(relays: Set<RelayURL>)
    case outbox(strategy: OutboxFilterStrategy)
    case `default`(relays: Set<RelayURL>)
}
