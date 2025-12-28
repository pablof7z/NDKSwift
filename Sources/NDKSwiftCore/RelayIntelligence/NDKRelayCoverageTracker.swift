import Foundation

/// Statistics for tracking relay coverage
public struct RelayCoverageStats: Sendable, Equatable {
    /// Number of events this relay delivered first
    public var firstDeliveryCount: Int = 0

    /// Total number of events seen from this relay
    public var totalEventsCount: Int = 0

    /// Number of duplicate deliveries (events seen on other relays first)
    public var duplicateDeliveryCount: Int = 0

    /// Computed coverage ratio (first deliveries / total events)
    public var coverageRatio: Double {
        guard totalEventsCount > 0 else { return 0.0 }
        return Double(firstDeliveryCount) / Double(totalEventsCount)
    }

    public init(
        firstDeliveryCount: Int = 0,
        totalEventsCount: Int = 0,
        duplicateDeliveryCount: Int = 0
    ) {
        self.firstDeliveryCount = firstDeliveryCount
        self.totalEventsCount = totalEventsCount
        self.duplicateDeliveryCount = duplicateDeliveryCount
    }
}

/// Tracks relay coverage for intelligent relay selection
///
/// This actor monitors which relays deliver events first vs duplicates,
/// helping identify high-value relays for the user's network.
public actor NDKRelayCoverageTracker {
    /// Coverage statistics per relay URL
    private var relayStats: [RelayURL: RelayCoverageStats] = [:]

    /// Events we've seen and which relay delivered them first
    private var eventFirstDelivery: [EventID: RelayURL] = [:]

    /// Maximum number of events to track for first delivery
    private let maxTrackedEvents: Int

    /// Order of events for LRU eviction
    private var eventTrackingOrder: [EventID] = []

    public init(maxTrackedEvents: Int = 10000) {
        self.maxTrackedEvents = maxTrackedEvents
    }

    /// Normalize relay URL for consistent dictionary lookups
    /// Removes trailing slash and lowercases for consistent matching
    private func normalizeURL(_ url: RelayURL) -> RelayURL {
        var normalized = url.lowercased()
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    /// Record an event delivery from a relay
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relayUrl: The relay that delivered the event
    /// - Returns: true if this was the first delivery, false if duplicate
    @discardableResult
    public func recordDelivery(eventId: EventID, relayUrl: RelayURL) -> Bool {
        let normalizedUrl = normalizeURL(relayUrl)

        // Initialize stats for this relay if needed
        if relayStats[normalizedUrl] == nil {
            relayStats[normalizedUrl] = RelayCoverageStats()
        }

        // Check if this is the first delivery
        let isFirstDelivery = eventFirstDelivery[eventId] == nil

        if isFirstDelivery {
            // Record this relay as the first to deliver this event
            eventFirstDelivery[eventId] = normalizedUrl
            eventTrackingOrder.append(eventId)

            // Increment first delivery count
            relayStats[normalizedUrl]?.firstDeliveryCount += 1

            // Evict oldest if we've exceeded the max
            if eventTrackingOrder.count > maxTrackedEvents {
                if let oldestEventId = eventTrackingOrder.first {
                    eventTrackingOrder.removeFirst()
                    eventFirstDelivery.removeValue(forKey: oldestEventId)
                }
            }
        } else {
            // This is a duplicate delivery
            relayStats[normalizedUrl]?.duplicateDeliveryCount += 1
        }

        // Always increment total count
        relayStats[normalizedUrl]?.totalEventsCount += 1

        return isFirstDelivery
    }

    /// Get coverage statistics for a specific relay
    /// - Parameter relayUrl: The relay URL
    /// - Returns: Coverage statistics, or default stats if relay not tracked
    public func getStats(for relayUrl: RelayURL) -> RelayCoverageStats {
        let normalizedUrl = normalizeURL(relayUrl)
        return relayStats[normalizedUrl] ?? RelayCoverageStats()
    }

    /// Get coverage statistics for all relays
    /// - Returns: Dictionary of relay URL to coverage stats
    public func getAllStats() -> [RelayURL: RelayCoverageStats] {
        return relayStats
    }

    /// Get relays sorted by coverage ratio (best to worst)
    /// - Returns: Array of (relay URL, coverage stats) tuples sorted by coverage ratio
    public func getRelaysByCoverage() -> [(relayUrl: RelayURL, stats: RelayCoverageStats)] {
        return relayStats
            .map { ($0.key, $0.value) }
            .sorted { $0.1.coverageRatio > $1.1.coverageRatio }
    }

    /// Clear all tracking data
    public func clear() {
        relayStats.removeAll()
        eventFirstDelivery.removeAll()
        eventTrackingOrder.removeAll()
    }

    /// Clear tracking data for a specific relay
    /// - Parameter relayUrl: The relay URL to clear
    public func clearRelay(_ relayUrl: RelayURL) {
        let normalizedUrl = normalizeURL(relayUrl)
        relayStats.removeValue(forKey: normalizedUrl)
        // Note: We don't remove from eventFirstDelivery as that would affect other relays' stats
    }

    /// Get summary statistics
    /// - Returns: Tuple with total tracked relays and events
    public func getSummary() -> (trackedRelays: Int, trackedEvents: Int) {
        return (relayStats.count, eventFirstDelivery.count)
    }
}
