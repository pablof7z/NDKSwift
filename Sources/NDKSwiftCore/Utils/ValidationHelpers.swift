import Foundation

/// Common validation helpers to reduce duplication and improve code clarity
public enum ValidationHelpers {

    // MARK: - String Validation

    /// Check if a string has content (not empty after trimming whitespace)
    /// - Parameter string: The string to validate
    /// - Returns: true if the string has content
    public static func hasContent(_ string: String) -> Bool {
        !trim(string).isEmpty
    }

    /// Trim whitespace and newlines from a string
    /// - Parameter string: The string to trim
    /// - Returns: The trimmed string
    public static func trim(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Normalize a string by trimming whitespace and converting to lowercase
    /// - Parameter string: The string to normalize
    /// - Returns: The normalized string
    public static func normalize(_ string: String) -> String {
        trim(string).lowercased()
    }

    /// Check if a string has a specific length
    /// - Parameters:
    ///   - string: The string to check
    ///   - length: The expected length
    /// - Returns: true if the string has the specified length
    public static func hasLength(_ string: String, equalTo length: Int) -> Bool {
        string.count == length
    }

    // MARK: - URL Validation

    /// Check if a URL string is a valid WebSocket URL
    /// - Parameter urlString: The URL string to validate
    /// - Returns: true if it's a valid WebSocket URL
    public static func isWebSocketURL(_ urlString: String) -> Bool {
        RelayConstants.WebSocketScheme.isWebSocketURL(urlString)
    }

    /// Check if a URL string can be parsed as a valid URL
    /// - Parameter urlString: The URL string to validate
    /// - Returns: true if it's a valid URL
    public static func isValidURL(_ urlString: String) -> Bool {
        URL(string: urlString) != nil
    }

    // MARK: - Numeric Validation

    /// Check if a value is within a specific range
    /// - Parameters:
    ///   - value: The value to check
    ///   - range: The valid range
    /// - Returns: true if the value is within the range
    public static func isInRange<T: Comparable>(_ value: T, range: ClosedRange<T>) -> Bool {
        range.contains(value)
    }

    /// Check if a numeric value is positive (greater than zero)
    /// - Parameter value: The value to check
    /// - Returns: true if the value is positive
    public static func isPositive<T: Numeric & Comparable>(_ value: T) -> Bool {
        value > 0
    }

    // MARK: - Hex Validation

    /// Check if a string is valid 64-character hex (32 bytes)
    /// - Parameter hex: The hex string to validate
    /// - Returns: true if it's valid 64-character hex
    public static func isValid32ByteHex(_ hex: String) -> Bool {
        HexValidator.isValid32ByteHex(hex)
    }

    /// Check if a string is valid 128-character hex (64 bytes)
    /// - Parameter hex: The hex string to validate
    /// - Returns: true if it's valid 128-character hex
    public static func isValid64ByteHex(_ hex: String) -> Bool {
        HexValidator.isValid64ByteHex(hex)
    }

    // MARK: - Event Kind Validation

    /// Check if an event kind is replaceable
    /// - Parameter kind: The event kind to check
    /// - Returns: true if the kind is replaceable
    public static func isReplaceableKind(_ kind: Int) -> Bool {
        EventKind.isReplaceable(kind)
    }

    /// Check if an event kind is ephemeral
    /// - Parameter kind: The event kind to check
    /// - Returns: true if the kind is ephemeral
    public static func isEphemeralKind(_ kind: Int) -> Bool {
        EventKind.isEphemeral(kind)
    }

    /// Check if an event kind is parameterized replaceable
    /// - Parameter kind: The event kind to check
    /// - Returns: true if the kind is parameterized replaceable
    public static func isParameterizedReplaceableKind(_ kind: Int) -> Bool {
        EventKind.isParameterizedReplaceable(kind)
    }
}