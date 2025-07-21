import Foundation

/// Manages data requirements from multiple components
/// Handles temporal grouping, deduplication, and lifecycle management
actor NDKDataRequirementManager {
    private let ndk: NDK
    private let groupingWindow: TimeInterval = 0.1 // 100ms
    
    // Active requirements tracked by ID
    private var activeRequirements: [RequirementID: DataRequirement] = [:]
    
    // Pending requirements waiting to be grouped
    private var pendingRequirements: [FilterSignature: [PendingRequirement]] = [:]
    
    // Timer tasks for flushing pending requirements
    private var flushTasks: [FilterSignature: Task<Void, Never>] = [:]
    
    init(ndk: NDK) {
        self.ndk = ndk
        NDKLogger.log(.debug, category: .subscription, "🏗️ NDKDataRequirementManager initialized")
    }
    
    /// Register a new data requirement
    /// - Parameters:
    ///   - filter: The filter defining what data is needed
    ///   - observer: The observer to notify when data arrives
    ///   - maxAge: Maximum age of cached data to consider fresh (0 = live subscription)
    ///   - cachePolicy: How to handle cache vs network
    ///   - relays: Optional set of specific relay URLs to query
    ///   - subscriptionId: Optional custom subscription ID (for debugging/tracing)
    /// - Returns: Handle for managing the requirement lifecycle
    func registerRequirement(
        filter: NDKFilter,
        observer: CacheObserver,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        subscriptionId: String? = nil
    ) async -> DataRequirementHandle {
        let requirementId = RequirementID()
        let correlationId = requirementId.uuidString.prefix(8)
        // Handle cache-only policy
        if cachePolicy == .cacheOnly {
            NDKLogger.log(.debug, category: .subscription, "📦 Cache-only policy - no network subscription", correlationId: String(correlationId))
            // The cache observer will deliver existing events
            // Just return a dummy handle since no subscription is needed
            return DataRequirementHandle(id: requirementId, manager: nil)
        }
        
        // For networkOnly or when cache is stale/empty, proceed with network request
        let signature = FilterSignature(from: filter)
        
        // Check if we can reuse an existing requirement (only for live subscriptions)
        if maxAge == 0, let existing = findMatchingRequirement(for: filter) {
            NDKLogger.log(.info, category: .subscription, "♻️ Reusing existing requirement for filter", correlationId: String(correlationId))
            await existing.addObserver(observer, id: requirementId, individualFilter: filter)
            return DataRequirementHandle(
                id: requirementId,
                manager: self
            )
        }
        
        // Create pending requirement with metadata
        let pending = PendingRequirement(
            id: requirementId,
            filter: filter,
            observer: observer,
            registeredAt: Date(),
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            subscriptionId: subscriptionId
        )
        
        // Add to pending queue
        pendingRequirements[signature, default: []].append(pending)
        let pendingCount = pendingRequirements[signature]?.count ?? 0
        NDKLogger.log(.debug, category: .subscription, "⏳ Added to pending queue - signature: \(signature), pending count: \(pendingCount)", correlationId: String(correlationId))
        
        // Start or extend grouping timer
        if flushTasks[signature] == nil {
            NDKLogger.log(.debug, category: .subscription, "⏲️ Starting grouping timer (\(groupingWindow * 1000)ms)", correlationId: String(correlationId))
            flushTasks[signature] = Task {
                try? await Task.sleep(nanoseconds: UInt64(groupingWindow * 1_000_000_000))
                await flushPendingRequirements(for: signature)
            }
        } else {
            NDKLogger.log(.trace, category: .subscription, "⏲️ Grouping timer already running", correlationId: String(correlationId))
        }
        
        return DataRequirementHandle(
            id: requirementId,
            manager: self
        )
    }
    
    /// Release a data requirement
    func releaseRequirement(id: RequirementID) async {
        let correlationId = id.uuidString.prefix(8)
        NDKLogger.log(.debug, category: .subscription, "🔓 Releasing requirement", correlationId: String(correlationId))
        
        guard let requirement = activeRequirements[id] else {
            NDKLogger.log(.trace, category: .subscription, "⚠️ Requirement not found in active list", correlationId: String(correlationId))
            return
        }
        
        await requirement.removeObserver(id: id)
        
        // If no more observers, close the subscription
        if requirement.observerCount == 0 {
            NDKLogger.log(.info, category: .subscription, "🛑 No more observers - closing subscription: \(requirement.subscriptionId)", correlationId: String(correlationId))
            await requirement.internalSubscription.close()
            activeRequirements.removeValue(forKey: id)
        } else {
            NDKLogger.log(.debug, category: .subscription, "👥 Still \(requirement.observerCount) observers remaining", correlationId: String(correlationId))
        }
    }
    
    // MARK: - Private Methods
    
    private func findMatchingRequirement(for filter: NDKFilter) -> DataRequirement? {
        // Look for exact match or superset that includes this filter
        for (_, requirement) in activeRequirements {
            if requirement.includesFilter(filter) {
                return requirement
            }
        }
        return nil
    }
    
    private func flushPendingRequirements(for signature: FilterSignature) async {
        NDKLogger.log(.debug, category: .subscription, "🚀 Flushing pending requirements for signature: \(signature)")
        flushTasks.removeValue(forKey: signature)
        
        guard let pending = pendingRequirements.removeValue(forKey: signature),
              !pending.isEmpty else {
            NDKLogger.log(.trace, category: .subscription, "No pending requirements to flush")
            return
        }
        
        NDKLogger.log(.info, category: .subscription, "📦 Processing \(pending.count) pending requirements")
        
        // Group by maxAge and cachePolicy to handle lifecycle correctly
        let groupedByLifecycle = Dictionary(grouping: pending) { p in
            "\(p.maxAge)-\(p.cachePolicy)"
        }
        
        for (_, lifecycleGroup) in groupedByLifecycle {
            // Group filters and create aggregated filters (may be multiple)
            let filters = lifecycleGroup.map { $0.filter }
            let aggregatedFilters = aggregateFilters(filters)
            
            // Determine if this group needs a live subscription
            let maxAge = lifecycleGroup.first?.maxAge ?? 0
            let closeOnEose = maxAge > 0
            
            // Create a subscription for each aggregated filter
            for aggregatedFilter in aggregatedFilters {
                // Use specified relays if provided, otherwise use outbox if enabled
                var relays: Set<RelayURL>? = lifecycleGroup.first?.relays
                if relays == nil && ndk.outboxEnabled {
                    print("🔍 [DataRequirementManager] No relays specified and outbox enabled, fetching recommended relays...")
                    relays = await ndk.outbox.getRecommendedRelaysForSubscription(filters: [aggregatedFilter])
                    print("🔍 [DataRequirementManager] Got \(relays?.count ?? 0) recommended relays")
                    
                    // Add and connect to any new relays
                    if let recommendedRelays = relays, !recommendedRelays.isEmpty {
                        print("🔍 [DataRequirementManager] Ensuring recommended relays are connected...")
                        for relayUrl in recommendedRelays {
                            // This will add the relay if not already in the pool
                            await ndk.addRelayAndConnect(relayUrl)
                        }
                        print("🔍 [DataRequirementManager] All recommended relays added to pool")
                    }
                    
                    // If outbox returned empty set, fall back to all connected relays
                    if relays?.isEmpty ?? true {
                        print("🔍 [DataRequirementManager] Outbox returned empty relay set, falling back to all connected relays")
                        relays = nil // This will cause the subscription to use all connected relays
                    }
                }
                
                // Create subscription using internal manager
                // Use custom subscription ID if provided, otherwise generate one
                let subscriptionId = lifecycleGroup.compactMap { $0.subscriptionId }.first ?? "ds_\(IDGenerator.randomId(length: 8))"
                NDKLogger.log(.info, category: .subscription, "🎯 Creating subscription - id: \(subscriptionId), filter: \(aggregatedFilter.fingerprint), relays: \(relays?.map { $0 } ?? ["all"])")
                let internalSubscription = await ndk.internalSubscriptionManager.createSubscription(
                    id: subscriptionId,
                    filters: [aggregatedFilter],
                    relays: relays
                )
                
                // Create data requirement
                let requirement = DataRequirement(
                    filter: aggregatedFilter,
                    subscriptionId: internalSubscription.id,
                    internalSubscription: internalSubscription,
                    cache: ndk.cache,
                    ndk: ndk,
                    closeOnEose: closeOnEose
                )
                
                // Add relevant observers to this requirement
                var addedObservers = 0
                NDKLogger.log(.debug, category: .subscription, "🔍 Checking \(lifecycleGroup.count) pending requirements for coverage")
                for p in lifecycleGroup {
                    // Only add observer if this aggregated filter covers their individual filter
                    let covers = requirement.includesFilter(p.filter)
                    NDKLogger.log(.debug, category: .subscription, "🔍 Filter coverage check - aggregated: \(aggregatedFilter.fingerprint), individual: \(p.filter.fingerprint), covers: \(covers)")
                    
                    if covers {
                        await requirement.addObserver(p.observer, id: p.id, individualFilter: p.filter)
                        addedObservers += 1
                        if !closeOnEose {
                            // Only track in activeRequirements if it's a live subscription
                            activeRequirements[p.id] = requirement
                        }
                    } else {
                        NDKLogger.log(.warning, category: .subscription, "⚠️ Aggregated filter doesn't cover individual filter - this shouldn't happen!")
                    }
                }
                NDKLogger.log(.debug, category: .subscription, "👥 Added \(addedObservers) observers to requirement")
                
                // Start processing events
                Task {
                    NDKLogger.log(.debug, category: .subscription, "▶️ Starting event processing for subscription: \(subscriptionId)")
                    await requirement.startProcessing()
                    
                    // Record fetch time after processing starts
                    await ndk.cache.recordFetchTime(for: aggregatedFilter, timestamp: Date())
                    NDKLogger.log(.trace, category: .subscription, "🕰️ Recorded fetch time for filter")
                }
            }
        }
    }
    
    /// Smart filter aggregation that returns multiple filters when needed
    private func aggregateFilters(_ filters: [NDKFilter]) -> [NDKFilter] {
        NDKLogger.log(.debug, category: .subscription, "🧮 Aggregating \(filters.count) filters")
        
        // Group filters by compatibility
        let filterGroups = groupCompatibleFilters(filters)
        NDKLogger.log(.debug, category: .subscription, "📦 Grouped into \(filterGroups.count) compatible groups")
        
        // Aggregate each group separately
        let aggregated = filterGroups.map { group in
            aggregateSingleGroup(group)
        }
        
        for (index, filter) in aggregated.enumerated() {
            NDKLogger.log(.trace, category: .subscription, "Group \(index + 1): \(filter.fingerprint)")
        }
        
        return aggregated
    }
    
    /// Group filters that can be efficiently combined
    private func groupCompatibleFilters(_ filters: [NDKFilter]) -> [[NDKFilter]] {
        var groups: [[NDKFilter]] = []
        
        for filter in filters {
            var addedToGroup = false
            
            // Try to add to existing group
            for i in 0..<groups.count {
                if canCombineFilters(groups[i][0], filter) {
                    groups[i].append(filter)
                    addedToGroup = true
                    break
                }
            }
            
            // Create new group if couldn't add to existing
            if !addedToGroup {
                groups.append([filter])
            }
        }
        
        return groups
    }
    
    /// Check if two filters can be efficiently combined
    private func canCombineFilters(_ filter1: NDKFilter, _ filter2: NDKFilter) -> Bool {
        // Filters are compatible if they have:
        // 1. Overlapping kinds OR one has no kind restrictions
        // 2. Overlapping authors OR one has no author restrictions
        // 3. Compatible tag filters
        
        // Check kinds compatibility
        if let kinds1 = filter1.kinds, let kinds2 = filter2.kinds {
            // Both have kinds - must have overlap
            if Set(kinds1).isDisjoint(with: Set(kinds2)) {
                return false // No overlap in kinds
            }
        }
        
        // Check authors compatibility
        if let authors1 = filter1.authors, let authors2 = filter2.authors {
            // Both have authors - must have overlap
            if Set(authors1).isDisjoint(with: Set(authors2)) {
                return false // No overlap in authors
            }
        }
        
        // Check if they have conflicting tag requirements
        if let tags1 = filter1.tags, let tags2 = filter2.tags {
            for (key, values1) in tags1 {
                if let values2 = tags2[key] {
                    // Both filters have requirements for this tag
                    if Set(values1).isDisjoint(with: Set(values2)) {
                        return false // No overlap in tag values
                    }
                }
            }
        }
        
        // Filters are compatible
        return true
    }
    
    /// Aggregate a group of compatible filters into a single filter
    private func aggregateSingleGroup(_ filters: [NDKFilter]) -> NDKFilter {
        var aggregated = NDKFilter()
        
        // Aggregate kinds
        var allKinds = Set<Int>()
        for filter in filters {
            if let kinds = filter.kinds {
                allKinds.formUnion(kinds)
            }
        }
        if !allKinds.isEmpty {
            aggregated.kinds = Array(allKinds)
        }
        
        // Aggregate authors
        var allAuthors = Set<String>()
        for filter in filters {
            if let authors = filter.authors {
                allAuthors.formUnion(authors)
            }
        }
        if !allAuthors.isEmpty {
            aggregated.authors = Array(allAuthors)
        }
        
        // Aggregate event IDs
        var allEventIds = Set<String>()
        for filter in filters {
            if let ids = filter.ids {
                allEventIds.formUnion(ids)
            }
        }
        if !allEventIds.isEmpty {
            aggregated.ids = Array(allEventIds)
        }
        
        // Aggregate tags
        var tagsByKey: [String: Set<String>] = [:]
        for filter in filters {
            if let tags = filter.tags {
                for (key, values) in tags {
                    tagsByKey[key, default: []].formUnion(values)
                }
            }
        }
        
        // Convert back to tag arrays
        for (key, values) in tagsByKey {
            // Remove the # prefix if present
            let tagName = key.hasPrefix("#") ? String(key.dropFirst()) : key
            aggregated.addTagFilter(tagName, values: Array(values))
        }
        
        // Aggregate time ranges (use widest range)
        aggregated.since = filters.compactMap { $0.since }.min()
        aggregated.until = filters.compactMap { $0.until }.max()
        
        // Aggregate limit (use max to ensure we get enough events)
        if let maxLimit = filters.compactMap({ $0.limit }).max() {
            aggregated.limit = maxLimit
        }
        
        return aggregated
    }
}

