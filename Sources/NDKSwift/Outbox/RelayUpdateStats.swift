import Foundation

/// Statistics about relay updates and subscriptions
public struct RelayUpdateStats: Sendable {
    public let activeSubscriptions: Int
    public let totalUnknownAuthors: Int
    public let totalUpdateSubscriptions: Int

    public init(activeSubscriptions: Int, totalUnknownAuthors: Int, totalUpdateSubscriptions: Int) {
        self.activeSubscriptions = activeSubscriptions
        self.totalUnknownAuthors = totalUnknownAuthors
        self.totalUpdateSubscriptions = totalUpdateSubscriptions
    }
}