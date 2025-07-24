import Foundation

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