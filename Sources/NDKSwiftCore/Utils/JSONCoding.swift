import Foundation

/// Centralized JSON encoding/decoding utility for consistent behavior across NDKSwift
public enum JSONCoding {
    // MARK: - Encoders

    /// Standard JSON encoder with sorted keys and without escaping slashes.
    /// Used for all general JSON encoding needs throughout NDKSwift.
    /// Configuration:
    /// - Sorted keys for consistent output
    /// - No slash escaping for cleaner URLs in JSON
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Pretty-printed JSON encoder for debugging and human-readable output.
    /// Use this when generating JSON for logs, debug output, or user display.
    /// Configuration:
    /// - Pretty printing with indentation
    /// - Sorted keys for consistent output
    /// - No slash escaping
    public static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Snake-case JSON encoder for protocols requiring snake_case keys.
    /// Primarily used for NWC (Nostr Wallet Connect) compatibility.
    /// Configuration:
    /// - Converts camelCase to snake_case
    /// - Sorted keys for consistent output
    /// - No slash escaping
    public static let snakeCaseEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    // MARK: - Decoders

    /// Standard JSON decoder with default configuration.
    /// Handles all JSON decoding throughout NDKSwift.
    public static let decoder = JSONDecoder()

    // MARK: - Convenience Methods

    /// Encode an object to JSON data using the standard encoder.
    /// - Parameter value: The encodable object to convert to JSON
    /// - Returns: JSON data representation
    /// - Throws: `EncodingError` if encoding fails
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    /// Encode an object to a JSON string using the standard encoder.
    /// - Parameter value: The encodable object to convert to JSON
    /// - Returns: JSON string representation
    /// - Throws: `NDKError` if encoding fails or UTF-8 conversion fails
    public static func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        let string = try GuardHelpers.unwrap(
            String(data: data, encoding: .utf8),
            error: NDKError.failedTo("convert JSON data to UTF-8 string", message: "Type: \(T.self)")
        )
        return string
    }

    /// Decode JSON data to an object of the specified type.
    /// - Parameters:
    ///   - type: The type to decode to
    ///   - data: JSON data to decode
    /// - Returns: Decoded object of type T
    /// - Throws: `DecodingError` if decoding fails
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    /// Decode a JSON string to an object of the specified type.
    /// - Parameters:
    ///   - type: The type to decode to
    ///   - string: JSON string to decode
    /// - Returns: Decoded object of type T
    /// - Throws: `NDKError` if UTF-8 conversion fails, `DecodingError` if decoding fails
    public static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let data = try GuardHelpers.unwrap(
            string.data(using: .utf8),
            error: NDKError.validationError("Invalid UTF-8 string")
        )
        return try decode(type, from: data)
    }

    /// Encode to dictionary representation
    public static func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encode(value)
        let dictionary = try GuardHelpers.unwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            error: NDKError.failedTo("convert JSON data to dictionary", message: "Type: \(T.self)")
        )
        return dictionary
    }

    /// Decode from dictionary representation
    public static func decodeFromDictionary<T: Decodable>(_ type: T.Type, from dictionary: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return try decode(type, from: data)
    }

    // MARK: - Specialized Methods

    /// Encode for Nostr message serialization (compact, no spaces)
    public static func encodeForNostr<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        let string = try GuardHelpers.unwrap(
            String(data: data, encoding: .utf8),
            error: NDKError.failedTo("encode Nostr message to UTF-8 string", message: "Type: \(T.self)")
        )
        return string
    }

    /// Encode with snake_case keys to string
    public static func encodeSnakeCaseToString<T: Encodable>(_ value: T) throws -> String {
        let data = try snakeCaseEncoder.encode(value)
        let string = try GuardHelpers.unwrap(
            String(data: data, encoding: .utf8),
            error: NDKError.failedTo("encode snake_case JSON to UTF-8 string", message: "Type: \(T.self)")
        )
        return string
    }

    /// Safe decode with optional result
    public static func safeDecode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decode(type, from: data)
    }

    /// Safe decode from string with optional result
    public static func safeDecode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        try? decode(type, from: string)
    }

    // MARK: - JSONSerialization Helpers

    /// Parse JSON data to Any (object or array)
    public static func parseJSON(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw NDKError.parseError(for: "JSON", details: "Failed to parse JSON: \(error.localizedDescription)")
        }
    }

    /// Parse JSON string to Any (object or array)
    public static func parseJSON(from string: String) throws -> Any {
        let data = try GuardHelpers.unwrap(
            string.data(using: .utf8),
            error: NDKError.validationError("Invalid UTF-8 string")
        )
        return try parseJSON(from: data)
    }

    /// Parse JSON data to dictionary
    public static func parseDictionary(from data: Data) throws -> [String: Any] {
        let dict = try GuardHelpers.unwrap(
            parseJSON(from: data) as? [String: Any],
            error: NDKError.parseError(for: "JSON dictionary", details: "Expected dictionary but got different type")
        )
        return dict
    }

    /// Parse JSON string to dictionary
    public static func parseDictionary(from string: String) throws -> [String: Any] {
        let data = try GuardHelpers.unwrap(
            string.data(using: .utf8),
            error: NDKError.validationError("Invalid UTF-8 string")
        )
        return try parseDictionary(from: data)
    }

    /// Parse JSON data to array
    public static func parseArray(from data: Data) throws -> [Any] {
        let parsed = try parseJSON(from: data)
        let actualType = String(describing: type(of: parsed))
        let array = try GuardHelpers.unwrap(
            parsed as? [Any],
            error: NDKError.parseError(for: "JSON array", details: "Expected array but got \(actualType): \(String(describing: parsed).prefix(100))")
        )
        return array
    }

    /// Parse JSON string to array
    public static func parseArray(from string: String) throws -> [Any] {
        guard !string.isEmpty else {
            throw NDKError.validationError("Empty string cannot be parsed as JSON array")
        }
        let data = try GuardHelpers.unwrap(
            string.data(using: .utf8),
            error: NDKError.validationError("Invalid UTF-8 string")
        )
        return try parseArray(from: data)
    }

    /// Serialize object to JSON data
    public static func serialize(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    /// Serialize object to JSON string
    public static func serializeToString(_ object: Any) throws -> String {
        let data = try serialize(object)
        let string = try GuardHelpers.unwrap(
            String(data: data, encoding: .utf8),
            error: NDKError.failedTo("serialize JSON data to UTF-8 string")
        )
        return string
    }

    /// Safe parse JSON with optional result
    public static func safeParseJSON(from data: Data) -> Any? {
        try? parseJSON(from: data)
    }

    /// Safe parse dictionary with optional result
    public static func safeParseDictionary(from data: Data) -> [String: Any]? {
        try? parseDictionary(from: data)
    }

    /// Safe parse array with optional result
    public static func safeParseArray(from data: Data) -> [Any]? {
        try? parseArray(from: data)
    }
}
