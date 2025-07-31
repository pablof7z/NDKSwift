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
    
    init(relay: NDKRelay) {
        self.relay = relay
    }
    
    /// Adds a subscription to the manager
    func addSubscription(_ subscription: NDKSubscriptionCoordinator, filters: [NDKFilter]) async {
        guard let relay = relay else { return }
        
        if !subscription.isGroupable {
            // Non-groupable subscriptions execute immediately
            let group = NDKRelaySubscription(
                relay: relay,
                fingerprint: UUID().uuidString,
                isGroupable: false
            )
            await group.addItem(subscription, filters: filters)
            subscriptionGroups[group.fingerprint] = group
            await group.execute()
        } else {
            // Calculate fingerprint for groupable subscriptions
            let fingerprint = NDKFilterGrouping.filterFingerprint(
                filters,
                closeOnEose: subscription.closeOnEose
            )
            
            // Find existing group or create new one
            if let existingGroup = subscriptionGroups[fingerprint],
               await existingGroup.canAcceptNewItems() {
                await existingGroup.addItem(subscription, filters: filters)
            } else {
                let newGroup = NDKRelaySubscription(
                    relay: relay,
                    fingerprint: fingerprint,
                    isGroupable: true
                )
                await newGroup.addItem(subscription, filters: filters)
                subscriptionGroups[fingerprint] = newGroup
                
                // Schedule execution with delay
                let delay = subscription.groupableDelay ?? 0.1
                let delayType = subscription.groupableDelayType ?? .atMost
                await newGroup.scheduleExecution(
                    delay: delay,
                    delayType: delayType
                )
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
        guard let group = subscriptionIdToGroup[subscriptionId] else {
            NDKLogger.log(.warning, category: .subscription,
                         "⚠️ No group found for subscription \(subscriptionId)")
            return
        }
        
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