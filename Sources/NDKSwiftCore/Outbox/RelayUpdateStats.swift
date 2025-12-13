import Foundation

/// Statistics about relay updates and subscriptions
///
/// This struct provides insights into the current state of relay discovery
/// and subscription management in the outbox model.
public struct RelayUpdateStats: Sendable {
    /// The number of currently active subscriptions across all relays
    public let activeSubscriptions: Int

    /// The total number of authors whose relay preferences are unknown
    ///
    /// These authors will be queried through relay discovery to find their
    /// preferred relays for publishing and reading events.
    public let totalUnknownAuthors: Int

    /// The total number of subscriptions created specifically for relay updates
    ///
    /// These subscriptions monitor for NIP-65 relay list metadata events
    /// to keep relay preferences up-to-date.
    public let totalUpdateSubscriptions: Int

    /// Initialize relay update statistics
    /// - Parameters:
    ///   - activeSubscriptions: Number of active subscriptions
    ///   - totalUnknownAuthors: Number of authors with unknown relay preferences
    ///   - totalUpdateSubscriptions: Number of relay update subscriptions
    public init(activeSubscriptions: Int, totalUnknownAuthors: Int, totalUpdateSubscriptions: Int) {
        self.activeSubscriptions = activeSubscriptions
        self.totalUnknownAuthors = totalUnknownAuthors
        self.totalUpdateSubscriptions = totalUpdateSubscriptions
    }
}
