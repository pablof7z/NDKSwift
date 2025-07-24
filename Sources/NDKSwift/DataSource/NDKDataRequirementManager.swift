import Foundation

/// Manages data requirements from multiple components
/// Handles temporal grouping, deduplication, and lifecycle management
actor NDKDataRequirementManager {
    private let ndk: NDK
    private let groupingWindow: TimeInterval = NetworkConstants.dataGroupingWindow
    
    // Active requirements tracked by ID
    private var activeRequirements: [RequirementID: DataRequirement] = [:]
    
    // Pending requirements waiting to be grouped
    private var pendingRequirements: [FilterSignature: [PendingRequirement]] = [:]
    
    // Timer tasks for flushing pending requirements
    private var flushTasks: [FilterSignature: Task<Void, Never>] = [:]
    
    // Track requirements that have immediate cache observations
    private var immediateCacheHandles: [RequirementID: ObservationHandle] = [:]
    
    init(ndk: NDK) {
        self.ndk = ndk
        NDKLogger.log(.debug, category: .subscription, "🏗️ NDKDataRequirementManager initialized")
        
        // Start periodic cleanup task
        Task {
            await startPeriodicCleanup()
        }
    }
    
    /// Periodic cleanup of stale handles and requirements
    private func startPeriodicCleanup() async {
        while !Task.isCancelled {
            // Wait 1 hour between cleanups
            try? await Task.sleep(nanoseconds: UInt64(TimeConstants.hour * Double(TimeConstants.nanosecondsPerSecond)))
            
            // Clean up orphaned immediate cache handles
            let activeIds = Set(activeRequirements.keys)
            let handleIds = Set(immediateCacheHandles.keys)
            let orphanedIds = handleIds.subtracting(activeIds)
            
            if !orphanedIds.isEmpty {
                NDKLogger.log(.info, category: .subscription, "🧹 Cleaning up \(orphanedIds.count) orphaned cache handles")
                for id in orphanedIds {
                    if let handle = immediateCacheHandles.removeValue(forKey: id) {
                        await handle.cancel()
                    }
                }
            }
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
    /// - Returns: Handle for managing the requirement lifecycle
    func registerRequirement(
        filter: NDKFilter,
        observer: CacheObserver,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil
    ) async -> DataRequirementHandle {
        let requirementId = RequirementID()
        let correlationId = requirementId.uuidString.prefix(8)
        
        NDKLogger.log(.info, category: .subscription, "📥 [DataReqManager] registerRequirement - filter: \(filter), maxAge: \(maxAge), policy: \(cachePolicy), subscriptionId: \(subscriptionId ?? "auto")", correlationId: String(correlationId))
        
        // IMMEDIATELY register cache observer to deliver existing events
        // This happens before any delay, giving instant cache hits
        var cacheObservationHandle: ObservationHandle?
        if cachePolicy != .networkOnly {
            cacheObservationHandle = await ndk.cache.observeEvents(
                matching: filter,
                observer: observer
            )
            // Track this handle so we can clean it up if needed
            if let handle = cacheObservationHandle {
                immediateCacheHandles[requirementId] = handle
            }
        }
        
        // Handle cache-only policy
        if cachePolicy == .cacheOnly {
            // Return handle that can cancel the cache observation
            return DataRequirementHandle(
                id: requirementId, 
                manager: nil,
                cacheObservationHandle: cacheObservationHandle
            )
        }
        
        // For networkOnly or when cache is stale/empty, proceed with network request
        let signature = FilterSignature(from: filter)
        
        // Check if we can reuse an existing requirement (only for live subscriptions)
        if maxAge == 0, let existing = findMatchingRequirement(for: filter) {
            await existing.addObserver(observer, id: requirementId, individualFilter: filter)
            return DataRequirementHandle(
                id: requirementId,
                manager: self,
                cacheObservationHandle: cacheObservationHandle
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
            exclusiveRelays: exclusiveRelays,
            subscriptionId: subscriptionId,
            cacheObservationHandle: cacheObservationHandle
        )
        
        // Add to pending queue
        pendingRequirements[signature, default: []].append(pending)
        
        // Start or extend grouping timer
        if flushTasks[signature] == nil {
            NDKLogger.log(.debug, category: .subscription, "⏰ [DataReqManager] Starting grouping timer for \(groupingWindow)s", correlationId: String(correlationId))
            flushTasks[signature] = Task {
                try? await Task.sleep(nanoseconds: UInt64(groupingWindow * Double(TimeConstants.nanosecondsPerSecond)))
                NDKLogger.log(.debug, category: .subscription, "⏰ [DataReqManager] Grouping timer expired, flushing...", correlationId: String(correlationId))
                await flushPendingRequirements(for: signature)
            }
        } else {
            NDKLogger.log(.trace, category: .subscription, "⏲️ Grouping timer already running", correlationId: String(correlationId))
        }
        
        return DataRequirementHandle(
            id: requirementId,
            manager: self,
            cacheObservationHandle: cacheObservationHandle
        )
    }
    
    /// Release a data requirement
    func releaseRequirement(id: RequirementID) async {
        let correlationId = id.uuidString.prefix(8)
        NDKLogger.log(.debug, category: .subscription, "🔓 Releasing requirement", correlationId: String(correlationId))
        
        // Clean up any immediate cache handle
        if let handle = immediateCacheHandles.removeValue(forKey: id) {
            await handle.cancel()
        }
        
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
        NDKLogger.log(.info, category: .subscription, "🔄 [DataReqManager] flushPendingRequirements called for signature: \(signature)")
        flushTasks.removeValue(forKey: signature)
        
        guard let pending = pendingRequirements.removeValue(forKey: signature),
              !pending.isEmpty else {
            NDKLogger.log(.trace, category: .subscription, "No pending requirements to flush")
            return
        }
        
        NDKLogger.log(.debug, category: .subscription, "📋 [DataReqManager] Flushing \(pending.count) pending requirements")
        
        
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
            let cachePolicy = lifecycleGroup.first?.cachePolicy ?? .cacheWithNetwork
            
            // Check cache freshness if maxAge > 0 and cachePolicy allows it
            var shouldFetchFromNetwork = true
            if maxAge > 0 && cachePolicy == .cacheWithNetwork {
                // Check if we have fresh data in cache
                if let lastFetchTime = await ndk.cache.getLastFetchTime(for: aggregatedFilters[0]) {
                    let age = Date().timeIntervalSince(lastFetchTime)
                    if age <= maxAge {
                        NDKLogger.log(.info, category: .subscription, "✅ Cache is fresh (age: \(Int(age))s, maxAge: \(Int(maxAge))s) - skipping network fetch")
                        shouldFetchFromNetwork = false
                        
                        // We're not creating a subscription since cache is fresh
                        // The immediate cache observations will continue to deliver events
                        // Just remove from immediate handles tracking since they're now owned by the DataRequirementHandle
                        for p in lifecycleGroup {
                            immediateCacheHandles.removeValue(forKey: p.id)
                        }
                        continue
                    } else {
                        NDKLogger.log(.info, category: .subscription, "🔄 Cache is stale (age: \(Int(age))s, maxAge: \(Int(maxAge))s) - fetching from network")
                    }
                }
            }
            
            // Skip network fetch if not needed
            if !shouldFetchFromNetwork {
                continue
            }
            
            // Create a subscription for each aggregated filter
            for aggregatedFilter in aggregatedFilters {
                // Optimize filter for cache - remove event IDs we already have
                guard let optimizedFilter = await optimizeFilterForCache(aggregatedFilter) else {
                    NDKLogger.log(.info, category: .subscription, "✅ All events in filter already cached - skipping subscription")
                    
                    // Still need to notify observers about cached events
                    for p in lifecycleGroup {
                        if aggregatedFilter.fingerprint == p.filter.fingerprint || 
                           (aggregatedFilter.ids != nil && p.filter.ids != nil && 
                            Set(aggregatedFilter.ids ?? []).isSuperset(of: Set(p.filter.ids ?? []))) {
                            // The cache observer will deliver the cached events
                            NDKLogger.log(.debug, category: .subscription, "📦 Observer will receive cached events for filter: \(p.filter.fingerprint)")
                            // Remove from immediate handles tracking since they're now owned by the DataRequirementHandle
                            immediateCacheHandles.removeValue(forKey: p.id)
                        }
                    }
                    continue // Skip creating subscription
                }
                
                // Use specified relays if provided, otherwise use outbox if enabled
                var relays: Set<RelayURL>? = lifecycleGroup.first?.relays
                
                // Handle outbox model filter decomposition
                if relays == nil && ndk.outboxEnabled && optimizedFilter.authors != nil {
                    NDKLogger.log(.info, category: .subscription, "🎯 [DataReqManager] Using outbox strategy for filter")
                    let outboxStrategy = await ndk.outbox.getOutboxStrategy(for: optimizedFilter)
                    
                    // Start background discovery if needed
                    if !outboxStrategy.authorsToDiscover.isEmpty {
                        NDKLogger.log(.info, category: .subscription, "🔍 [DataReqManager] Triggering background relay discovery for \(outboxStrategy.authorsToDiscover.count) authors")
                        Task {
                            await ndk.outbox.discoverRelaysInBackground(for: outboxStrategy.authorsToDiscover)
                        }
                    }
                    
                    // Register subscription for relay updates if there are unknown authors
                    if !outboxStrategy.unknownAuthors.isEmpty && !closeOnEose {
                        let mainSubscriptionId = lifecycleGroup.compactMap { $0.subscriptionId }.first ?? generateSubscriptionId(for: optimizedFilter)
                        await ndk.outbox.registerSubscriptionForUpdates(
                            id: mainSubscriptionId,
                            filter: optimizedFilter,
                            unknownAuthors: outboxStrategy.unknownAuthors
                        )
                        NDKLogger.log(.info, category: .subscription, "📡 [DataReqManager] Registered subscription '\(mainSubscriptionId)' for relay updates")
                    }
                    
                    // If we have relay-specific filters, create multiple subscriptions
                    if outboxStrategy.hasRelaySpecificFilters {
                        NDKLogger.log(.info, category: .subscription, "📊 [DataReqManager] Creating \(outboxStrategy.filtersByRelay.count) relay-specific subscriptions")
                        
                        // Track all requirements created for this group
                        var createdRequirements: [DataRequirement] = []
                        
                        // Create a subscription for each relay with its specific filter
                        for (relay, relaySpecificFilter) in outboxStrategy.filtersByRelay {
                            let relayHost = URL(string: relay)?.host ?? relay
                            let subscriptionId = lifecycleGroup.compactMap { $0.subscriptionId }.first.map { "\($0)_\(relayHost)" } ?? "\(generateSubscriptionId(for: relaySpecificFilter))_\(relayHost)"
                            
                            NDKLogger.log(.debug, category: .subscription, "📡 [DataReqManager] Creating subscription for \(relay): \(relaySpecificFilter.authors?.count ?? 0) authors")
                            
                            let internalSubscription = await ndk.internalSubscriptionManager.createSubscription(
                                id: subscriptionId,
                                filters: [relaySpecificFilter],
                                relays: [relay]
                            )
                            
                            // Create data requirement for this relay
                            let requirement = DataRequirement(
                                filter: relaySpecificFilter,
                                subscriptionId: internalSubscription.id,
                                internalSubscription: internalSubscription,
                                cache: ndk.cache,
                                ndk: ndk,
                                relays: Set([relay]),
                                exclusiveRelays: lifecycleGroup.first?.exclusiveRelays ?? false,
                                closeOnEose: closeOnEose
                            )
                            
                            createdRequirements.append(requirement)
                        }
                        
                        // Add observers to all created requirements
                        for p in lifecycleGroup {
                            for requirement in createdRequirements {
                                // Check if this requirement's filter includes any of the observer's authors
                                if let reqAuthors = requirement.filter.authors,
                                   let obsAuthors = p.filter.authors {
                                    let hasOverlap = !Set(reqAuthors).isDisjoint(with: Set(obsAuthors))
                                    if hasOverlap {
                                        await requirement.addObserver(p.observer, id: p.id, individualFilter: p.filter)
                                        if !closeOnEose {
                                            activeRequirements[p.id] = requirement
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Cancel immediate cache observations since requirements handle their own
                        for p in lifecycleGroup {
                            await p.cacheObservationHandle?.cancel()
                            immediateCacheHandles.removeValue(forKey: p.id)
                        }
                        
                        // Start processing all requirements
                        for requirement in createdRequirements {
                            Task {
                                await requirement.startProcessing()
                            }
                        }
                        
                        // Record fetch time
                        await ndk.cache.recordFetchTime(for: aggregatedFilter, timestamp: Date())
                        
                        // Skip the normal single subscription creation
                        continue
                    }
                    
                    // If no relay-specific filters, fall back to using all connected relays
                    NDKLogger.log(.debug, category: .subscription, "📡 [DataReqManager] No relay-specific filters, using all connected relays")
                    relays = nil
                }
                
                // Create single subscription for non-outbox or non-decomposed cases
                let subscriptionId = lifecycleGroup.compactMap { $0.subscriptionId }.first ?? generateSubscriptionId(for: optimizedFilter)
                NDKLogger.log(.info, category: .subscription, "📡 [DataReqManager] Creating internal subscription - id: \(subscriptionId), filter: \(optimizedFilter), relays: \(relays?.joined(separator: ", ") ?? "all")")
                let internalSubscription = await ndk.internalSubscriptionManager.createSubscription(
                    id: subscriptionId,
                    filters: [optimizedFilter],
                    relays: relays
                )
                NDKLogger.log(.debug, category: .subscription, "✅ [DataReqManager] Internal subscription created")
                
                // Create data requirement (use original aggregated filter for coverage checks)
                let requirement = DataRequirement(
                    filter: aggregatedFilter,
                    subscriptionId: internalSubscription.id,
                    internalSubscription: internalSubscription,
                    cache: ndk.cache,
                    ndk: ndk,
                    relays: relays,
                    exclusiveRelays: lifecycleGroup.first?.exclusiveRelays ?? false,
                    closeOnEose: closeOnEose
                )
                
                // Add relevant observers to this requirement
                var addedObservers = 0
                for p in lifecycleGroup {
                    // Only add observer if this aggregated filter covers their individual filter
                    let covers = requirement.includesFilter(p.filter)
                    
                    if covers {
                        // Cancel the immediate cache observation since DataRequirement will set up its own
                        await p.cacheObservationHandle?.cancel()
                        // Remove from immediate cache handles tracking
                        immediateCacheHandles.removeValue(forKey: p.id)
                        
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
        let aggregated = filterGroups.map { group in
            aggregateSingleGroup(group)
        }
        
        for (index, filter) in aggregated.enumerated() {
            NDKLogger.log(.trace, category: .subscription, "Group \(index + 1): \(filter.fingerprint)")
        }
        
        return aggregated
    }
    
    /// Optimize filter by removing event IDs that are already in cache
    /// Returns nil if all requested IDs are in cache (no subscription needed)
    private func optimizeFilterForCache(_ filter: NDKFilter) async -> NDKFilter? {
        // Only optimize if filter has specific event IDs
        guard let requestedIds = filter.ids, !requestedIds.isEmpty else {
            return filter
        }
        
        // Check which IDs we already have
        let cacheStatus = await ndk.cache.hasEvents(ids: requestedIds)
        let missingIds = requestedIds.filter { cacheStatus[$0] != true }
        
        // If we have all IDs, no need for subscription
        if missingIds.isEmpty {
            NDKLogger.log(.info, category: .subscription, "✅ All \(requestedIds.count) event IDs found in cache - no subscription needed")
            return nil
        }
        
        // If we have some IDs, create optimized filter with only missing ones
        if missingIds.count < requestedIds.count {
            var optimizedFilter = filter
            optimizedFilter.ids = missingIds
            NDKLogger.log(.info, category: .subscription, "🎯 Optimized filter - removed \(requestedIds.count - missingIds.count) cached IDs")
            return optimizedFilter
        }
        
        // All IDs are missing, use original filter
        return filter
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
        // 1. Same or compatible kinds
        // 2. Same or compatible authors
        // 3. Same tag keys (values can differ and will be merged)
        
        // Check kinds compatibility
        if let kinds1 = filter1.kinds, let kinds2 = filter2.kinds {
            // Both have kinds - check if they're the same or one is subset
            let set1 = Set(kinds1)
            let set2 = Set(kinds2)
            
            // Allow merging if:
            // - They have overlap OR
            // - They have the same count (likely similar queries) OR
            // - One is a subset of the other
            if set1.isDisjoint(with: set2) && 
               kinds1.count != kinds2.count && 
               !set1.isSubset(of: set2) && 
               !set2.isSubset(of: set1) {
                return false
            }
        }
        
        // Check authors compatibility
        if let authors1 = filter1.authors, let authors2 = filter2.authors {
            // Both have authors - must have overlap or be for same purpose
            let set1 = Set(authors1)
            let set2 = Set(authors2)
            
            if set1.isDisjoint(with: set2) && 
               authors1.count != authors2.count &&
               !set1.isSubset(of: set2) && 
               !set2.isSubset(of: set1) {
                return false
            }
        }
        
        // For tags: allow merging if they have the same tag keys
        // Different values will be aggregated (unioned) during merge
        let keys1 = filter1.tags?.keys != nil ? Set(filter1.tags!.keys) : Set<String>()
        let keys2 = filter2.tags?.keys != nil ? Set(filter2.tags!.keys) : Set<String>()
        
        // If they have different tag keys, they're likely different queries
        if !keys1.isEmpty && !keys2.isEmpty && keys1 != keys2 {
            return false
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
    
    /// Generate a meaningful subscription ID based on filter content
    private func generateSubscriptionId(for filter: NDKFilter) -> String {
        var parts: [String] = []
        
        // Add kind description
        if let kinds = filter.kinds {
            let kindDescription = describeKinds(kinds)
            parts.append(kindDescription)
        }
        
        // Add author info
        if let authors = filter.authors {
            if authors.count == 1 {
                parts.append("author_\(authors[0].prefix(8))")
            } else if authors.count > 1 {
                parts.append("authors_\(authors.count)")
            }
        }
        
        // Add event ID info
        if let ids = filter.ids {
            if ids.count == 1 {
                parts.append("event_\(ids[0].prefix(8))")
            } else if ids.count > 1 {
                parts.append("events_\(ids.count)")
            }
        }
        
        // Add tag info
        if let tags = filter.tags, !tags.isEmpty {
            let tagKeys = tags.keys.sorted().joined(separator: "_")
            parts.append("tags_\(tagKeys)")
        }
        
        // Add time info
        if filter.since != nil || filter.until != nil {
            parts.append("timed")
        }
        
        // If no meaningful parts, use generic
        if parts.isEmpty {
            parts.append("general")
        }
        
        // Add a short random suffix for uniqueness
        let suffix = IDGenerator.randomId(length: 4)
        parts.append(suffix)
        
        return parts.joined(separator: "_")
    }
    
    /// Get human-readable description for event kinds
    private func describeKinds(_ kinds: [Int]) -> String {
        // Map common kinds to descriptions
        let kindMap: [Int: String] = [
            EventKind.metadata: "metadata",
            EventKind.textNote: "notes",
            EventKind.contacts: "contacts",
            EventKind.encryptedDirectMessage: "dm",
            EventKind.deletion: "deletion",
            EventKind.repost: "repost",
            EventKind.reaction: "reaction",
            EventKind.channel: "channel",
            EventKind.channelMetadata: "channel_meta",
            EventKind.channelMessage: "channel_msg",
            EventKind.report: "report",
            EventKind.zapRequest: "zap_req",
            EventKind.zap: "zap",
            EventKind.muteList: "mute_list",
            EventKind.pinList: "pin_list",
            EventKind.relayList: "relay_list",
            EventKind.bookmarkList: "bookmarks",
            EventKind.communitiesList: "communities",
            EventKind.publicChatsList: "public_chats",
            EventKind.blockedRelays: "blocked_relays",
            EventKind.searchRelays: "search_relays",
            EventKind.categorizedPeopleList: "categorized_people",
            EventKind.categorizedBookmarkList: "categorized_bookmarks",
            EventKind.profileBadges: "profile_badges",
            EventKind.badgeDefinition: "badge_definition",
            EventKind.longFormContent: "long_form",
            EventKind.draftLongForm: "draft_long_form",
            EventKind.applicationSpecificData: "app_specific_data",
            EventKind.liveEvent: "live_event",
            EventKind.handlerRecommendation: "handler_recommendation",
            EventKind.handlerInformation: "handler_information"
        ]
        
        var descriptions: [String] = []
        for kind in kinds.sorted() {
            if let desc = kindMap[kind] {
                descriptions.append(desc)
            } else {
                descriptions.append("kind\(kind)")
            }
        }
        
        // Limit to first 3 kinds to keep ID reasonable length
        if descriptions.count > 3 {
            return descriptions.prefix(3).joined(separator: "_") + "_more"
        }
        
        return descriptions.joined(separator: "_")
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
    let exclusiveRelays: Bool
    let subscriptionId: String?
    let cacheObservationHandle: ObservationHandle?
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
    private var observers: [RequirementID: CacheObserver] = [:]  // Track observers for relay updates
    private let relays: Set<RelayURL>?
    private let exclusiveRelays: Bool
    
    var observerCount: Int { observerHandles.count }
    
    init(filter: NDKFilter, subscriptionId: String, internalSubscription: InternalSubscription, cache: NDKCache?, ndk: NDK, relays: Set<RelayURL>? = nil, exclusiveRelays: Bool = false, closeOnEose: Bool = false) {
        self.filter = filter
        self.subscriptionId = subscriptionId
        self.internalSubscription = internalSubscription
        self.cache = cache
        self.ndk = ndk
        self.relays = relays
        self.exclusiveRelays = exclusiveRelays
        self.closeOnEose = closeOnEose
    }
    
    func addObserver(_ observer: CacheObserver, id: RequirementID, individualFilter: NDKFilter) async {
        let correlationId = id.uuidString.prefix(8)
        
        // Store observer reference for relay updates
        observers[id] = observer
        
        // Register observer with cache - cache is the single source of truth
        if let cache = cache {
            let handle = await cache.observeEvents(
                matching: individualFilter,
                observer: observer
            )
            observerHandles[id] = handle
        } else {
            NDKLogger.log(.error, category: .subscription, "❌ No cache available - observer not registered!", correlationId: String(correlationId))
        }
    }
    
    func removeObserver(id: RequirementID) async {
        if let handle = observerHandles.removeValue(forKey: id) {
            await handle.cancel()
        }
        observers.removeValue(forKey: id)
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
        NDKLogger.log(.debug, category: .subscription, "🎬 [DataRequirement] startProcessing called for subscription: \(subscriptionId)")
        guard let cache = cache else {
            NDKLogger.log(.error, category: .subscription, "❌ Cannot start processing - no cache available!")
            return
        }
        
        // The subscription is already started by InternalSubscriptionManager.createSubscription()
        NDKLogger.log(.debug, category: .subscription, "📋 [DataRequirement] Processing events from internal subscription...")
        
        // Track received event IDs if this filter is for specific IDs
        let requestedIds = filter.ids
        var receivedIds: Set<String>? = requestedIds != nil ? Set() : nil
        
        // Set up EOSE handler
        await internalSubscription.onEOSE { [weak self] relay in
            guard let self = self else { return }
            
            // Forward EOSE to all observers as relay updates
            for (_, observer) in self.observers {
                await observer.handleRelayUpdate(.eose(relay: relay))
            }
            
            // Close subscription if closeOnEose is set OR if we have all requested event IDs
            let shouldClose = self.closeOnEose || 
                (requestedIds != nil && receivedIds != nil && Set(requestedIds!) == receivedIds!)
            
            if shouldClose {
                Task {
                    await self.internalSubscription.close()
                }
            }
        }
        
        // Process events from subscription
        Task {
            var eventCount = 0
            
            for await (event, relay) in await internalSubscription.events {
                eventCount += 1
                NDKLogger.log(.trace, category: .subscription, "📨 Event #\(eventCount) received - id: \(event.id), kind: \(event.kind), from: \(relay)")
                
                // Apply exclusive relay filtering if enabled
                if exclusiveRelays, let relayFilter = relays {
                    guard relayFilter.contains(relay) else {
                        NDKLogger.log(.trace, category: .subscription, "⏭️ Skipping event from non-exclusive relay: \(relay)")
                        continue
                    }
                }
                
                // Track received event IDs
                if receivedIds != nil {
                    receivedIds!.insert(event.id)
                    
                    // Check if we've received all requested IDs
                    if let requested = requestedIds, Set(requested) == receivedIds! {
                        NDKLogger.log(.info, category: .subscription, "✅ Received all \(requested.count) requested event IDs - closing subscription immediately")
                        Task {
                            await self.internalSubscription.close()
                        }
                    }
                }
                
                // Send event to cache
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
                
                // Also forward as relay update to data sources
                for (_, observer) in observers {
                    await observer.handleRelayUpdate(.event(event, relay: relay))
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
    let cacheObservationHandle: ObservationHandle?
    
    init(id: RequirementID, manager: NDKDataRequirementManager?, cacheObservationHandle: ObservationHandle? = nil) {
        self.id = id
        self.manager = manager
        self.cacheObservationHandle = cacheObservationHandle
    }
    
    /// Release this data requirement
    public func release() async {
        // Cancel cache observation if present
        await cacheObservationHandle?.cancel()
        // Release the requirement from manager
        await manager?.releaseRequirement(id: id)
    }
}