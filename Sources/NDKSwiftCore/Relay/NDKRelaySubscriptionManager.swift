import Foundation

/// The subscription manager of an NDKRelay is in charge of orchestrating the subscriptions
/// that are created and closed in a given relay.
///
/// The manager is responsible for:
/// * Grouping similar subscriptions to be compiled into individual REQs
/// * Scheduling grouped subscriptions with appropriate delays
/// * Managing subscription lifecycle on the relay
actor NDKRelaySubscriptionManager {
    private weak var relay: NDKRelay?
    private var subscriptionGroups: [String: NDKRelaySubscription] = [:]
    /// Maps subscription IDs to their groups for event routing
    private var subscriptionIdToGroup: [String: NDKRelaySubscription] = [:]

    init(relay: NDKRelay?) {
        self.relay = relay
    }

    /// Sets the relay reference (called after initialization to break init cycle)
    func setRelay(_ relay: NDKRelay) {
        self.relay = relay
    }

    /// Adds a subscription to the manager
    func addSubscription(_ subscription: NDKSubscriptionCoordinator, filters: [NDKFilter]) async {
        guard let relay = relay else { return }

        // Start telemetry span
        let ndk = await relay.ndk
        let span = ndk?.startSpan("subscription.add", category: .subscriptionGrouping)
        span?.set(SpanAttributes.relayUrl, relay.url)
        span?.set(SpanAttributes.subscriptionGroupable, subscription.isGroupable)
        span?.set(SpanAttributes.subscriptionCloseOnEose, subscription.closeOnEose)
        defer { span?.end() }

        // Record subscription in metrics
        await NDKSubscriptionMetrics.recordSubscription(isGroupable: subscription.isGroupable)

        if !subscription.isGroupable {
            // Non-groupable subscriptions execute immediately
            span?.set(SpanAttributes.decisionReason, "not_groupable")
            span?.addEvent("immediate_execution", attributes: nil)

            let group = NDKRelaySubscription(
                relay: relay,
                fingerprint: UUID().uuidString,
                isGroupable: false
            )
            await group.addItem(subscription, filters: filters)
            subscriptionGroups[group.fingerprint] = group
            await group.execute()
            span?.success()
        } else {
            // Calculate fingerprint for groupable subscriptions
            let fingerprint = NDKFilterGrouping.filterFingerprint(
                filters,
                closeOnEose: subscription.closeOnEose
            )
            span?.set(SpanAttributes.subscriptionFingerprint, fingerprint)

            // Find existing group or create new one
            if let existingGroup = subscriptionGroups[fingerprint],
               await existingGroup.canAcceptNewItems()
            {
                // Grouped with existing subscription!
                let groupSize = await existingGroup.itemCount
                span?.set(SpanAttributes.groupId, fingerprint)
                span?.set(SpanAttributes.groupSize, groupSize + 1)
                span?.set(SpanAttributes.groupMerged, true)
                span?.addEvent("merged_with_existing_group", attributes: [
                    "prior_group_size": .int(groupSize)
                ])

                await existingGroup.addItem(subscription, filters: filters)
                // Record that this subscription was grouped
                await NDKSubscriptionMetrics.recordGroupedSubscription()
                span?.success()
            } else {
                // Creating new group
                span?.set(SpanAttributes.groupId, fingerprint)
                span?.set(SpanAttributes.groupMerged, false)

                let newGroup = NDKRelaySubscription(
                    relay: relay,
                    fingerprint: fingerprint,
                    isGroupable: true
                )
                await newGroup.addItem(subscription, filters: filters)
                subscriptionGroups[fingerprint] = newGroup

                // Schedule execution with delay
                // Note: These properties are nonisolated on NDKSubscriptionCoordinator
                let delay = subscription.groupableDelay ?? 0.1
                let delayType = subscription.groupableDelayType ?? .atMost
                span?.set("grouping_delay_ms", delay * 1000)
                span?.set("grouping_delay_type", delayType == .atMost ? "at_most" : "at_least")
                span?.addEvent("scheduled_execution", attributes: [
                    "delay_ms": .double(delay * 1000)
                ])

                await newGroup.scheduleExecution(
                    delay: delay,
                    delayType: delayType
                )
                span?.success()
            }
        }
    }

    /// Removes a subscription from the manager
    func removeSubscription(_ subscription: NDKSubscriptionCoordinator) async {
        for (fingerprint, group) in subscriptionGroups {
            let wasRemoved = await group.removeItem(subscription)
            if wasRemoved {
                let isEmpty = await group.isEmpty()
                if isEmpty {
                    subscriptionGroups.removeValue(forKey: fingerprint)
                }
                break
            }
        }
    }

    /// Called when a group closes
    func onGroupClosed(_ group: NDKRelaySubscription) async {
        subscriptionGroups.removeValue(forKey: group.fingerprint)
        // Remove from subscription ID mapping
        if let subId = await group.subId {
            subscriptionIdToGroup.removeValue(forKey: subId)
            NDKLogger.log(.debug, category: .subscription,
                          "🗑️ [SubManager] Removed subscription ID '\(subId)' for closed group '\(group.fingerprint)'")
        }
    }

    /// Called when a group starts executing (to track subscription ID)
    func trackGroupSubscriptionId(_ group: NDKRelaySubscription) async {
        if let subId = await group.subId {
            subscriptionIdToGroup[subId] = group
            NDKLogger.log(.debug, category: .subscription,
                          "📋 [SubManager] Tracking subscription ID '\(subId)' for group '\(group.fingerprint)'")
        }
    }

    /// Route an incoming event to the appropriate group
    func routeEvent(_ event: NDKEvent, subscriptionId: String, from relay: NDKRelay) async {
        // Start telemetry span for event routing
        let ndk = await relay.ndk
        let span = ndk?.startSpan("event.route", category: .eventRouting)
        span?.set(SpanAttributes.eventId, event.id)
        span?.set(SpanAttributes.eventKind, event.kind)
        span?.set(SpanAttributes.subscriptionId, subscriptionId)
        span?.set(SpanAttributes.relayUrl, relay.url)
        defer { span?.end() }

        guard let group = subscriptionIdToGroup[subscriptionId] else {
            span?.set(SpanAttributes.decisionOutcome, "no_group_found")
            span?.setStatus(.error("No group found for subscription"))
            NDKLogger.log(.warning, category: .subscription,
                          "⚠️ No group found for subscription \(subscriptionId)")
            return
        }

        span?.set(SpanAttributes.subscriptionFingerprint, group.fingerprint)
        span?.set(SpanAttributes.decisionOutcome, "routed")
        span?.success()

        await group.handleEvent(event, from: relay)
    }

    /// Route EOSE to the appropriate group
    func routeEOSE(subscriptionId: String) async {
        guard let group = subscriptionIdToGroup[subscriptionId] else {
            // Could be an old subscription
            return
        }

        await group.handleEOSE(subscriptionId: subscriptionId)
    }

    /// Route CLOSED to the appropriate group
    func routeClosed(subscriptionId: String, message: String) async {
        guard let group = subscriptionIdToGroup[subscriptionId] else {
            return
        }

        await group.handleClosed(subscriptionId: subscriptionId, message: message)
    }

    /// Handles relay disconnection
    func handleRelayDisconnection() async {
        // Cancel all pending executions
        for group in subscriptionGroups.values {
            await group.cancelPendingExecution()
        }
    }

    /// Handles relay reconnection
    func handleRelayReconnection() async {
        // Re-execute all active groups
        for group in subscriptionGroups.values {
            if await group.isActive() {
                await group.execute()
            }
        }
    }
}

// MARK: - Testing Support

#if DEBUG
    extension NDKRelaySubscriptionManager {
        /// Get current grouping state for testing
        func debugGroupingState() async -> [String: [String]] {
            var state: [String: [String]] = [:]
            for (fingerprint, group) in subscriptionGroups {
                // Get subscription IDs from the group
                let subscriptionIds = await group.getSubscriptionIds()
                state[fingerprint] = subscriptionIds
            }
            return state
        }

        /// Get count of active subscription groups
        func debugGroupCount() async -> Int {
            subscriptionGroups.count
        }

        /// Force immediate execution of all pending groups (for testing)
        func flushPendingGroups() async {
            for group in subscriptionGroups.values {
                await group.executeNow()
            }
        }

        /// Get detailed information about a specific group
        func debugInspectGroup(fingerprint: String) async -> GroupInspectionData? {
            guard let group = subscriptionGroups[fingerprint] else { return nil }
            return await group.inspectForTesting()
        }

        /// Debug information about a subscription group
        struct GroupInspectionData: Sendable {
            public let fingerprint: String
            public let isGroupable: Bool
            public let itemCount: Int
            public let status: String
            public let subId: String?
        }
    }
#endif
