import Foundation

// MARK: - Numeric Collection Extensions
extension Collection where Element: BinaryInteger {
    /// Calculates the average of all elements in the collection
    /// - Returns: The average value, or 0 if the collection is empty
    public var ndkAverage: Double {
        isEmpty ? 0 : Double(reduce(0, +)) / Double(count)
    }
}

extension Collection where Element: BinaryFloatingPoint {
    /// Calculates the average of all elements in the collection
    /// - Returns: The average value, or 0 if the collection is empty
    public var ndkAverage: Element {
        isEmpty ? 0 : reduce(0, +) / Element(count)
    }
}

// MARK: - Safe Collection Operations
extension Collection {
    /// Safely returns the first element that satisfies the given predicate
    /// - Parameter predicate: A closure that takes an element and returns a Boolean
    /// - Returns: The first element that satisfies predicate, or nil
    public func firstWhere(_ predicate: (Element) throws -> Bool) rethrows -> Element? {
        try first(where: predicate)
    }
    
    /// Returns true if the collection is not empty
    public var isNotEmpty: Bool {
        !isEmpty
    }
    
    /// More readable way to check if collection has elements
    public var hasElements: Bool {
        return !isEmpty
    }
    
    /// Check if collection has exactly one element
    public var hasOneElement: Bool {
        return count == 1
    }
    
    /// Check if collection has more than one element
    public var hasMultipleElements: Bool {
        return count > 1
    }
    
    /// Safe way to get the only element if collection has exactly one
    public var onlyElement: Element? {
        return hasOneElement ? first : nil
    }
}

// MARK: - Array Extensions

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

// MARK: - String Extensions for Common Operations

public extension String {
    /// Returns true if string has content after trimming whitespace
    var hasContent: Bool {
        return !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Returns the string trimmed of whitespace and newlines
    var trimmed: String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Returns the string normalized (trimmed and lowercased)
    var normalized: String {
        return trimmed.lowercased()
    }
    
    /// Checks if string starts with any of the given prefixes (case-insensitive)
    func startsWithAny(of prefixes: [String]) -> Bool {
        let normalized = self.normalized
        return prefixes.contains { normalized.hasPrefix($0.normalized) }
    }
}

// MARK: - Optional Extensions

public extension Optional where Wrapped: Collection {
    /// Returns true if optional is nil or empty
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
    
    /// Returns true if optional has elements
    var hasElements: Bool {
        return !isNilOrEmpty
    }
}