import Foundation

/// Centralized JSON encoding/decoding utility for consistent behavior across NDKSwift
public enum JSONCoding {
    
    // MARK: - Encoders
    
    /// Standard JSON encoder with sorted keys and without escaping slashes
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    
    /// Pretty-printed JSON encoder for debugging
    public static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    
    /// Snake-case JSON encoder for NWC and other protocols requiring snake_case
    public static let snakeCaseEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    
    // MARK: - Decoders
    
    /// Standard JSON decoder
    public static let decoder = JSONDecoder()
    
    // MARK: - Convenience Methods
    
    /// Encode an object to JSON data
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
    
    /// Encode an object to JSON string
    public static func encodeToString<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NDKError.failedTo("convert JSON data to UTF-8 string", message: "Type: \(T.self)")
        }
        return string
    }
    
    /// Decode JSON data to object
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
    
    /// Decode JSON string to object
    public static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw NDKError.invalidInput(message: "Invalid UTF-8 string")
        }
        return try decode(type, from: data)
    }
    
    /// Encode to dictionary representation
    public static func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encode(value)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NDKError.failedTo("convert JSON data to dictionary", message: "Type: \(T.self)")
        }
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
        guard let string = String(data: data, encoding: .utf8) else {
            throw NDKError.failedTo("encode Nostr message to UTF-8 string", message: "Type: \(T.self)")
        }
        return string
    }
    
    /// Encode with snake_case keys to string
    public static func encodeSnakeCaseToString<T: Encodable>(_ value: T) throws -> String {
        let data = try snakeCaseEncoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NDKError.failedTo("encode snake_case JSON to UTF-8 string", message: "Type: \(T.self)")
        }
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
        guard let data = string.data(using: .utf8) else {
            throw NDKError.invalidInput(message: "Invalid UTF-8 string")
        }
        return try parseJSON(from: data)
    }
    
    /// Parse JSON data to dictionary
    public static func parseDictionary(from data: Data) throws -> [String: Any] {
        guard let dict = try parseJSON(from: data) as? [String: Any] else {
            throw NDKError.parseError(for: "JSON dictionary", details: "Expected dictionary but got different type")
        }
        return dict
    }
    
    /// Parse JSON string to dictionary
    public static func parseDictionary(from string: String) throws -> [String: Any] {
        guard let data = string.data(using: .utf8) else {
            throw NDKError.invalidInput(message: "Invalid UTF-8 string")
        }
        return try parseDictionary(from: data)
    }
    
    /// Parse JSON data to array
    public static func parseArray(from data: Data) throws -> [Any] {
        let parsed = try parseJSON(from: data)
        guard let array = parsed as? [Any] else {
            let actualType = String(describing: type(of: parsed))
            throw NDKError.parseError(for: "JSON array", details: "Expected array but got \(actualType): \(String(describing: parsed).prefix(100))")
        }
        return array
    }
    
    /// Parse JSON string to array
    public static func parseArray(from string: String) throws -> [Any] {
        guard !string.isEmpty else {
            throw NDKError.invalidInput(message: "Empty string cannot be parsed as JSON array")
        }
        guard let data = string.data(using: .utf8) else {
            throw NDKError.invalidInput(message: "Invalid UTF-8 string")
        }
        return try parseArray(from: data)
    }
    
    /// Serialize object to JSON data
    public static func serialize(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }
    
    /// Serialize object to JSON string
    public static func serializeToString(_ object: Any) throws -> String {
        let data = try serialize(object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NDKError.failedTo("serialize JSON data to UTF-8 string")
        }
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
