import Foundation

/// Protocol defining relay selection intelligence for various operations
public protocol RelayIntelligence: Sendable {
    /// Select relays for publishing an event
    /// - Parameter event: The event to be published
    /// - Returns: Set of relay URLs to publish to
    func relaysForPublishing(event: NDKEvent) async -> Set<RelayURL>

    /// Select relays for fetching events matching a filter
    /// - Parameter filter: The filter to match
    /// - Returns: Set of relay URLs to fetch from
    func relaysForFetching(filter: NDKFilter) async -> Set<RelayURL>

    /// Select relays for subscribing to events matching filters
    /// - Parameter filters: The filters to match
    /// - Returns: Set of relay URLs to subscribe to
    func relaysForSubscribing(filters: [NDKFilter]) async -> Set<RelayURL>
}
