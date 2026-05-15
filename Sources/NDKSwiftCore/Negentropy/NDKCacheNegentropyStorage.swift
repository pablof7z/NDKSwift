import Foundation

/// Negentropy storage implementation backed by NDKCache
public actor NDKCacheNegentropyStorage: NegentropyStorage {
    private let cache: NDKNostrDBCache
    private var filter: NDKFilter?

    public init(cache: NDKNostrDBCache, filter: NDKFilter? = nil) {
        self.cache = cache
        self.filter = filter
    }

    public func setFilter(_ filter: NDKFilter) {
        self.filter = filter
    }

    public func getItems(in range: NegentropyRange) async throws -> [NegentropyItem] {
        // Convert range bounds to timestamps
        var fromTimestamp = range.lower?.timestamp ?? 0
        var toTimestamp = range.upper?.timestamp ?? UInt64(Timestamp.max)

        // Apply filter's time constraints if present
        if let filter = filter {
            if let since = filter.since {
                fromTimestamp = max(fromTimestamp, UInt64(since))
            }
            if let until = filter.until {
                toTimestamp = min(toTimestamp, UInt64(until))
            }
        }

        // Get events from cache
        let events = try await cache.getEventsByTimeRange(
            from: Timestamp(fromTimestamp),
            to: Timestamp(toTimestamp),
            filter: filter
        )

        // Convert to NegentropyItems and sort ASC by (timestamp, id). The cache
        // returns events DESC by createdAt, but Negentropy fingerprinting,
        // varint delta encoding, and binary-search bound location all assume
        // canonical ASC order. Without this, reconciliation cannot converge
        // with spec-compliant peers.
        let items = try events.map { try NegentropyItem(event: $0) }
        return items.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.lexicographicallyPrecedes(rhs.id)
        }
    }

    public func getRangeInfo(_ range: NegentropyRange) async throws -> (fingerprint: Data, count: Int) {
        // Get items in range
        let items = try await getItems(in: range)

        // Compute fingerprint
        let accumulator = NegentropyAccumulator.from(items)
        let fingerprint = accumulator.fingerprint()

        return (fingerprint: fingerprint, count: items.count)
    }

    public func addItems(_: [NegentropyItem]) async throws {
        // Events are added through normal NDK flow, not directly through this method
        // This maintains consistency with NDK's event handling pipeline
    }

    public func removeItems(_ ids: [Data]) async throws {
        // Convert Data IDs to hex strings
        for idData in ids {
            let hexId = idData.hexString
            try await cache.deleteEvent(id: hexId)
        }
    }

    /// Get items that match specific IDs (for reconciliation)
    public func getItemsById(_ ids: [Data]) async throws -> [NegentropyItem] {
        let hexIds = ids.map { $0.hexString }
        let existence = await cache.hasEvents(ids: hexIds)

        var items: [NegentropyItem] = []
        for (hexId, exists) in existence {
            if exists, let event = await cache.getEvent(id: hexId) {
                try items.append(NegentropyItem(event: event))
            }
        }

        return items
    }

    /// Efficient method to get just IDs and timestamps without full event data
    public func getItemMetadata(in range: NegentropyRange) async throws -> [(id: Data, timestamp: UInt64)] {
        let fromTimestamp = range.lower?.timestamp ?? 0
        let toTimestamp = range.upper?.timestamp ?? UInt64(Timestamp.max)

        let idsAndTimestamps = try await cache.getEventIdsWithTimestamps(
            from: Timestamp(fromTimestamp),
            to: Timestamp(toTimestamp),
            filter: filter
        )

        let mapped: [(id: Data, timestamp: UInt64)] = try idsAndTimestamps.map { id, timestamp in
            guard let idData = id.hexDecoded(), idData.count == 32 else {
                throw NegentropyError.invalidItemId
            }
            return (id: idData, timestamp: UInt64(timestamp))
        }

        // Negentropy canonical order: ASC by (timestamp, id).
        return mapped.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.lexicographicallyPrecedes(rhs.id)
        }
    }
}
