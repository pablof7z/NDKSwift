import Foundation

/// Advanced subscription manager that handles grouping, merging, and coordination
public actor NDKSubscriptionManager {
    // MARK: - Types

    /// Subscription execution state
    public enum SubscriptionState {
        case pending
        case grouping
        case executing
        case active
        case closed
    }

    /// Subscription execution plan
    struct ExecutionPlan {
        let subscriptions: [NDKSubscription]
        let mergedFilters: [NDKFilter]
        let relaySet: Set<NDKRelay>
        let useCache: Bool
        let closeOnEose: Bool
        let delay: TimeInterval
    }

    /// Filter fingerprint for grouping compatibility
    /// Follows ndk-core's approach: uses filter keys (not values) to determine groupability
    struct FilterFingerprint: Hashable {
        let value: String
        
        /// Create fingerprint from filters following ndk-core pattern:
        /// Format: [+][filter-keys-sorted|filter-keys-sorted|...]
        /// - Prefix '+' indicates closeOnEose
        /// - Filter keys are sorted alphabetically
        /// - Multiple filters separated by '|'
        /// - Time constraints (since/until) include actual values
        init(filters: [NDKFilter], closeOnEose: Bool) {
            var parts: [String] = []
            
            for filter in filters {
                var keys: [String] = []
                
                // Add keys for non-nil properties (not values, except for time)
                if filter.ids != nil { keys.append("ids") }
                if filter.authors != nil { keys.append("authors") }
                if filter.kinds != nil { keys.append("kinds") }
                if filter.events != nil { keys.append("#e") }
                if filter.pubkeys != nil { keys.append("#p") }
                
                // Time constraints include values to prevent mixing different windows
                if let since = filter.since { keys.append("since:\(since)") }
                if let until = filter.until { keys.append("until:\(until)") }
                
                // Limit affects groupability
                if filter.limit != nil { keys.append("limit") }
                
                // Add generic tag filters
                if let tags = filter.tags {
                    for tagName in tags.keys.sorted() {
                        keys.append("#\(tagName)")
                    }
                }
                
                // Sort keys and join
                let filterPart = keys.sorted().joined(separator: "-")
                parts.append(filterPart)
            }
            
            // Build final fingerprint
            let prefix = closeOnEose ? "+" : ""
            self.value = prefix + parts.joined(separator: "|")
        }
    }

    // MARK: - Properties

    private weak var ndk: NDK?
    private var activeSubscriptions: [String: NDKSubscription] = [:]
    private var subscriptionStates: [String: SubscriptionState] = [:]
    private var pendingGroups: [FilterFingerprint: PendingGroup] = [:]
    private var eventDeduplication: [EventID: Timestamp] = [:]
    private var eoseTracking: [String: EOSETracker] = [:]
    
    // Tombstone cache for deletion events that arrive before the original event
    private var deletionTombstones: [EventID: Timestamp] = [:]
    private let tombstoneTTL: TimeInterval = 600 // 10 minutes

    /// Configuration
    private let maxFiltersPerRequest = 10
    private let groupingDelay: TimeInterval = 0.1
    private let deduplicationWindow: TimeInterval = 300 // 5 minutes
    private let eoseTimeoutRatio: Double = 0.5 // 50% of relays for timeout

    /// Statistics
    private var stats = SubscriptionStats()

    // MARK: - Pending Group Management

    private struct PendingGroup {
        var subscriptions: [NDKSubscription] = []
        var timer: Task<Void, Never>?
        var createdAt: Date = .init()

        mutating func addSubscription(_ subscription: NDKSubscription) {
            subscriptions.append(subscription)
        }

        mutating func cancel() {
            timer?.cancel()
            timer = nil
        }
    }

    // MARK: - EOSE Tracking

    private struct EOSETracker {
        let targetRelayUrls: Set<String>
        var eosedRelayUrls: Set<String> = []
        var lastEventReceived: Date = .init()
        let createdAt: Date = .init()

        var eosePercentage: Double {
            guard !targetRelayUrls.isEmpty else { return 1.0 }
            return Double(eosedRelayUrls.count) / Double(targetRelayUrls.count)
        }

        var shouldTimeout: Bool {
            let timeSinceLastEvent = Date().timeIntervalSince(lastEventReceived)
            let timeSinceCreation = Date().timeIntervalSince(createdAt)

            // Don't timeout too early or if we recently received events
            return eosePercentage >= 0.5 && timeSinceLastEvent > 0.02 && timeSinceCreation > 0.1
        }

        mutating func recordEose(from relay: RelayProtocol) {
            eosedRelayUrls.insert(relay.url)
        }

        mutating func recordEvent() {
            lastEventReceived = Date()
        }
    }

    // MARK: - Statistics

    public struct SubscriptionStats {
        public var totalSubscriptions: Int = 0
        public var activeSubscriptions: Int = 0
        public var groupedSubscriptions: Int = 0
        public var requestsSaved: Int = 0
        public var eventsDeduped: Int = 0
        public var averageGroupSize: Double = 0

        mutating func recordGrouping(originalCount: Int, finalCount: Int) {
            groupedSubscriptions += originalCount
            requestsSaved += (originalCount - finalCount)
            if finalCount > 0 {
                averageGroupSize = (averageGroupSize + Double(originalCount) / Double(finalCount)) / 2
            }
        }
    }

    // MARK: - Initialization

    public init(ndk: NDK) {
        self.ndk = ndk

        // Start cleanup timer for deduplication
        Task {
            await startPeriodicCleanup()
        }
    }

    // MARK: - Public Interface

    /// Add a subscription to be managed
    public func addSubscription(_ subscription: NDKSubscription) {
        guard let ndk = ndk else { return }

        activeSubscriptions[subscription.id] = subscription
        subscriptionStates[subscription.id] = .pending
        stats.totalSubscriptions += 1
        stats.activeSubscriptions += 1

        // Track subscription creation
        Task {
            await ndk.subscriptionTracker.trackSubscription(
                subscription,
                filter: subscription.filters.first ?? NDKFilter(),
                relayUrls: []
            )
        }

        // Determine execution strategy
        Task {
            if await shouldGroupSubscription(subscription) {
                await addToGrouping(subscription)
            } else {
                executeImmediately(subscription)
            }
        }
    }

    /// Remove a subscription
    public func removeSubscription(_ subscriptionId: String) {
        activeSubscriptions.removeValue(forKey: subscriptionId)
        subscriptionStates.removeValue(forKey: subscriptionId)
        eoseTracking.removeValue(forKey: subscriptionId)
        stats.activeSubscriptions = max(0, stats.activeSubscriptions - 1)

        // Track subscription closure
        if let ndk = ndk {
            Task {
                await ndk.subscriptionTracker.closeSubscription(subscriptionId)
            }
        }
    }

    /// Process an event from a relay
    public func processEvent(_ event: NDKEvent, from relay: RelayProtocol) async {
        await processEvent(event, from: .relay(relay))
    }
    
    /// Process an optimistic event from local publishing
    public func processOptimisticEvent(_ event: NDKEvent) async {
        await processEvent(event, from: .optimistic)
    }
    
    /// Unified event processing for both relay and optimistic events
    private func processEvent(_ event: NDKEvent, from source: EventSource) async {
        let eventId = event.id

        // Check if this event was previously deleted (tombstone check)
        if deletionTombstones[eventId] != nil {
            // This event was deleted before it arrived, discard it
            return
        }

        // Check deduplication (skip for optimistic events to allow immediate UI updates)
        let now = Timestamp.now
        let isUnique: Bool
        
        switch source {
        case .optimistic:
            // Optimistic events are always considered unique for immediate dispatch
            isUnique = true
        case .relay, .cache:
            // Check normal deduplication for relay/cache events
            isUnique = eventDeduplication[eventId] == nil
            if !isUnique {
                stats.eventsDeduped += 1
                return
            }
            eventDeduplication[eventId] = now
        }

        // Process deletion events (NIP-09) before dispatching to subscriptions
        if event.kind == EventKind.deletion {
            await processDeletionEvent(event)
        }

        // Find matching subscriptions and dispatch
        for (subscriptionId, subscription) in activeSubscriptions {
            var matches = false
            for filter in subscription.filters {
                if filter.matches(event: event) {
                    matches = true
                    break
                }
            }
            if matches {
                Task {
                    let relay: RelayProtocol? = {
                        switch source {
                        case .relay(let relay):
                            return relay
                        case .optimistic, .cache:
                            return nil
                        }
                    }()
                    await subscription.handleEvent(event, fromRelay: relay)
                }

                // Track event received (only for relay events)
                if case .relay(let relay) = source, let ndk = ndk {
                    Task {
                        await ndk.subscriptionTracker.trackEventReceived(
                            subscriptionId: subscriptionId,
                            eventId: eventId,
                            relayUrl: relay.url,
                            isUnique: isUnique
                        )
                        
                        // Track relay information in eventTracker
                        if isUnique {
                            // This is the first time we've seen this event, so set as source relay
                            await ndk.eventTracker.setSourceRelay(eventId: eventId, relay: relay.url)
                        } else {
                            // We've seen this event before, just mark it as seen on this relay
                            await ndk.eventTracker.markSeen(eventId: eventId, relay: relay.url)
                        }
                    }
                }

                // Update EOSE tracking (only for relay events)
                if case .relay = source, var tracker = eoseTracking[subscriptionId] {
                    tracker.recordEvent()
                    eoseTracking[subscriptionId] = tracker
                }
            }
        }
    }

    /// Process EOSE from a relay
    public func processEOSE(subscriptionId: String, from relay: RelayProtocol) {
        guard let subscription = activeSubscriptions[subscriptionId],
              var tracker = eoseTracking[subscriptionId] else { return }

        tracker.recordEose(from: relay)
        eoseTracking[subscriptionId] = tracker

        // Track EOSE received
        if let ndk = ndk {
            Task {
                await ndk.subscriptionTracker.trackEoseReceived(
                    subscriptionId: subscriptionId,
                    relayUrl: relay.url
                )
            }
        }

        // Check if we should emit EOSE for this subscription
        if tracker.eosedRelayUrls.count == tracker.targetRelayUrls.count || tracker.shouldTimeout {
            Task {
                await subscription.handleEOSE(fromRelay: relay)
            }

            // closeOnEose is handled internally by the subscription
            // No need to check it here
        }
    }
    
    /// Process COUNT from a relay (NIP-45)
    public func processCount(subscriptionId: String, count: Int, from relay: RelayProtocol) {
        guard let subscription = activeSubscriptions[subscriptionId] else { return }
        
        // Forward to subscription
        Task {
            await subscription.handleCount(count, fromRelay: relay)
        }
    }

    /// Get current statistics
    public func getStats() -> SubscriptionStats {
        return stats
    }

    // MARK: - Grouping Logic

    private func shouldGroupSubscription(_ subscription: NDKSubscription) async -> Bool {
        // Get subscription options
        let options = await subscription.options
        
        // Don't group if groupingDelay is explicitly set to 0
        if let delay = options.groupingDelay, delay == 0 {
            return false
        }
        
        // Don't group if:
        // - Subscription has specific relays
        // - Has a very small limit that shouldn't be shared
        // - closeOnEose is true (these are typically one-shot queries)
        guard options.relays == nil,
              options.limit == nil || options.limit! > 10,
              !options.closeOnEose
        else {
            return false
        }
        
        // Check for time constraints that make grouping risky
        for filter in subscription.filters {
            if filter.since != nil || filter.until != nil {
                return false
            }
        }
        
        return true
    }

    private func addToGrouping(_ subscription: NDKSubscription) async {
        subscriptionStates[subscription.id] = .grouping

        // Create fingerprint for grouping
        let fingerprint = await createFingerprint(for: subscription)

        if var group = pendingGroups[fingerprint] {
            // Add to existing group
            group.addSubscription(subscription)
            pendingGroups[fingerprint] = group
        } else {
            // Create new group
            var group = PendingGroup()
            group.addSubscription(subscription)

            // Get the subscription's grouping delay or use default
            let options = await subscription.options
            let delay = options.groupingDelay ?? groupingDelay

            // Set timer to execute group
            group.timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await executeGroup(fingerprint: fingerprint)
            }

            pendingGroups[fingerprint] = group
        }
    }

    private func createFingerprint(for subscription: NDKSubscription) async -> FilterFingerprint {
        let options = await subscription.options
        return FilterFingerprint(filters: subscription.filters, closeOnEose: options.closeOnEose)
    }

    private func executeGroup(fingerprint: FilterFingerprint) async {
        guard var group = pendingGroups[fingerprint] else { return }

        pendingGroups.removeValue(forKey: fingerprint)
        group.cancel()

        guard !group.subscriptions.isEmpty else { return }

        // Create execution plan
        let plan = await createExecutionPlan(for: group.subscriptions)

        // Execute the plan
        executeSubscriptionGroup(plan)

        // Update statistics
        stats.recordGrouping(originalCount: group.subscriptions.count, finalCount: plan.mergedFilters.count)
    }

    private func createExecutionPlan(for subscriptions: [NDKSubscription]) async -> ExecutionPlan {
        // Merge compatible filters
        let mergedFilters = mergeFilters(from: subscriptions)

        // Collect all unique relays from subscriptions
        var relaySet: Set<NDKRelay> = []
        var useCache = true
        var closeOnEose = false
        
        for subscription in subscriptions {
            let options = await subscription.options
            if let specificRelays = options.relays {
                relaySet.formUnion(specificRelays)
            }
            // If any subscription doesn't use cache, disable for group
            if !options.useCache {
                useCache = false
            }
            // If any subscription has closeOnEose, enable for group
            if options.closeOnEose {
                closeOnEose = true
            }
        }
        
        // If no specific relays, use NDK's default relays
        if relaySet.isEmpty, let ndk = ndk {
            relaySet = Set(await ndk.relays)
        }

        return ExecutionPlan(
            subscriptions: subscriptions,
            mergedFilters: mergedFilters,
            relaySet: relaySet,
            useCache: useCache,
            closeOnEose: closeOnEose,
            delay: 0
        )
    }

    private func mergeFilters(from subscriptions: [NDKSubscription]) -> [NDKFilter] {
        // Following ndk-core approach:
        // 1. Filters with limit are not merged - kept separate
        // 2. Filters without limit are merged using union semantics
        // 3. Limited filters come first in the result
        
        var limitedFilters: [NDKFilter] = []
        var unlimitedFilters: [NDKFilter] = []
        
        // Separate filters by whether they have limits
        for subscription in subscriptions {
            for filter in subscription.filters {
                if filter.limit != nil {
                    limitedFilters.append(filter)
                } else {
                    unlimitedFilters.append(filter)
                }
            }
        }
        
        // Merge unlimited filters using union semantics
        let mergedUnlimited = mergeUnlimitedFilters(unlimitedFilters)
        
        // Combine results: limited filters first, then merged unlimited
        var result = limitedFilters
        if let merged = mergedUnlimited {
            result.append(merged)
        }
        
        // Respect maximum filters per request
        if result.count > maxFiltersPerRequest {
            result = Array(result.prefix(maxFiltersPerRequest))
        }
        
        return result
    }
    
    /// Merge filters without limits using union semantics
    private func mergeUnlimitedFilters(_ filters: [NDKFilter]) -> NDKFilter? {
        guard !filters.isEmpty else { return nil }
        
        // Start with empty sets
        var mergedIds = Set<EventID>()
        var mergedAuthors = Set<PublicKey>()
        var mergedKinds = Set<Kind>()
        var mergedEvents = Set<EventID>()
        var mergedPubkeys = Set<PublicKey>()
        var mergedTags: [String: Set<String>] = [:]
        
        // Use most inclusive time range
        var mergedSince: Timestamp?
        var mergedUntil: Timestamp?
        
        // Union all filter values
        for filter in filters {
            if let ids = filter.ids { mergedIds.formUnion(ids) }
            if let authors = filter.authors { mergedAuthors.formUnion(authors) }
            if let kinds = filter.kinds { mergedKinds.formUnion(kinds) }
            if let events = filter.events { mergedEvents.formUnion(events) }
            if let pubkeys = filter.pubkeys { mergedPubkeys.formUnion(pubkeys) }
            
            // For time constraints, use most inclusive range
            if let since = filter.since {
                mergedSince = mergedSince != nil ? min(mergedSince!, since) : since
            }
            if let until = filter.until {
                mergedUntil = mergedUntil != nil ? max(mergedUntil!, until) : until
            }
            
            // Merge tag filters
            if let tags = filter.tags {
                for (tagName, values) in tags {
                    if mergedTags[tagName] == nil {
                        mergedTags[tagName] = Set<String>()
                    }
                    mergedTags[tagName]?.formUnion(values)
                }
            }
        }
        
        // Create merged filter
        return NDKFilter(
            ids: mergedIds.isEmpty ? nil : Array(mergedIds),
            authors: mergedAuthors.isEmpty ? nil : Array(mergedAuthors),
            kinds: mergedKinds.isEmpty ? nil : Array(mergedKinds),
            events: mergedEvents.isEmpty ? nil : Array(mergedEvents),
            pubkeys: mergedPubkeys.isEmpty ? nil : Array(mergedPubkeys),
            since: mergedSince,
            until: mergedUntil,
            limit: nil, // Unlimited filters only
            tags: mergedTags.isEmpty ? nil : mergedTags
        )
    }

    private func executeImmediately(_ subscription: NDKSubscription) {
        Task {
            let options = await subscription.options
            let plan = await ExecutionPlan(
                subscriptions: [subscription],
                mergedFilters: subscription.filters,
                relaySet: {
                    if let relays = options.relays {
                        return relays
                    } else if let ndk = ndk {
                        return Set(await ndk.relays)
                    } else {
                        return Set([])
                    }
                }(),
                useCache: options.useCache,
                closeOnEose: options.closeOnEose,
                delay: 0
            )

            executeSubscriptionGroup(plan)
        }
    }

    private func executeSubscriptionGroup(_ plan: ExecutionPlan) {
        guard ndk != nil else { return }

        // Mark subscriptions as executing
        for subscription in plan.subscriptions {
            subscriptionStates[subscription.id] = .executing
        }

        // Setup EOSE tracking
        for subscription in plan.subscriptions {
            eoseTracking[subscription.id] = EOSETracker(targetRelayUrls: Set(plan.relaySet.map { $0.url }))
        }

        Task {
            // Handle cache first if needed
            if plan.useCache {
                await executeCacheQuery(plan)
            }

            // Execute relay queries
            await executeRelayQueries(plan)

            // Mark as active
            for subscription in plan.subscriptions {
                subscriptionStates[subscription.id] = .active
            }
        }
    }

    private func executeCacheQuery(_ plan: ExecutionPlan) async {
        guard let ndk = ndk else { return }
        let cache = ndk.cache

        for subscription in plan.subscriptions {
            var cachedEvents: [NDKEvent] = []
            for filter in subscription.filters {
                if let events = try? await cache.queryEvents(filter) {
                    cachedEvents.append(contentsOf: events)
                }
            }

            for event in cachedEvents {
                await subscription.handleEvent(event, fromRelay: nil)
            }

            // Cache query complete
        }
    }

    private func executeRelayQueries(_ plan: ExecutionPlan) async {
        guard ndk != nil else { return }

        // Send subscription to each relay using their subscription managers
        for relay in plan.relaySet {
            for subscription in plan.subscriptions {
                // Register with relay's subscription manager
                _ = await relay.subscriptionManager.addSubscription(subscription, filters: plan.mergedFilters)
            }
        }
    }

    // MARK: - Utilities

    // Removed obsolete cache strategy helpers

    // MARK: - Deletion Event Processing (NIP-09)
    
    /// Process a kind:5 deletion event according to NIP-09
    func processDeletionEvent(_ deletionEvent: NDKEvent) async {
        guard let ndk = ndk else { return }
        
        // Extract event IDs to delete from "e" tags
        let eventIdsToDelete = deletionEvent.tags
            .filter { $0.count >= 2 && $0[0] == "e" }
            .map { $0[1] }
        
        guard !eventIdsToDelete.isEmpty else { return }
        
        let now = Timestamp.now
        
        // For each event ID to delete
        for eventId in eventIdsToDelete {
            // First, try to get the event from cache to verify authorship
            if let eventToDelete = await ndk.cache.getEvent(id: eventId) {
                // NIP-09: Only the author of an event can delete it
                if eventToDelete.pubkey == deletionEvent.pubkey {
                    // Delete from cache
                    do {
                        try await ndk.cache.deleteEvent(id: eventId)
                    } catch {
                        // Log error but continue processing other deletions
                        NDKLogger.shared.log(.error, category: .cache, "Failed to delete event \(eventId) from cache: \(error.localizedDescription)")
                    }
                }
            } else {
                // Event not in cache yet - add to tombstone cache
                // This prevents the event from being added if it arrives later
                deletionTombstones[eventId] = now
                
                // Also try to delete it in case some cache implementations handle this
                do {
                    try await ndk.cache.deleteEvent(id: eventId)
                } catch {
                    // Silent fail - event might not exist
                }
            }
        }
    }

    // MARK: - Cleanup

    private func startPeriodicCleanup() async {
        while true {
            try? await Task.sleep(nanoseconds: 60 * TimeConstants.nanosecondsPerSecond) // 1 minute
            await performCleanup()
        }
    }

    private func performCleanup() async {
        let now = Timestamp.now
        let cutoff = now - Int64(deduplicationWindow)
        let tombstoneCutoff = now - Int64(tombstoneTTL)

        // Clean old event deduplication entries
        eventDeduplication = eventDeduplication.filter { _, timestamp in
            timestamp > cutoff
        }
        
        // Clean old deletion tombstones
        deletionTombstones = deletionTombstones.filter { _, timestamp in
            timestamp > tombstoneCutoff
        }

        // Clean closed subscriptions
        var closedSubscriptions: [(String, NDKSubscription)] = []
        for (id, subscription) in activeSubscriptions {
            if subscription.isClosed {
                closedSubscriptions.append((id, subscription))
            }
        }

        for (subscriptionId, _) in closedSubscriptions {
            removeSubscription(subscriptionId)
        }
    }
}
