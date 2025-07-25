import Foundation

/// Result from outbox relay recommendation that includes filter breakdown by relay
public struct OutboxFilterStrategy {
    /// Filters broken down by relay - each relay gets only the authors it serves
    public let filtersByRelay: [RelayURL: NDKFilter]

    /// Authors we don't have relay info for (will use app's default relays)
    public let unknownAuthors: Set<String>

    /// Authors we should look up relay lists for in background
    public let authorsToDiscover: Set<String>

    /// Whether this strategy has any relay-specific filters
    public var hasRelaySpecificFilters: Bool {
        !filtersByRelay.isEmpty
    }

    /// Total number of authors across all filters
    public var totalAuthors: Int {
        var allAuthors = Set<String>()
        for (_, filter) in filtersByRelay {
            if let authors = filter.authors {
                allAuthors.formUnion(authors)
            }
        }
        return allAuthors.count
    }
}

/// Tracks recent relay list lookups to avoid spamming
actor RelayListLookupTracker {
    private var recentLookups: [String: Date] = [:]
    private let lookupWindow: TimeInterval

    init(lookupWindow: TimeInterval = 2 * TimeConstants.hour) { // 2 hours default
        self.lookupWindow = lookupWindow
    }

    func shouldLookup(_ pubkey: String) -> Bool {
        if let lastLookup = recentLookups[pubkey] {
            return Date().timeIntervalSince(lastLookup) > lookupWindow
        }
        return true
    }

    func markLookedUp(_ pubkey: String) {
        recentLookups[pubkey] = Date()
    }

    func markLookedUp(_ pubkeys: Set<String>) {
        let now = Date()
        for pubkey in pubkeys {
            recentLookups[pubkey] = now
        }

        // Clean up old entries periodically
        cleanupOldEntries()
    }

    /// Remove entries older than 2x the lookup window to prevent unbounded growth
    private func cleanupOldEntries() {
        let cutoffDate = Date().addingTimeInterval(-lookupWindow * 2)
        recentLookups = recentLookups.filter { $0.value > cutoffDate }
    }
}