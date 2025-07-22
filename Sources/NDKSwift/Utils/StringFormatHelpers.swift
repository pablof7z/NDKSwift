import Foundation

/// Common string formatting helpers to reduce duplication
public enum StringFormatHelpers {
    
    // MARK: - Error Message Formatting
    
    /// Format an error message with operation context
    public static func errorMessage(operation: String, details: String? = nil) -> String {
        if let details = details {
            return "\(ErrorMessageConstants.failedTo(operation)): \(details)"
        }
        return ErrorMessageConstants.failedTo(operation)
    }
    
    /// Format a validation error message
    public static func validationError(field: String, requirement: String) -> String {
        return "\(field) \(requirement)"
    }
    
    // MARK: - Relay URL Formatting
    
    /// Format relay URL for display (removes trailing slash for consistency)
    public static func displayURL(_ url: String) -> String {
        return url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    
    /// Format multiple relay URLs for display
    public static func displayURLs(_ urls: [String], separator: String = ", ") -> String {
        return urls.map { displayURL($0) }.joined(separator: separator)
    }
    
    // MARK: - Hex String Formatting
    
    /// Format hex string for display (lowercase, no 0x prefix)
    public static func formatHex(_ hex: String) -> String {
        var formatted = hex.lowercased()
        if formatted.hasPrefix("0x") {
            formatted = String(formatted.dropFirst(2))
        }
        return formatted
    }
    
    /// Truncate hex string for display (e.g., "abc123...def456")
    public static func truncateHex(_ hex: String, prefixLength: Int = 6, suffixLength: Int = 6) -> String {
        guard hex.count > prefixLength + suffixLength + 3 else { return hex }
        let prefix = hex.prefix(prefixLength)
        let suffix = hex.suffix(suffixLength)
        return "\(prefix)...\(suffix)"
    }
    
    // MARK: - JSON Formatting
    
    /// Pretty print JSON data
    public static func prettyJSON(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }
    
    /// Pretty print JSON dictionary
    public static func prettyJSON(from dictionary: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted),
              let prettyString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return prettyString
    }
    
    // MARK: - Time Formatting
    
    /// Format Unix timestamp for display
    public static func formatTimestamp(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Format time interval for display (e.g., "5 minutes", "2 hours")
    public static func formatTimeInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute, .second]
        return formatter.string(from: interval) ?? "\(Int(interval)) seconds"
    }
}