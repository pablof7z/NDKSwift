import Foundation

/// Manages subscriptions at the relay level with filter merging and reconnection support
public actor NDKRelaySubscriptionManager {
    // MARK: - Types

    /// Represents a relay-level subscription that can contain multiple NDKSubscriptions
    public struct RelaySubscription {
        let id: String
        var subscriptions: [NDKSubscription] = []
        var mergedFilters: [NDKFilter]
        let closeOnEose: Bool
        var status: RelaySubscriptionStatus = .initial
        var lastExecuted: Date?

        /// Add a subscription to this relay subscription
        mutating func addSubscription(_ subscription: NDKSubscription, filters _: [NDKFilter]) {
            subscriptions.append(subscription)
            // Re-merge filters when adding new subscription
            mergedFilters = NDKRelaySubscriptionManager.mergeAllFilters(
                from: subscriptions.map { ($0, $0.filters) }
            )
        }

        /// Remove a subscription from this relay subscription
        mutating func removeSubscription(_ subscriptionId: String) {
            subscriptions.removeAll { $0.id == subscriptionId }
            if !subscriptions.isEmpty {
                // Re-merge filters after removal
                mergedFilters = NDKRelaySubscriptionManager.mergeAllFilters(
                    from: subscriptions.map { ($0, $0.filters) }
                )
            }
        }

        /// Check if this relay subscription should be closed
        var shouldClose: Bool {
            return subscriptions.isEmpty || (closeOnEose && status == .eoseReceived)
        }
    }

    /// Status of a relay subscription
    public enum RelaySubscriptionStatus {
        case initial
        case pending
        case waiting // Waiting for relay to be ready
        case running
        case eoseReceived
        case closed
    }

    /// Filter fingerprint for grouping
    public struct FilterFingerprint: Hashable {
        let kinds: String
        let authorsPresent: Bool
        let tagKeys: String
        let hasLimit: Bool
        let hasTimeConstraints: Bool
        let closeOnEose: Bool

        init(filters: [NDKFilter], closeOnEose: Bool) {
            // Sort kinds for consistent fingerprinting
            let allKinds = filters.compactMap { $0.kinds }.flatMap { $0 }.sorted()
            self.kinds = allKinds.isEmpty ? "all" : allKinds.map { String($0) }.joined(separator: ",")

            self.authorsPresent = filters.contains { $0.authors != nil && !$0.authors!.isEmpty }

            // Extract tag keys from filters
            let tagKeys = filters.compactMap { filter -> [String]? in
                guard let tags = filter.tags else { return nil }
                return Array(tags.keys).sorted()
            }.flatMap { $0 }
            self.tagKeys = tagKeys.isEmpty ? "" : tagKeys.joined(separator: ",")

            self.hasLimit = filters.contains { $0.limit != nil }
            self.hasTimeConstraints = filters.contains { $0.since != nil || $0.until != nil }
            self.closeOnEose = closeOnEose
        }
    }

    // MARK: - Properties

    private weak var relay: NDKRelay?

    /// Map of fingerprint to relay subscriptions for grouping
    private var subscriptionsByFingerprint: [FilterFingerprint: [RelaySubscription]] = [:]

    /// Map of subscription ID to relay subscription for quick lookup
    private var subscriptionIdToRelaySubscription: [String: String] = [:]

    /// All relay subscriptions by ID
    private var relaySubscriptions: [String: RelaySubscription] = [:]

    /// Whether to enable subscription grouping
    private let enableGrouping: Bool = true

    /// Maximum filters per subscription request
    private let maxFiltersPerRequest: Int = 10

    // MARK: - Initialization

    public init(relay: NDKRelay) {
        self.relay = relay

        // Observe relay connection state for replay
        Task {
            await observeRelayConnection()
        }
    }

    // MARK: - Public Interface

    /// Add a subscription to be managed
    public func addSubscription(_ subscription: NDKSubscription, filters: [NDKFilter]) -> String {
        guard enableGrouping else {
            // No grouping, create individual relay subscription
            return createIndividualSubscription(subscription, filters: filters)
        }

        // Check if subscription can be grouped
        let fingerprint = FilterFingerprint(filters: filters, closeOnEose: subscription.options.closeOnEose)

        // Find existing relay subscription that can accept this subscription
        if let existingSubscriptions = subscriptionsByFingerprint[fingerprint] {
            for var relaySub in existingSubscriptions {
                if relaySub.status == .initial || relaySub.status == .pending {
                    // Can add to this subscription
                    relaySub.addSubscription(subscription, filters: filters)
                    relaySubscriptions[relaySub.id] = relaySub
                    subscriptionIdToRelaySubscription[subscription.id] = relaySub.id
                    return relaySub.id
                }
            }
        }

        // Create new relay subscription
        return createGroupedSubscription(subscription, filters: filters, fingerprint: fingerprint)
    }

    /// Remove a subscription
    public func removeSubscription(_ subscriptionId: String) {
        guard let relaySubId = subscriptionIdToRelaySubscription[subscriptionId],
              var relaySub = relaySubscriptions[relaySubId] else { return }

        relaySub.removeSubscription(subscriptionId)
        subscriptionIdToRelaySubscription.removeValue(forKey: subscriptionId)

        if relaySub.shouldClose {
            // Close and remove relay subscription
            closeRelaySubscription(relaySubId)
        } else {
            // Update with modified filters
            relaySubscriptions[relaySubId] = relaySub

            // If running, send updated filters to relay
            if relaySub.status == .running {
                Task {
                    await updateSubscriptionFilters(relaySubId)
                }
            }
        }
    }

    /// Execute all pending subscriptions
    public func executePendingSubscriptions() async {
        let pending = relaySubscriptions.values.filter { $0.status == .pending || $0.status == .waiting }

        for relaySub in pending {
            await executeRelaySubscription(relaySub.id)
        }
    }

    /// Get all active subscription IDs
    public func getActiveSubscriptionIds() -> [String] {
        return relaySubscriptions.values
            .filter { $0.status == .running }
            .map { $0.id }
    }

    /// Handle EOSE for a relay subscription
    public func handleEOSE(relaySubscriptionId: String) {
        #if DEBUG
        print("🔍 SubscriptionManager: Handling EOSE for relay subscription: \(relaySubscriptionId)")
        print("   Available relay subscriptions: \(Array(relaySubscriptions.keys))")
        #endif
        
        guard var relaySub = relaySubscriptions[relaySubscriptionId] else {
            #if DEBUG
            print("❌ SubscriptionManager: No relay subscription found for ID: \(relaySubscriptionId)")
            #endif
            return
        }

        #if DEBUG
        print("✅ SubscriptionManager: Found relay subscription with \(relaySub.subscriptions.count) subscriptions")
        #endif

        relaySub.status = .eoseReceived
        relaySubscriptions[relaySubscriptionId] = relaySub

        // Notify all subscriptions in this group
        for subscription in relaySub.subscriptions {
            #if DEBUG
            print("📤 SubscriptionManager: Notifying subscription \(subscription.id) of EOSE")
            #endif
            subscription.handleEOSE(fromRelay: relay)

            // Track EOSE received
            if let ndk = relay?.ndk {
                Task {
                    await ndk.subscriptionTracker.trackEoseReceived(
                        subscriptionId: subscription.id,
                        relayUrl: relay?.url ?? ""
                    )
                }
            }
        }

        // Close if all subscriptions want closeOnEose
        if relaySub.closeOnEose {
            #if DEBUG
            print("🔒 SubscriptionManager: Closing relay subscription \(relaySubscriptionId) (closeOnEose=true)")
            #endif
            closeRelaySubscription(relaySubscriptionId)

            // Remove subscriptions from tracking
            for subscription in relaySub.subscriptions {
                subscriptionIdToRelaySubscription.removeValue(forKey: subscription.id)
            }
        }
    }

    /// Handle event for routing to appropriate subscriptions
    public func handleEvent(_ event: NDKEvent, relaySubscriptionId: String?) {
        guard let eventId = event.id else { return }

        #if DEBUG
        print("🔍 SubscriptionManager: Handling event \(eventId) for relay subscription: \(relaySubscriptionId ?? "nil")")
        print("   Available relay subscriptions: \(Array(relaySubscriptions.keys))")
        #endif

        // If we have a specific relay subscription ID, route only to those subscriptions
        if let relaySubId = relaySubscriptionId,
           let relaySub = relaySubscriptions[relaySubId]
        {
            #if DEBUG
            print("✅ SubscriptionManager: Found relay subscription with \(relaySub.subscriptions.count) subscriptions")
            #endif
            
            for subscription in relaySub.subscriptions {
                let matches = subscription.filters.contains(where: { $0.matches(event: event) })
                #if DEBUG
                print("🔍 SubscriptionManager: Subscription \(subscription.id) matches: \(matches)")
                #endif
                
                if matches {
                    #if DEBUG
                    print("📤 SubscriptionManager: Notifying subscription \(subscription.id) of event")
                    #endif
                    subscription.handleEvent(event, fromRelay: relay)

                    // Track event received
                    if let ndk = relay?.ndk {
                        Task {
                            await ndk.subscriptionTracker.trackEventReceived(
                                subscriptionId: subscription.id,
                                eventId: eventId,
                                relayUrl: relay?.url ?? "",
                                isUnique: true // NDKSubscriptionManager handles deduplication
                            )
                        }
                    }
                }
            }
        } else {
            #if DEBUG
            print("🔍 SubscriptionManager: No specific relay subscription ID, routing to all matching subscriptions")
            #endif
            
            // Route to all matching subscriptions
            for relaySub in relaySubscriptions.values {
                if relaySub.status == .running || relaySub.status == .eoseReceived {
                    for subscription in relaySub.subscriptions {
                        if subscription.filters.contains(where: { $0.matches(event: event) }) {
                            subscription.handleEvent(event, fromRelay: relay)

                            // Track event received
                            if let ndk = relay?.ndk {
                                Task {
                                    await ndk.subscriptionTracker.trackEventReceived(
                                        subscriptionId: subscription.id,
                                        eventId: eventId,
                                        relayUrl: relay?.url ?? "",
                                        isUnique: true // NDKSubscriptionManager handles deduplication
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private Implementation

    private func createIndividualSubscription(_ subscription: NDKSubscription, filters: [NDKFilter]) -> String {
        // Use subscription ID as the relay sub ID for wire protocol, but make it unique per relay
        let relaySubId = subscription.id
        let relaySub = RelaySubscription(
            id: relaySubId,
            subscriptions: [subscription],
            mergedFilters: filters,
            closeOnEose: subscription.options.closeOnEose,
            status: .pending
        )

        relaySubscriptions[relaySubId] = relaySub
        subscriptionIdToRelaySubscription[subscription.id] = relaySubId

        // Execute immediately
        Task {
            await executeRelaySubscription(relaySubId)
        }

        return relaySubId
    }

    private func createGroupedSubscription(_ subscription: NDKSubscription, filters: [NDKFilter], fingerprint: FilterFingerprint) -> String {
        let relaySubId = subscription.id // Use the subscription's own ID for now
        var relaySub = RelaySubscription(
            id: relaySubId,
            subscriptions: [],
            mergedFilters: [],
            closeOnEose: subscription.options.closeOnEose,
            status: .pending
        )

        relaySub.addSubscription(subscription, filters: filters)

        relaySubscriptions[relaySubId] = relaySub
        subscriptionIdToRelaySubscription[subscription.id] = relaySubId

        // Add to fingerprint map
        if subscriptionsByFingerprint[fingerprint] == nil {
            subscriptionsByFingerprint[fingerprint] = []
        }
        subscriptionsByFingerprint[fingerprint]?.append(relaySub)

        // Execute immediately to avoid race conditions
        Task {
            await executeRelaySubscription(relaySubId)
        }

        return relaySubId
    }

    private func executeRelaySubscription(_ relaySubId: String) async {
        guard var relaySub = relaySubscriptions[relaySubId],
              let relay = relay else { return }

        // Check relay connection
        if !relay.isConnected {
            relaySub.status = .waiting
            relaySubscriptions[relaySubId] = relaySub
            return
        }

        // Don't re-execute if already running
        if relaySub.status == .running {
            return
        }

        relaySub.status = .running
        relaySub.lastExecuted = Date()
        relaySubscriptions[relaySubId] = relaySub

        // Send subscription to relay
        do {
            let reqMessage = NostrMessage.req(subscriptionId: relaySubId, filters: relaySub.mergedFilters)
            try await relay.send(reqMessage.serialize())

            // Register subscription with relay
            for subscription in relaySub.subscriptions {
                relay.addSubscription(subscription)

                // Track subscription sent to relay with actual filters
                if let ndk = relay.ndk {
                    for filter in relaySub.mergedFilters {
                        await ndk.subscriptionTracker.trackSubscriptionSentToRelay(
                            subscriptionId: subscription.id,
                            relayUrl: relay.url,
                            appliedFilter: filter
                        )
                    }
                }
            }
        } catch {
            // Handle error
            relaySub.status = .initial
            relaySubscriptions[relaySubId] = relaySub

            for subscription in relaySub.subscriptions {
                subscription.handleError(error)
            }
        }
    }

    private func updateSubscriptionFilters(_ relaySubId: String) async {
        guard let relaySub = relaySubscriptions[relaySubId],
              let relay = relay,
              relaySub.status == .running else { return }

        // Close old subscription
        do {
            let closeMessage = NostrMessage.close(subscriptionId: relaySubId)
            try await relay.send(closeMessage.serialize())
        } catch {
            // Ignore close errors
        }

        // Send new subscription with updated filters
        do {
            let reqMessage = NostrMessage.req(subscriptionId: relaySubId, filters: relaySub.mergedFilters)
            try await relay.send(reqMessage.serialize())
        } catch {
            for subscription in relaySub.subscriptions {
                subscription.handleError(error)
            }
        }
    }

    private func closeRelaySubscription(_ relaySubId: String) {
        guard var relaySub = relaySubscriptions.removeValue(forKey: relaySubId),
              let relay = relay else { return }

        relaySub.status = .closed

        // Remove from fingerprint map
        let fingerprint = FilterFingerprint(filters: relaySub.mergedFilters, closeOnEose: relaySub.closeOnEose)
        subscriptionsByFingerprint[fingerprint]?.removeAll { $0.id == relaySubId }

        // Send close message to relay
        Task {
            do {
                let closeMessage = NostrMessage.close(subscriptionId: relaySubId)
                try await relay.send(closeMessage.serialize())
            } catch {
                // Ignore close errors
            }
        }
    }

    // MARK: - Relay Connection Observation

    private func observeRelayConnection() async {
        guard let relay = relay else { return }

        // Monitor connection state changes
        relay.observeConnectionState { [weak self] state in
            guard let self = self else { return }

            Task {
                await self.handleConnectionStateChange(state)
            }
        }
    }

    private func handleConnectionStateChange(_ state: NDKRelayConnectionState) async {
        switch state {
        case .connected:
            // Replay waiting subscriptions
            await replayWaitingSubscriptions()
        case .disconnected, .failed:
            // Mark running subscriptions as waiting
            await markSubscriptionsAsWaiting()
        default:
            break
        }
    }

    private func replayWaitingSubscriptions() async {
        let waiting = relaySubscriptions.values.filter { $0.status == .waiting }

        for relaySub in waiting {
            await executeRelaySubscription(relaySub.id)
        }
    }

    private func markSubscriptionsAsWaiting() async {
        for (id, var relaySub) in relaySubscriptions {
            if relaySub.status == .running {
                relaySub.status = .waiting
                relaySubscriptions[id] = relaySub
            }
        }
    }

    // MARK: - Filter Merging

    /// Merge filters from multiple subscriptions
    static func mergeAllFilters(from subscriptions: [(NDKSubscription, [NDKFilter])]) -> [NDKFilter] {
        var mergedFilters: [NDKFilter] = []
        var filtersWithLimits: [NDKFilter] = []
        var filtersWithoutLimits: [NDKFilter] = []

        // Separate filters with and without limits
        for (_, filters) in subscriptions {
            for filter in filters {
                if filter.limit != nil {
                    filtersWithLimits.append(filter)
                } else {
                    filtersWithoutLimits.append(filter)
                }
            }
        }

        // Filters with limits are not merged
        mergedFilters.append(contentsOf: filtersWithLimits)

        // Merge filters without limits
        if !filtersWithoutLimits.isEmpty {
            let merged = mergeFiltersWithoutLimits(filtersWithoutLimits)
            mergedFilters.append(merged)
        }

        return mergedFilters
    }

    /// Merge filters that don't have limits
    private static func mergeFiltersWithoutLimits(_ filters: [NDKFilter]) -> NDKFilter {
        var merged = NDKFilter()

        // Merge kinds
        let allKinds = filters.compactMap { $0.kinds }.flatMap { $0 }
        if !allKinds.isEmpty {
            merged.kinds = Array(Set(allKinds)).sorted()
        }

        // Merge authors
        let allAuthors = filters.compactMap { $0.authors }.flatMap { $0 }
        if !allAuthors.isEmpty {
            merged.authors = Array(Set(allAuthors))
        }

        // Merge IDs
        let allIds = filters.compactMap { $0.ids }.flatMap { $0 }
        if !allIds.isEmpty {
            merged.ids = Array(Set(allIds))
        }

        // Merge tags
        var mergedTags: [String: [String]] = [:]
        for filter in filters {
            if let tags = filter.tags {
                for (key, values) in tags {
                    if mergedTags[key] == nil {
                        mergedTags[key] = []
                    }
                    mergedTags[key]?.append(contentsOf: values)
                }
            }
        }

        // Convert merged tags to proper format and add to filter
        for (tagName, values) in mergedTags {
            merged.addTagFilter(tagName, values: Array(Set(values)))
        }

        // Handle time constraints (use most restrictive)
        let sinceValues = filters.compactMap { $0.since }
        if !sinceValues.isEmpty {
            merged.since = sinceValues.max() // Most recent since
        }

        let untilValues = filters.compactMap { $0.until }
        if !untilValues.isEmpty {
            merged.until = untilValues.min() // Earliest until
        }

        return merged
    }
}
