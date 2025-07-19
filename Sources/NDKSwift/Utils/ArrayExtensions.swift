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