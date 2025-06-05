import Foundation

/// Tracks subscription metrics and history for debugging and monitoring
public actor NDKSubscriptionTracker {
    // MARK: - Properties

    /// Active subscription details keyed by subscription ID
    private var activeSubscriptions: [String: NDKSubscriptionDetail] = [:]

    /// Closed subscription history (limited by maxClosedSubscriptions)
    private var closedSubscriptions: [NDKClosedSubscription] = []

    /// Maximum number of closed subscriptions to remember
    private let maxClosedSubscriptions: Int

    /// Whether to track closed subscriptions
    private let trackClosedSubscriptions: Bool

    /// Cache for global statistics to avoid recalculation
    private var cachedStatistics: NDKSubscriptionStatistics?

    // MARK: - Initialization

    public init(trackClosedSubscriptions: Bool = false, maxClosedSubscriptions: Int = 100) {
        self.trackClosedSubscriptions = trackClosedSubscriptions
        self.maxClosedSubscriptions = maxClosedSubscriptions
    }

    // MARK: - Subscription Lifecycle

    /// Registers a new subscription for tracking
    public func trackSubscription(
        _ subscription: NDKSubscription,
        filter: NDKFilter,
        relayUrls _: [String]
    ) {
        let detail = NDKSubscriptionDetail(
            subscriptionId: subscription.id,
            originalFilter: filter
        )

        activeSubscriptions[subscription.id] = detail
        invalidateStatisticsCache()
    }

    /// Records that a subscription has been sent to a specific relay
    public func trackSubscriptionSentToRelay(
        subscriptionId: String,
        relayUrl: String,
        appliedFilter: NDKFilter
    ) {
        guard var detail = activeSubscriptions[subscriptionId] else { return }

        let relayMetrics = NDKRelaySubscriptionMetrics(
            relayUrl: relayUrl,
            appliedFilter: appliedFilter
        )

        detail.relayMetrics[relayUrl] = relayMetrics
        detail.metrics.activeRelayCount = detail.relayMetrics.count

        activeSubscriptions[subscriptionId] = detail
        invalidateStatisticsCache()
    }

    /// Records that an event was received for a subscription from a specific relay
    public func trackEventReceived(
        subscriptionId: String,
        eventId _: String,
        relayUrl: String,
        isUnique: Bool
    ) {
        guard var detail = activeSubscriptions[subscriptionId] else { return }

        // Update relay-specific metrics
        if var relayMetrics = detail.relayMetrics[relayUrl] {
            relayMetrics.eventsReceived += 1
            detail.relayMetrics[relayUrl] = relayMetrics
        }

        // Update overall metrics
        detail.metrics.totalEvents += 1
        if isUnique {
            detail.metrics.totalUniqueEvents += 1
        }

        activeSubscriptions[subscriptionId] = detail
        invalidateStatisticsCache()
    }

    /// Records that EOSE was received from a relay
    public func trackEoseReceived(subscriptionId: String, relayUrl: String) {
        guard var detail = activeSubscriptions[subscriptionId] else { return }

        if var relayMetrics = detail.relayMetrics[relayUrl] {
            relayMetrics.eoseReceived = true
            relayMetrics.eoseTime = Date()
            detail.relayMetrics[relayUrl] = relayMetrics
        }

        activeSubscriptions[subscriptionId] = detail
    }

    /// Marks a subscription as closed
    public func closeSubscription(_ subscriptionId: String) {
        guard var detail = activeSubscriptions.removeValue(forKey: subscriptionId) else { return }

        detail.metrics.endTime = Date()

        if trackClosedSubscriptions {
            let closedSub = NDKClosedSubscription(detail: detail)
            closedSubscriptions.append(closedSub)

            // Maintain max history size
            if closedSubscriptions.count > maxClosedSubscriptions {
                closedSubscriptions.removeFirst(closedSubscriptions.count - maxClosedSubscriptions)
            }
        }

        invalidateStatisticsCache()
    }

    // MARK: - Query Methods

    /// Returns the current number of active subscriptions
    public func activeSubscriptionCount() -> Int {
        return activeSubscriptions.count
    }

    /// Returns the total number of unique events received across all active subscriptions
    public func totalUniqueEventsReceived() -> Int {
        return activeSubscriptions.values.reduce(0) { $0 + $1.metrics.totalUniqueEvents }
    }

    /// Returns detailed information about a specific subscription
    public func getSubscriptionDetail(_ subscriptionId: String) -> NDKSubscriptionDetail? {
        return activeSubscriptions[subscriptionId]
    }

    /// Returns all active subscription details
    public func getAllActiveSubscriptions() -> [NDKSubscriptionDetail] {
        return Array(activeSubscriptions.values)
    }

    /// Returns metrics for a specific subscription
    public func getSubscriptionMetrics(_ subscriptionId: String) -> NDKSubscriptionMetrics? {
        return activeSubscriptions[subscriptionId]?.metrics
    }

    /// Returns relay-specific metrics for a subscription
    public func getRelayMetrics(
        subscriptionId: String,
        relayUrl: String
    ) -> NDKRelaySubscriptionMetrics? {
        return activeSubscriptions[subscriptionId]?.relayMetrics[relayUrl]
    }

    /// Returns all relay metrics for a subscription
    public func getAllRelayMetrics(
        subscriptionId: String
    ) -> [String: NDKRelaySubscriptionMetrics]? {
        return activeSubscriptions[subscriptionId]?.relayMetrics
    }

    /// Returns the closed subscription history
    public func getClosedSubscriptions() -> [NDKClosedSubscription] {
        return closedSubscriptions
    }

    /// Returns global subscription statistics
    public func getStatistics() -> NDKSubscriptionStatistics {
        if let cached = cachedStatistics {
            return cached
        }

        var stats = NDKSubscriptionStatistics()

        // Active subscriptions
        stats.activeSubscriptions = activeSubscriptions.count

        // Total subscriptions (active + closed)
        stats.totalSubscriptions = activeSubscriptions.count + closedSubscriptions.count

        // Events from active subscriptions
        let activeEvents = activeSubscriptions.values.reduce((unique: 0, total: 0)) { result, detail in
            (
                unique: result.unique + detail.metrics.totalUniqueEvents,
                total: result.total + detail.metrics.totalEvents
            )
        }

        // Events from closed subscriptions
        let closedEvents = closedSubscriptions.reduce((unique: 0, total: 0)) { result, closed in
            (
                unique: result.unique + closed.uniqueEventCount,
                total: result.total + closed.totalEventCount
            )
        }

        stats.totalUniqueEvents = activeEvents.unique + closedEvents.unique
        stats.totalEvents = activeEvents.total + closedEvents.total
        stats.closedSubscriptionsTracked = closedSubscriptions.count

        cachedStatistics = stats
        return stats
    }

    // MARK: - Utility Methods

    /// Clears the closed subscription history
    public func clearClosedSubscriptionHistory() {
        closedSubscriptions.removeAll()
        invalidateStatisticsCache()
    }

    /// Exports all tracking data for debugging
    public func exportTrackingData() -> [String: Any] {
        return [
            "activeSubscriptions": activeSubscriptions.values.map { detail in
                [
                    "subscriptionId": detail.subscriptionId,
                    "filter": detail.originalFilter.dictionary,
                    "metrics": [
                        "totalUniqueEvents": detail.metrics.totalUniqueEvents,
                        "totalEvents": detail.metrics.totalEvents,
                        "activeRelayCount": detail.metrics.activeRelayCount,
                        "startTime": detail.metrics.startTime.timeIntervalSince1970,
                        "isActive": detail.metrics.isActive,
                    ],
                    "relayMetrics": detail.relayMetrics.mapValues { relay in
                        [
                            "eventsReceived": relay.eventsReceived,
                            "eoseReceived": relay.eoseReceived,
                            "subscriptionTime": relay.subscriptionTime.timeIntervalSince1970,
                            "timeToEose": relay.timeToEose ?? -1,
                        ]
                    },
                ]
            },
            "closedSubscriptions": closedSubscriptions.map { closed in
                [
                    "subscriptionId": closed.subscriptionId,
                    "filter": closed.filter.dictionary,
                    "relays": closed.relays,
                    "uniqueEventCount": closed.uniqueEventCount,
                    "totalEventCount": closed.totalEventCount,
                    "duration": closed.duration,
                    "eventsPerSecond": closed.eventsPerSecond,
                ]
            },
            "statistics": [
                "activeSubscriptions": getStatistics().activeSubscriptions,
                "totalSubscriptions": getStatistics().totalSubscriptions,
                "totalUniqueEvents": getStatistics().totalUniqueEvents,
                "totalEvents": getStatistics().totalEvents,
                "averageEventsPerSubscription": getStatistics().averageEventsPerSubscription,
            ],
        ]
    }

    // MARK: - Private Methods

    private func invalidateStatisticsCache() {
        cachedStatistics = nil
    }
}
