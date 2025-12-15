import Foundation

// MARK: - Date Extensions for Nostr

public extension Date {
    /// Returns the current Unix timestamp as used by Nostr
    /// - Returns: The current time as a Timestamp (Int64)
    static var currentNostrTimestamp: Timestamp {
        Timestamp(Date().timeIntervalSince1970)
    }

    /// Converts a Date to a Nostr timestamp
    /// - Returns: The date as a Timestamp (Int64)
    var nostrTimestamp: Timestamp {
        Timestamp(timeIntervalSince1970)
    }

    /// Creates a Date from a Nostr timestamp
    /// - Parameter nostrTimestamp: The Nostr timestamp
    init(nostrTimestamp: Timestamp) {
        self.init(timeIntervalSince1970: TimeInterval(nostrTimestamp))
    }
}
