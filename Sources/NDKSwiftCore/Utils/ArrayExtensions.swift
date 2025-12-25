// MARK: - Safe Array Access

public extension Array {
    /// Safe subscript that returns nil for out-of-bounds indices
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Async Extensions

public extension Array {
    /// Asynchronously filter array elements
    /// - Parameter isIncluded: An async closure that returns true if the element should be included
    /// - Returns: A new array containing only elements where isIncluded returns true
    func asyncFilter(_ isIncluded: (Element) async -> Bool) async -> [Element] {
        var result: [Element] = []
        for element in self where await isIncluded(element) {
            result.append(element)
        }
        return result
    }
}

// MARK: - NDKEvent Convenience

/// Convenience extensions for arrays containing NDKEvent objects
public extension Array where Element == NDKEvent {
    /// Returns the most recent event based on createdAt timestamp
    /// - Returns: The event with the highest createdAt value, or nil if array is empty
    ///
    /// Example:
    /// ```swift
    /// // Instead of:
    /// let latest = events.sorted(by: { $0.createdAt > $1.createdAt }).first
    ///
    /// // Use:
    /// let latest = events.mostRecent
    /// ```
    var mostRecent: NDKEvent? {
        return self.max(by: { $0.createdAt < $1.createdAt })
    }

    /// Returns the oldest event based on createdAt timestamp
    /// - Returns: The event with the lowest createdAt value, or nil if array is empty
    ///
    /// Example:
    /// ```swift
    /// // Instead of:
    /// let oldest = events.sorted(by: { $0.createdAt < $1.createdAt }).first
    ///
    /// // Use:
    /// let oldest = events.oldest
    /// ```
    var oldest: NDKEvent? {
        return self.min(by: { $0.createdAt < $1.createdAt })
    }

    /// Returns events sorted by createdAt in descending order (newest first)
    /// - Returns: Array of events sorted from newest to oldest
    ///
    /// Example:
    /// ```swift
    /// // Instead of:
    /// let sorted = events.sorted(by: { $0.createdAt > $1.createdAt })
    ///
    /// // Use:
    /// let sorted = events.sortedByRecency()
    /// ```
    func sortedByRecency() -> [NDKEvent] {
        return sorted(by: { $0.createdAt > $1.createdAt })
    }
}

// MARK: - Array Mutation Extensions
// (No custom removeAll to avoid shadowing Swift stdlib)