// MARK: - Supporting Types

typealias RequirementID = UUID

struct PendingRequirement {
    let id: RequirementID
    let filter: NDKFilter
    let observer: CacheObserver
    let registeredAt: Date
    let maxAge: TimeInterval
    let cachePolicy: CachePolicy
    let relays: Set<RelayURL>?
    let subscriptionId: String?
}

/// Manages a single data requirement - events flow ONLY through cache
class DataRequirement {
    let filter: NDKFilter
    let subscriptionId: String
    let internalSubscription: InternalSubscription
    private let cache: NDKCache?
    private weak var ndk: NDK?
    private let closeOnEose: Bool
    private var observerHandles: [RequirementID: ObservationHandle] = [:]
    
    var observerCount: Int { observerHandles.count }
    
    init(filter: NDKFilter, subscriptionId: String, internalSubscription: InternalSubscription, cache: NDKCache?, ndk: NDK, closeOnEose: Bool = false) {
        self.filter = filter
        self.subscriptionId = subscriptionId
        self.internalSubscription = internalSubscription
        self.cache = cache
        self.ndk = ndk
        self.closeOnEose = closeOnEose
    }
    
    func addObserver(_ observer: CacheObserver, id: RequirementID, individualFilter: NDKFilter) async {
        let correlationId = id.uuidString.prefix(8)
        NDKLogger.log(.debug, category: .subscription, "👁️ Adding observer to DataRequirement - filter: \(individualFilter.fingerprint)", correlationId: String(correlationId))
        
        // Register observer with cache - cache is the single source of truth
        if let cache = cache {
            let handle = await cache.observeEvents(
                matching: individualFilter,
                observer: observer
            )
            observerHandles[id] = handle
            NDKLogger.log(.trace, category: .subscription, "✅ Observer registered with cache", correlationId: String(correlationId))
        } else {
            NDKLogger.log(.error, category: .subscription, "❌ No cache available - observer not registered!", correlationId: String(correlationId))
        }
    }
    
