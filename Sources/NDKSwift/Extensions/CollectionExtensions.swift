import Foundation

// MARK: - Numeric Collection Extensions
extension Collection where Element: BinaryInteger {
    /// Calculates the average of all elements in the collection
    /// - Returns: The average value, or 0 if the collection is empty
    public var average: Double {
        isEmpty ? 0 : Double(reduce(0, +)) / Double(count)
    }
}

extension Collection where Element: BinaryFloatingPoint {
    /// Calculates the average of all elements in the collection
    /// - Returns: The average value, or 0 if the collection is empty
    public var average: Element {
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
}