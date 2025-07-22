// MARK: - Safe Array Access

public extension Array {
    /// Safe subscript that returns nil for out-of-bounds indices
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Array to Set Conversion

public extension Array where Element: Hashable {
    /// Convert array to set
    var set: Set<Element> {
        Set(self)
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

