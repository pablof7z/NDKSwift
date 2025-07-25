import Foundation

/// Manages efficient subscription swapping when dependencies change
public actor SubscriptionSwapManager {
    /// Shared instance
    public static let shared = SubscriptionSwapManager()

    /// Tracked subscriptions with their reactive filters
    private var trackedSubscriptions: [String: TrackedSubscription] = [:]

    private struct TrackedSubscription {
        let id: String
        let dataSource: NDKDataSource<NDKEvent>
        let reactiveFilter: ReactiveFilter
        let sessionData: NDKSessionData
        var lastFilter: NDKFilter
    }

    private init() {}

    /// Register a reactive subscription
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - dataSource: The data source to manage
    ///   - reactiveFilter: The reactive filter definition
    ///   - sessionData: Session data for dependencies
    func register(
        id: String,
        dataSource: NDKDataSource<NDKEvent>,
        reactiveFilter: ReactiveFilter,
        sessionData: NDKSessionData
    ) {
        let filter = reactiveFilter.builder(sessionData)
        trackedSubscriptions[id] = TrackedSubscription(
            id: id,
            dataSource: dataSource,
            reactiveFilter: reactiveFilter,
            sessionData: sessionData,
            lastFilter: filter
        )
    }

    /// Unregister a subscription
    /// - Parameter id: Subscription identifier
    func unregister(id: String) {
        trackedSubscriptions.removeValue(forKey: id)
    }

    /// Handle follow list update
    /// - Parameter sessionData: Updated session data
    func handleFollowListUpdate(_ sessionData: NDKSessionData) async {
        // Find all subscriptions that depend on follow list
        let affectedSubscriptions = trackedSubscriptions.values.filter { subscription in
            subscription.reactiveFilter.dependencies.contains(.followList)
        }

        // Swap each affected subscription
        for subscription in affectedSubscriptions {
            await swapSubscription(subscription)
        }
    }

    /// Perform efficient subscription swap
    /// - Parameter subscription: Subscription to swap
    private func swapSubscription(_ subscription: TrackedSubscription) async {
        // Build new filter with updated session data
        let newFilter = subscription.reactiveFilter.builder(subscription.sessionData)

        // Check if filter actually changed
        guard !filtersEqual(subscription.lastFilter, newFilter) else { return }

        // If WOT is needed, ensure it's loaded
        if subscription.reactiveFilter.wotConfig != nil {
            _ = subscription.sessionData.webOfTrust // Trigger lazy load
        }

        // Create bridge filter with small limit
        var bridgeFilter = newFilter
        bridgeFilter.limit = 5

        // Perform the swap
        await subscription.dataSource.updateFilter(bridgeFilter)

        // Wait a moment for bridge events
        try? await Task.sleep(nanoseconds: 100 * TimeConstants.nanosecondsPerMillisecond) // 100ms

        // Update to full filter
        await subscription.dataSource.updateFilter(newFilter)

        // Update tracked filter
        if var updated = trackedSubscriptions[subscription.id] {
            updated.lastFilter = newFilter
            trackedSubscriptions[subscription.id] = updated
        }
    }

    /// Check if two filters are equal
    private func filtersEqual(_ a: NDKFilter, _ b: NDKFilter) -> Bool {
        // Compare relevant fields
        return a.kinds == b.kinds &&
               a.authors == b.authors &&
               a.tags == b.tags &&
               a.since == b.since &&
               a.until == b.until
    }
}