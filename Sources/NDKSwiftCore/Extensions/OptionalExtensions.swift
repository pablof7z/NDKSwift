/// Extensions for Optional types to provide convenient nil-handling functionality
///
/// These extensions provide common patterns for dealing with optional values,
/// particularly for strings and collections, reducing boilerplate code throughout
/// the NDKSwift codebase.

extension Optional where Wrapped == String {
    /// Returns true if the string is nil or empty
    ///
    /// This property provides a convenient way to check if an optional string
    /// contains a meaningful value without unwrapping.
    ///
    /// ## Example
    /// ```swift
    /// let name: String? = nil
    /// if name.isNilOrEmpty {
    ///     print("No name provided")
    /// }
    /// ```
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            return true
        case let .some(value):
            return value.isEmpty
        }
    }

    /// Returns the string value or an empty string if nil
    ///
    /// This property provides a safe way to unwrap optional strings when an
    /// empty string is an acceptable default value.
    ///
    /// ## Example
    /// ```swift
    /// let optionalText: String? = nil
    /// let displayText = optionalText.orEmpty // Returns ""
    /// ```
    var orEmpty: String {
        self ?? ""
    }
}

extension Optional where Wrapped: Collection {
    /// Returns true if the collection is nil or empty
    ///
    /// This property provides a convenient way to check if an optional collection
    /// contains any elements without unwrapping.
    ///
    /// ## Example
    /// ```swift
    /// let tags: [[String]]? = nil
    /// if tags.isNilOrEmpty {
    ///     print("No tags available")
    /// }
    /// ```
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            return true
        case let .some(value):
            return value.isEmpty
        }
    }
}
