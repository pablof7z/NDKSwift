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

    /// Cache usage strategy for subscriptions
    public enum CacheUsage {
        case onlyCache // Cache only, no relays
        case cacheFirst // Cache then relays if needed
        case parallel // Cache + relays simultaneously
        case onlyRelay // Skip cache entirely
    }

    /// Subscription execution plan
    struct ExecutionPlan {
        let subscriptions: [NDKSubscription]
        let mergedFilters: [NDKFilter]
        let relaySet: Set<NDKRelay>
        let cacheUsage: CacheUsage
        let closeOnEose: Bool
        let delay: TimeInterval
    }

    /// Filter fingerprint for grouping compatibility
    struct FilterFingerprint: Hashable {
        let kinds: Set<Int>?
        let authorsCount: Int
        let tagTypes: Set<String>
        let hasTimeConstraints: Bool
        let hasLimit: Bool
        let closeOnEose: Bool

        init(filter: NDKFilter, closeOnEose: Bool) {
            self.kinds = filter.kinds != nil ? Set(filter.kinds!) : nil
            self.authorsCount = filter.authors?.count ?? 0
            // Note: tagNames property doesn't exist in current NDKFilter, use empty set
            self.tagTypes = Set<String>()
            self.hasTimeConstraints = filter.since != nil || filter.until != nil
            self.hasLimit = filter.limit != nil
            self.closeOnEose = closeOnEose
        }
    }

    // MARK: - Properties

    private weak var ndk: NDK?
    private var activeSubscriptions: [String: NDKSubscription] = [:]
    private var subscriptionStates: [String: SubscriptionState] = [:]
    private var pendingGroups: [FilterFingerprint: PendingGroup] = [:]
    private var eventDeduplication: [EventID: Timestamp] = [:]
    private var eoseTracking: [String: EOSETracker] = [:]

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
        let targetRelays: Set<NDKRelay>
        var eosedRelays: Set<NDKRelay> = []
        var lastEventReceived: Date = .init()
        let createdAt: Date = .init()

        var eosePercentage: Double {
            guard !targetRelays.isEmpty else { return 1.0 }
            return Double(eosedRelays.count) / Double(targetRelays.count)
        }

        var shouldTimeout: Bool {
            let timeSinceLastEvent = Date().timeIntervalSince(lastEventReceived)
            let timeSinceCreation = Date().timeIntervalSince(createdAt)

            // Don't timeout too early or if we recently received events
            return eosePercentage >= 0.5 && timeSinceLastEvent > 0.02 && timeSinceCreation > 0.1
        }

        mutating func recordEose(from relay: NDKRelay) {
            eosedRelays.insert(relay)
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
                relayUrls: subscription.options.relays?.map { $0.url } ?? ndk.relays.map { $0.url }
            )
        }

        // Determine execution strategy
        if shouldGroupSubscription(subscription) {
            addToGrouping(subscription)
        } else {
            executeImmediately(subscription)
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
    public func processEvent(_ event: NDKEvent, from relay: NDKRelay) {
        guard let eventId = event.id else { return }

        // Check deduplication
        let now = Timestamp(Date().timeIntervalSince1970)
        let isUnique = eventDeduplication[eventId] == nil

        if !isUnique {
            // Already seen this event
            stats.eventsDeduped += 1
            return
        }

        eventDeduplication[eventId] = now

        // Find matching subscriptions and dispatch
        for (subscriptionId, subscription) in activeSubscriptions {
            if subscription.filters.contains(where: { $0.matches(event: event) }) {
                subscription.handleEvent(event, fromRelay: relay)

                // Track event received
                if let ndk = ndk {
                    Task {
                        await ndk.subscriptionTracker.trackEventReceived(
                            subscriptionId: subscriptionId,
                            eventId: eventId,
                            relayUrl: relay.url,
                            isUnique: isUnique
                        )
                    }
                }

                // Update EOSE tracking
                if var tracker = eoseTracking[subscriptionId] {
                    tracker.recordEvent()
                    eoseTracking[subscriptionId] = tracker
                }
            }
        }
    }

    /// Process EOSE from a relay
    public func processEOSE(subscriptionId: String, from relay: NDKRelay) {
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
        if tracker.eosedRelays.count == tracker.targetRelays.count || tracker.shouldTimeout {
            subscription.handleEOSE(fromRelay: relay)

            if subscription.options.closeOnEose {
                removeSubscription(subscriptionId)
            }
        }
    }

    /// Get current statistics
    public func getStats() -> SubscriptionStats {
        return stats
    }

    // MARK: - Grouping Logic

    private func shouldGroupSubscription(_ subscription: NDKSubscription) -> Bool {
        // Don't group if:
        // - Subscription has specific relays
        // - Has time constraints that make grouping unsafe
        // - Is cache-only
        // - Has a very small limit that shouldn't be shared

        guard subscription.options.relays == nil,
              subscription.options.cacheStrategy != .cacheOnly,
              subscription.options.limit == nil || subscription.options.limit! > 10
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

    private func addToGrouping(_ subscription: NDKSubscription) {
        subscriptionStates[subscription.id] = .grouping

        // Create fingerprint for grouping
        let fingerprint = createFingerprint(for: subscription)

        if var group = pendingGroups[fingerprint] {
            // Add to existing group
            group.addSubscription(subscription)
            pendingGroups[fingerprint] = group
        } else {
            // Create new group
            var group = PendingGroup()
            group.addSubscription(subscription)

            // Set timer to execute group
            group.timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(groupingDelay * 1_000_000_000))
                await executeGroup(fingerprint: fingerprint)
            }

            pendingGroups[fingerprint] = group
        }
    }

    private func createFingerprint(for subscription: NDKSubscription) -> FilterFingerprint {
        // For now, create fingerprint from first filter
        // In a more sophisticated implementation, we'd analyze all filters
        guard let firstFilter = subscription.filters.first else {
            return FilterFingerprint(filter: NDKFilter(), closeOnEose: subscription.options.closeOnEose)
        }

        return FilterFingerprint(filter: firstFilter, closeOnEose: subscription.options.closeOnEose)
    }

    private func executeGroup(fingerprint: FilterFingerprint) {
        guard var group = pendingGroups[fingerprint] else { return }

        pendingGroups.removeValue(forKey: fingerprint)
        group.cancel()

        guard !group.subscriptions.isEmpty else { return }

        // Create execution plan
        let plan = createExecutionPlan(for: group.subscriptions)

        // Execute the plan
        executeSubscriptionGroup(plan)

        // Update statistics
        stats.recordGrouping(originalCount: group.subscriptions.count, finalCount: plan.mergedFilters.count)
    }

    private func createExecutionPlan(for subscriptions: [NDKSubscription]) -> ExecutionPlan {
        // Merge compatible filters
        let mergedFilters = mergeFilters(from: subscriptions)

        // Determine relay set (use intersection of all subscription relay preferences)
        var relaySet: Set<NDKRelay> = []
        if let firstRelaySet = subscriptions.first?.options.relays {
            relaySet = firstRelaySet
            for subscription in subscriptions.dropFirst() {
                if let subRelaySet = subscription.options.relays {
                    relaySet = relaySet.intersection(subRelaySet)
                }
            }
        } else if let ndk = ndk {
            relaySet = Set(ndk.relays)
        }

        // Determine cache usage (most restrictive wins)
        let cacheUsage = subscriptions.map { $0.options.cacheStrategy }.min { a, b in
            cacheStrategyPriority(a) < cacheStrategyPriority(b)
        } ?? .cacheFirst

        // Determine close behavior (all must agree)
        let closeOnEose = subscriptions.allSatisfy { $0.options.closeOnEose }

        return ExecutionPlan(
            subscriptions: subscriptions,
            mergedFilters: mergedFilters,
            relaySet: relaySet,
            cacheUsage: cacheUsageFromStrategy(cacheUsage),
            closeOnEose: closeOnEose,
            delay: 0
        )
    }

    private func mergeFilters(from subscriptions: [NDKSubscription]) -> [NDKFilter] {
        var result: [NDKFilter] = []
        var processed: Set<String> = []

        for subscription in subscriptions {
            for filter in subscription.filters {
                let filterId = "\(filter.kinds ?? [])_\(filter.authors?.count ?? 0)" // Simple approach

                if !processed.contains(filterId) {
                    // Try to merge with existing filters
                    var merged = false
                    for i in 0 ..< result.count {
                        if let mergedFilter = result[i].merged(with: filter) {
                            result[i] = mergedFilter
                            merged = true
                            break
                        }
                    }

                    if !merged {
                        result.append(filter)
                    }

                    processed.insert(filterId)
                }
            }
        }

        // Respect maximum filters per request
        if result.count > maxFiltersPerRequest {
            result = Array(result.prefix(maxFiltersPerRequest))
        }

        return result
    }

    private func executeImmediately(_ subscription: NDKSubscription) {
        let plan = ExecutionPlan(
            subscriptions: [subscription],
            mergedFilters: subscription.filters,
            relaySet: subscription.options.relays ?? Set(ndk?.relays ?? []),
            cacheUsage: cacheUsageFromStrategy(subscription.options.cacheStrategy),
            closeOnEose: subscription.options.closeOnEose,
            delay: 0
        )

        executeSubscriptionGroup(plan)
    }

    private func executeSubscriptionGroup(_ plan: ExecutionPlan) {
        guard ndk != nil else { return }

        // Mark subscriptions as executing
        for subscription in plan.subscriptions {
            subscriptionStates[subscription.id] = .executing
        }

        // Setup EOSE tracking
        for subscription in plan.subscriptions {
            eoseTracking[subscription.id] = EOSETracker(targetRelays: plan.relaySet)
        }

        Task {
            // Handle cache first if needed
            if plan.cacheUsage == .cacheFirst || plan.cacheUsage == .parallel {
                await executeCacheQuery(plan)
            }

            // Execute relay queries if needed
            if plan.cacheUsage != .onlyCache {
                await executeRelayQueries(plan)
            }

            // Mark as active
            for subscription in plan.subscriptions {
                subscriptionStates[subscription.id] = .active
            }
        }
    }

    private func executeCacheQuery(_ plan: ExecutionPlan) async {
        guard let ndk = ndk, let cache = ndk.cacheAdapter else { return }

        for subscription in plan.subscriptions {
            let cachedEvents = await cache.query(subscription: subscription)

            for event in cachedEvents {
                subscription.handleEvent(event, fromRelay: nil)
            }

            // For cache-only, emit EOSE
            if plan.cacheUsage == .onlyCache {
                subscription.handleEOSE()
            }
        }
    }

    private func executeRelayQueries(_ plan: ExecutionPlan) async {
        guard ndk != nil else { return }

        // Create a single subscription ID for the group
        let groupSubscriptionId = plan.subscriptions.first?.id ?? UUID().uuidString

        for relay in plan.relaySet {
            await sendSubscriptionToRelay(
                relay: relay,
                subscriptionId: groupSubscriptionId,
                filters: plan.mergedFilters
            )
        }
    }

    private func sendSubscriptionToRelay(relay: NDKRelay, subscriptionId: String, filters: [NDKFilter]) async {
        guard relay.isConnected else {
            // TODO: Wait for connection
            return
        }

        do {
            let reqMessage = NostrMessage.req(subscriptionId: subscriptionId, filters: filters)
            try await relay.send(reqMessage.serialize())

            // Track subscription sent to relay
            if let ndk = ndk {
                for filter in filters {
                    await ndk.subscriptionTracker.trackSubscriptionSentToRelay(
                        subscriptionId: subscriptionId,
                        relayUrl: relay.url,
                        appliedFilter: filter
                    )
                }
            }
        } catch {
            // Handle relay error
            for subscription in activeSubscriptions.values {
                subscription.handleError(error)
            }
        }
    }

    // MARK: - Utilities

    private func cacheStrategyPriority(_ strategy: NDKCacheStrategy) -> Int {
        switch strategy {
        case .cacheOnly: return 0
        case .cacheFirst: return 1
        case .parallel: return 2
        case .relayOnly: return 3
        }
    }

    private func cacheUsageFromStrategy(_ strategy: NDKCacheStrategy) -> CacheUsage {
        switch strategy {
        case .cacheOnly: return .onlyCache
        case .cacheFirst: return .cacheFirst
        case .parallel: return .parallel
        case .relayOnly: return .onlyRelay
        }
    }

    // MARK: - Cleanup

    private func startPeriodicCleanup() async {
        while true {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 1 minute
            await performCleanup()
        }
    }

    private func performCleanup() {
        let now = Timestamp(Date().timeIntervalSince1970)
        let cutoff = now - Int64(deduplicationWindow)

        // Clean old event deduplication entries
        eventDeduplication = eventDeduplication.filter { _, timestamp in
            timestamp > cutoff
        }

        // Clean closed subscriptions
        let closedSubscriptions = activeSubscriptions.filter { _, subscription in
            subscription.isClosed
        }

        for (subscriptionId, _) in closedSubscriptions {
            removeSubscription(subscriptionId)
        }
    }
}
