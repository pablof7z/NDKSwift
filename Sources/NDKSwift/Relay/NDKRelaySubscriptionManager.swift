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
            mergedFilters = NDKRelaySubscriptionManager.mergeFilters(subscriptions)
        }

        /// Remove a subscription from this relay subscription
        mutating func removeSubscription(_ subscriptionId: String) {
            subscriptions.removeAll { $0.id == subscriptionId }
            if !subscriptions.isEmpty {
                // Re-merge filters after removal
                mergedFilters = NDKRelaySubscriptionManager.mergeFilters(subscriptions)
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
    /// Uses the same approach as NDKSubscriptionManager for consistency
    public struct FilterFingerprint: Hashable {
        let value: String
        
        init(filters: [NDKFilter], closeOnEose: Bool) {
            // Use the same fingerprint generation as NDKSubscriptionManager
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
    public func addSubscription(_ subscription: NDKSubscription, filters: [NDKFilter]) async -> String {
        guard enableGrouping else {
            // No grouping, create individual relay subscription
            return await createIndividualSubscription(subscription, filters: filters)
        }

        // Check if subscription can be grouped
        let options = await subscription.options
        let fingerprint = FilterFingerprint(filters: filters, closeOnEose: options.closeOnEose)

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
        return await createGroupedSubscription(subscription, filters: filters, fingerprint: fingerprint)
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
<<<<<<< HEAD
        #if DEBUG
        NDKLogger.shared.log(.debug, category: .subscription, "Handling EOSE for relay subscription: \(relaySubscriptionId)")
        NDKLogger.shared.log(.trace, category: .subscription, "Available relay subscriptions: \(Array(relaySubscriptions.keys))")
        #endif
        
        guard var relaySub = relaySubscriptions[relaySubscriptionId] else {
            #if DEBUG
            NDKLogger.shared.log(.warning, category: .subscription, "No relay subscription found for ID: \(relaySubscriptionId)")
            #endif
            return
        }

        #if DEBUG
        NDKLogger.shared.log(.debug, category: .subscription, "Found relay subscription with \(relaySub.subscriptions.count) subscriptions")
        #endif
=======
        NDKLogger.debug("SubscriptionManager: Handling EOSE for relay subscription: \(relaySubscriptionId)")
        NDKLogger.debug("Available relay subscriptions: \(Array(relaySubscriptions.keys))")
        
        guard var relaySub = relaySubscriptions[relaySubscriptionId] else {
            NDKLogger.debug("SubscriptionManager: No relay subscription found for ID: \(relaySubscriptionId)")
            return
        }

        NDKLogger.debug("SubscriptionManager: Found relay subscription with \(relaySub.subscriptions.count) subscriptions")
>>>>>>> 1708f88 (refactor: improve separation of concerns and standardize key generation)

        relaySub.status = .eoseReceived
        relaySubscriptions[relaySubscriptionId] = relaySub

        // Notify all subscriptions in this group
        for subscription in relaySub.subscriptions {
            #if DEBUG
            NDKLogger.shared.log(.debug, category: .subscription, "Notifying subscription \(subscription.id) of EOSE")
            #endif
            Task {
                await subscription.handleEOSE(fromRelay: relay)
            }

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
            NDKLogger.shared.log(.debug, category: .subscription, "Closing relay subscription \(relaySubscriptionId) (closeOnEose=true)")
            #endif
            closeRelaySubscription(relaySubscriptionId)

            // Remove subscriptions from tracking
            for subscription in relaySub.subscriptions {
                subscriptionIdToRelaySubscription.removeValue(forKey: subscription.id)
            }
        }
    }

    /// Handle event for routing to appropriate subscriptions
    public func handleEvent(_ event: NDKEvent, relaySubscriptionId: String?) async {
        let eventId = event.id

        #if DEBUG
        NDKLogger.shared.log(.debug, category: .subscription, "Handling event \(eventId) for relay subscription: \(relaySubscriptionId ?? "nil")")
        NDKLogger.shared.log(.trace, category: .subscription, "Available relay subscriptions: \(Array(relaySubscriptions.keys))")
        #endif

        // If we have a specific relay subscription ID, route only to those subscriptions
        if let relaySubId = relaySubscriptionId,
           let relaySub = relaySubscriptions[relaySubId] {
            #if DEBUG
            NDKLogger.shared.log(.debug, category: .subscription, "Found relay subscription with \(relaySub.subscriptions.count) subscriptions")
            #endif
            
            for subscription in relaySub.subscriptions {
                var matches = false
                for filter in subscription.filters {
                    if filter.matches(event: event) {
                        matches = true
                        break
                    }
                }
                #if DEBUG
                NDKLogger.shared.log(.trace, category: .subscription, "Subscription \(subscription.id) matches: \(matches)")
                #endif
                
                if matches {
                    #if DEBUG
                    NDKLogger.shared.log(.debug, category: .subscription, "Notifying subscription \(subscription.id) of event")
                    #endif
                    Task {
                        await subscription.handleEvent(event, fromRelay: relay)
                    }

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
            NDKLogger.shared.log(.debug, category: .subscription, "No specific relay subscription ID, routing to all matching subscriptions")
            #endif
            
            // Route to all matching subscriptions
            for relaySub in relaySubscriptions.values {
                if relaySub.status == .running || relaySub.status == .eoseReceived {
                    for subscription in relaySub.subscriptions {
                        var matches = false
                        for filter in subscription.filters {
                            if filter.matches(event: event) {
                                matches = true
                                break
                            }
                        }
                        if matches {
                            Task {
                                await subscription.handleEvent(event, fromRelay: relay)
                            }

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

    private func createIndividualSubscription(_ subscription: NDKSubscription, filters: [NDKFilter]) async -> String {
        // Use subscription ID as the relay sub ID for wire protocol, but make it unique per relay
        let relaySubId = subscription.id
        let relaySub = RelaySubscription(
            id: relaySubId,
            subscriptions: [subscription],
            mergedFilters: filters,
            closeOnEose: await subscription.options.closeOnEose,
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

    private func createGroupedSubscription(_ subscription: NDKSubscription, filters: [NDKFilter], fingerprint: FilterFingerprint) async -> String {
        let relaySubId = subscription.id // Use the subscription's own ID for now
        var relaySub = RelaySubscription(
            id: relaySubId,
            subscriptions: [],
            mergedFilters: [],
            closeOnEose: await subscription.options.closeOnEose,
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
        if !(await relay.isConnected) {
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
            let serialized = try reqMessage.serialize()
            
            // Log the raw filter being sent
            if let ndk = relay.ndk, ndk.debugMode {
                NDKLogger.shared.log(.debug, category: .subscription, "Sending subscription \(relaySubId) to relay \(relay.url):")
                NDKLogger.shared.log(.trace, category: .subscription, "Raw filter: \(serialized)")
            }
            
            try await relay.send(serialized)

            // Register subscription with relay
            for subscription in relaySub.subscriptions {
                await relay.addSubscription(subscription)

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
                Task {
                    subscription.handleError(error)
                }
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
            let serialized = try reqMessage.serialize()
            
            // Log the updated filter being sent
            if let ndk = relay.ndk, ndk.debugMode {
                NDKLogger.shared.log(.debug, category: .subscription, "Updating subscription \(relaySubId) on relay \(relay.url):")
                NDKLogger.shared.log(.trace, category: .subscription, "Raw filter: \(serialized)")
            }
            
            try await relay.send(serialized)
        } catch {
            for subscription in relaySub.subscriptions {
                Task {
                    subscription.handleError(error)
                }
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
        await relay.observeConnectionState { [weak self] state in
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

    /// Merge filters from multiple subscriptions using the same logic as NDKSubscriptionManager
    static func mergeFilters(_ subscriptions: [NDKSubscription]) -> [NDKFilter] {
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
        
        return result
    }
    
    /// Merge filters without limits using union semantics
    private static func mergeUnlimitedFilters(_ filters: [NDKFilter]) -> NDKFilter? {
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
}
