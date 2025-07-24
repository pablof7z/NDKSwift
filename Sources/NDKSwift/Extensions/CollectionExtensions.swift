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

public extension Array where Element: Equatable {
    /// Remove all occurrences of the specified value
    /// - Parameter value: The value to remove from the array
    mutating func removeAll(value: Element) {
        removeAll { $0 == value }
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

