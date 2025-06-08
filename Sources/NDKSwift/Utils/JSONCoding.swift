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
            throw NDKError.runtime("json_error", "Failed to convert JSON data to string")
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
            throw NDKError.runtime("json_error", "Invalid UTF-8 string")
        }
        return try decode(type, from: data)
    }
    
    /// Encode to dictionary representation
    public static func encodeToDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encode(value)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NDKError.runtime("json_error", "Failed to convert to dictionary")
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
            throw NDKError.runtime("json_error", "Failed to encode Nostr message")
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
}