    func removeObserver(id: RequirementID) async {
        if let handle = observerHandles.removeValue(forKey: id) {
            await handle.cancel()
        }
    }
    
    func includesFilter(_ filter: NDKFilter) -> Bool {
        // Check if this requirement's filter is a superset of the given filter
        
        // If we have specific kinds, the filter must only request those kinds
        if let ourKinds = self.filter.kinds,
           let theirKinds = filter.kinds {
            if !Set(ourKinds).isSuperset(of: Set(theirKinds)) {
                return false
            }
        }
        
        // Same for authors
        if let ourAuthors = self.filter.authors,
           let theirAuthors = filter.authors {
            if !Set(ourAuthors).isSuperset(of: Set(theirAuthors)) {
                return false
            }
        }
        
        // Same for event IDs
        if let ourIds = self.filter.ids,
           let theirIds = filter.ids {
            if !Set(ourIds).isSuperset(of: Set(theirIds)) {
                return false
            }
        }
        
        // Check tags - our tags must include all of their required tags
        if let theirTags = filter.tags {
            guard let ourTags = self.filter.tags else { return false }
            
            // Check each tag key
            for (key, theirValues) in theirTags {
                guard let ourValues = ourTags[key] else { return false }
                if !ourValues.isSuperset(of: theirValues) {
                    return false
                }
            }
        }
        
        // Time range checks
        if let ourSince = self.filter.since,
           let theirSince = filter.since,
           ourSince > theirSince {
            return false
        }
        
        if let ourUntil = self.filter.until,
           let theirUntil = filter.until,
           ourUntil < theirUntil {
            return false
        }
        
        // Limit check - we must have at least as high a limit
        if let ourLimit = self.filter.limit,
           let theirLimit = filter.limit,
           ourLimit < theirLimit {
            return false
        }
        
        return true
    }
    
