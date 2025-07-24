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