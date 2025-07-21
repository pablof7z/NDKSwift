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
    }
    
    /// Register a new data requirement
    /// - Parameters:
    ///   - filter: The filter defining what data is needed
    ///   - observer: The observer to notify when data arrives
    ///   - maxAge: Maximum age of cached data to consider fresh (0 = live subscription)
    ///   - cachePolicy: How to handle cache vs network
    /// - Returns: Handle for managing the requirement lifecycle
    func registerRequirement(
        filter: NDKFilter,
        observer: CacheObserver,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil
    ) async -> DataRequirementHandle {
        let requirementId = RequirementID()
        
        // Handle cache-only policy
        if cachePolicy == .cacheOnly {
            // Only return cached data, never hit network
            let cachedEvents = try? await ndk.cache.queryEvents(filter)
            if let events = cachedEvents {
                for event in events {
                    await observer.handleEvent(event)
                }
            }
            // Return dummy handle that does nothing
            return DataRequirementHandle(id: requirementId, manager: nil)
        }
        
        // Check cache freshness for cacheWithNetwork policy
        if cachePolicy == .cacheWithNetwork && maxAge > 0 {
            // Check if we have fresh cached data
            if let lastFetch = await ndk.cache.getLastFetchTime(for: filter) {
                let age = Date().timeIntervalSince(lastFetch)
                if age <= maxAge {
                    // Cache is fresh enough - return cached data
                    let cachedEvents = try? await ndk.cache.queryEvents(filter)
                    if let events = cachedEvents, !events.isEmpty {
                        for event in events {
                            await observer.handleEvent(event)
                        }
                        // For maxAge > 0, we don't keep subscription open
                        return DataRequirementHandle(id: requirementId, manager: nil)
                    }
                }
            }
        }
        
        // For networkOnly or when cache is stale/empty, proceed with network request
        let signature = FilterSignature(from: filter)
        
        // Check if we can reuse an existing requirement (only for live subscriptions)
        if maxAge == 0, let existing = findMatchingRequirement(for: filter) {
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
            relays: relays
        )
        
        // Add to pending queue
        pendingRequirements[signature, default: []].append(pending)
        
        // Start or extend grouping timer
        if flushTasks[signature] == nil {
            flushTasks[signature] = Task {
                try? await Task.sleep(nanoseconds: UInt64(groupingWindow * 1_000_000_000))
                await flushPendingRequirements(for: signature)
            }
        }
        
        return DataRequirementHandle(
            id: requirementId,
            manager: self
        )
    }
    
    /// Release a data requirement
    func releaseRequirement(id: RequirementID) async {
        guard let requirement = activeRequirements[id] else { return }
        
        await requirement.removeObserver(id: id)
        
        // If no more observers, close the subscription
        if requirement.observerCount == 0 {
            await requirement.internalSubscription.close()
            activeRequirements.removeValue(forKey: id)
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
        flushTasks.removeValue(forKey: signature)
        
        guard let pending = pendingRequirements.removeValue(forKey: signature),
              !pending.isEmpty else { return }
        
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
                    relays = await ndk.outbox.getRecommendedRelaysForSubscription(filters: [aggregatedFilter])
                }
                
                // Create subscription using internal manager
                // Use a deterministic subscription ID based on the filter
                let subscriptionId = "ds_\(UUID().uuidString)"
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
                for p in lifecycleGroup {
                    // Only add observer if this aggregated filter covers their individual filter
                    if requirement.includesFilter(p.filter) {
                        await requirement.addObserver(p.observer, id: p.id, individualFilter: p.filter)
                        if !closeOnEose {
                            // Only track in activeRequirements if it's a live subscription
                            activeRequirements[p.id] = requirement
                        }
                    }
                }
                
                // Start processing events
                Task {
                    await requirement.startProcessing()
                    
                    // Record fetch time after processing starts
                    await ndk.cache.recordFetchTime(for: aggregatedFilter, timestamp: Date())
                }
            }
        }
    }
    
    /// Smart filter aggregation that returns multiple filters when needed
    private func aggregateFilters(_ filters: [NDKFilter]) -> [NDKFilter] {
        // Group filters by compatibility
        let filterGroups = groupCompatibleFilters(filters)
        
        // Aggregate each group separately
        return filterGroups.map { group in
            aggregateSingleGroup(group)
        }
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
        // Register observer with cache - cache is the single source of truth
        if let cache = cache {
            let handle = await cache.observeEvents(
                matching: individualFilter,
                observer: observer
            )
            observerHandles[id] = handle
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
        guard let cache = cache else { return }
        
        // Set up EOSE handler for closeOnEose subscriptions
        if closeOnEose {
            await internalSubscription.onEOSE { [weak self] in
                guard let self = self else { return }
                // Close subscription after EOSE
                Task {
                    await self.internalSubscription.close()
                }
            }
        }
        
        // Process events from subscription
        Task {
            for await (event, relay) in await internalSubscription.events {
                // ONLY send to cache - cache is the single source of truth
                // Cache will notify ALL observers including our data sources
                try? await cache.processEvent(
                    event,
                    from: relay,
                    subscriptionId: subscriptionId
                )
            }
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