    func startProcessing() async {
        guard let cache = cache else {
            NDKLogger.log(.error, category: .subscription, "❌ Cannot start processing - no cache available!")
            return
        }
        
        NDKLogger.log(.info, category: .subscription, "🏁 Starting event processing - subscriptionId: \(subscriptionId), closeOnEose: \(closeOnEose)")
        
        // Set up EOSE handler for closeOnEose subscriptions
        if closeOnEose {
            await internalSubscription.onEOSE { [weak self] in
                guard let self = self else { return }
                NDKLogger.log(.info, category: .subscription, "🏁 EOSE received - closing subscription: \(self.subscriptionId)")
                // Close subscription after EOSE
                Task {
                    await self.internalSubscription.close()
                }
            }
        }
        
        // Process events from subscription
        Task {
            var eventCount = 0
            NDKLogger.log(.debug, category: .subscription, "👂 Listening for events on subscription: \(subscriptionId)")
            
            for await (event, relay) in await internalSubscription.events {
                eventCount += 1
                NDKLogger.log(.trace, category: .subscription, "📨 Event #\(eventCount) received - id: \(event.id), kind: \(event.kind), from: \(relay)")
                
                // ONLY send to cache - cache is the single source of truth
                // Cache will notify ALL observers including our data sources
                do {
                    try await cache.processEvent(
                        event,
                        from: relay,
                        subscriptionId: subscriptionId
                    )
                    NDKLogger.log(.trace, category: .subscription, "✅ Event processed by cache")
                } catch {
                    NDKLogger.log(.error, category: .subscription, "❌ Failed to process event: \(error)")
                }
            }
            
            NDKLogger.log(.info, category: .subscription, "🔚 Event stream ended - processed \(eventCount) events for subscription: \(subscriptionId)")
        }
    }
}

/// Handle for managing a data requirement
public struct DataRequirementHandle {
    let id: RequirementID
    weak var manager: NDKDataRequirementManager?
    
    /// Release this data requirement
    public func release() async {
        await manager?.releaseRequirement(id: id)
    }
}