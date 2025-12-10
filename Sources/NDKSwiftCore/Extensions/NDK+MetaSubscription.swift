import Foundation

@available(iOS 17.0, macOS 14.0, *)
public extension NDK {
    /// Create a meta subscription that returns events pointed to by e-tags and a-tags
    ///
    /// Instead of returning events matching the filter, this returns the events they
    /// point to. Perfect for discovery feeds, notifications, and engagement-based sorting.
    ///
    /// ## Example
    /// ```swift
    /// // Show content reposted by people you follow
    /// let feed = ndk.metaSubscribe(
    ///     filter: NDKFilter(kinds: [6, 16], authors: follows),
    ///     sort: .tagTime
    /// )
    ///
    /// // Notifications: interactions pointing to your content
    /// let notifications = ndk.metaSubscribe(
    ///     filter: NDKFilter(kinds: [6, 16, 7, 9735], pTags: [myPubkey]),
    ///     sort: .tagTime
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - filter: Filter for pointer events (reposts, zaps, comments, etc.)
    ///   - sort: How to sort the pointed-to events (default: .tagTime)
    ///   - options: Subscription options
    /// - Returns: A reactive NDKMetaSubscription
    @MainActor
    func metaSubscribe(
        filter: NDKFilter,
        sort: NDKMetaSubscriptionSort = .tagTime,
        options: NDKSubscriptionOptions? = nil
    ) -> NDKMetaSubscription {
        NDKMetaSubscription(
            ndk: self,
            filter: filter,
            sort: sort,
            options: options ?? .default
        )
    }
}
