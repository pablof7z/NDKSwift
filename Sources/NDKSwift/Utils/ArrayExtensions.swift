// MARK: - Safe Array Access

public extension Array {
    /// Safe subscript that returns nil for out-of-bounds indices
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Async Operations

public extension Array {
    /// Filter array asynchronously
    func asyncFilter(_ isIncluded: (Element) async -> Bool) async -> [Element] {
        var result: [Element] = []
        for element in self {
            if await isIncluded(element) {
                result.append(element)
            }
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
        return self.sorted(by: { $0.createdAt > $1.createdAt })
    }

    /// Returns events sorted by createdAt in ascending order (oldest first)
    /// - Returns: Array of events sorted from oldest to newest
    func sortedByAge() -> [NDKEvent] {
        return self.sorted(by: { $0.createdAt < $1.createdAt })
    }
}

// MARK: - Array Mutation Extensions

public extension Array {
    /// Remove all elements matching the predicate and return the removed elements
    @discardableResult
    mutating func removeAll(where predicate: (Element) throws -> Bool) rethrows -> [Element] {
        var removed: [Element] = []
        self = try filter { element in
            let shouldRemove = try predicate(element)
            if shouldRemove {
                removed.append(element)
            }
            return !shouldRemove
        }
        return removed
    }
}

public extension Array where Element: Equatable {
    /// Remove all occurrences of the specified value
    /// - Parameter value: The value to remove from the array
    mutating func removeAll(value: Element) {
        removeAll { $0 == value }
    }
}

// MARK: - Array Utilities

public extension Array {
    /// Split array into chunks of specified size
    /// - Parameter size: The size of each chunk
    /// - Returns: Array of arrays, each containing at most `size` elements
    ///
    /// Example:
    /// ```swift
    /// let numbers = [1, 2, 3, 4, 5, 6, 7]
    /// let chunks = numbers.chunked(size: 3)
    /// // Result: [[1, 2, 3], [4, 5, 6], [7]]
    /// ```
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

public extension Array where Element: Hashable {
    /// Returns an array with duplicate elements removed while preserving order
    /// - Returns: Array containing only unique elements in their original order
    ///
    /// Example:
    /// ```swift
    /// let numbers = [1, 2, 3, 2, 4, 3, 5]
    /// let unique = numbers.unique()
    /// // Result: [1, 2, 3, 4, 5]
    /// ```
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { element in
            if seen.contains(element) {
                return false
            } else {
                seen.insert(element)
                return true
            }
        }
    }
}

