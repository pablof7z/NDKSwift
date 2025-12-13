import Foundation

/// Helper functions to reduce boilerplate in common guard patterns
public enum GuardHelpers {
    /// Unwraps an optional value or throws an error
    ///
    /// Example:
    /// ```swift
    /// // Before:
    /// guard let value = optionalValue else {
    ///     throw NDKError.invalidInput(message: "Value is required")
    /// }
    ///
    /// // After:
    /// let value = try GuardHelpers.unwrap(optionalValue, error: NDKError.invalidInput(message: "Value is required"))
    /// ```
    public static func unwrap<T>(_ optional: T?, error: Error) throws -> T {
        guard let value = optional else {
            throw error
        }
        return value
    }

    /// Ensures a string is not empty or throws an error
    ///
    /// Example:
    /// ```swift
    /// // Before:
    /// guard !string.isEmpty else {
    ///     throw NDKError.invalidInput(message: "String cannot be empty")
    /// }
    ///
    /// // After:
    /// try GuardHelpers.requireNotEmpty(string, error: NDKError.invalidInput(message: "String cannot be empty"))
    /// ```
    @discardableResult
    public static func requireNotEmpty(_ string: String, error: Error) throws -> String {
        guard !string.isEmpty else {
            throw error
        }
        return string
    }

    /// Ensures an array is not empty or throws an error
    ///
    /// Example:
    /// ```swift
    /// // Before:
    /// guard !array.isEmpty else {
    ///     throw NDKError.invalidInput(message: "Array cannot be empty")
    /// }
    ///
    /// // After:
    /// try GuardHelpers.requireNotEmpty(array, error: NDKError.invalidInput(message: "Array cannot be empty"))
    /// ```
    @discardableResult
    public static func requireNotEmpty<T>(_ array: [T], error: Error) throws -> [T] {
        guard !array.isEmpty else {
            throw error
        }
        return array
    }

    /// Validates and returns a value if it meets a condition, otherwise throws
    ///
    /// Example:
    /// ```swift
    /// // Before:
    /// guard value > 0 else {
    ///     throw NDKError.invalidInput(message: "Value must be positive")
    /// }
    ///
    /// // After:
    /// try GuardHelpers.require(value, condition: { $0 > 0 }, error: NDKError.invalidInput(message: "Value must be positive"))
    /// ```
    @discardableResult
    public static func require<T>(_ value: T, condition: (T) -> Bool, error: Error) throws -> T {
        guard condition(value) else {
            throw error
        }
        return value
    }

    /// Ensures content is not nil and not empty
    ///
    /// Example:
    /// ```swift
    /// // Before:
    /// guard let content = content, !content.isEmpty else {
    ///     throw NDKError.invalidInput(message: "Content is required")
    /// }
    ///
    /// // After:
    /// let content = try GuardHelpers.requireContent(content, error: NDKError.invalidInput(message: "Content is required"))
    /// ```
    public static func requireContent(_ content: String?, error: Error) throws -> String {
        guard let content = content, !content.isEmpty else {
            throw error
        }
        return content
    }
}
