import Foundation

/// Result type for validation operations that provides detailed error information
public enum ValidationResult<T> {
    case valid(T)
    case invalid(String)

    /// Whether the validation passed
    public var isValid: Bool {
        switch self {
        case .valid:
            return true
        case .invalid:
            return false
        }
    }

    /// The validated value if valid, nil otherwise
    public var value: T? {
        switch self {
        case let .valid(value):
            return value
        case .invalid:
            return nil
        }
    }

    /// The error message if invalid, nil otherwise
    public var error: String? {
        switch self {
        case .valid:
            return nil
        case let .invalid(error):
            return error
        }
    }

    /// Map the valid value to a new type
    public func map<U>(_ transform: (T) -> U) -> ValidationResult<U> {
        switch self {
        case let .valid(value):
            return .valid(transform(value))
        case let .invalid(error):
            return .invalid(error)
        }
    }

    /// FlatMap for chaining validations
    public func flatMap<U>(_ transform: (T) -> ValidationResult<U>) -> ValidationResult<U> {
        switch self {
        case let .valid(value):
            return transform(value)
        case let .invalid(error):
            return .invalid(error)
        }
    }

    /// Convert to a Swift Result type
    public var asResult: Result<T, ValidationError> {
        switch self {
        case let .valid(value):
            return .success(value)
        case let .invalid(error):
            return .failure(ValidationError(message: error))
        }
    }
}

/// Error type for validation failures
public struct ValidationError: LocalizedError {
    public let message: String

    public var errorDescription: String? {
        return message
    }
}

/// Common validation utilities
public enum ValidationUtils {
    /// Validate that a string is not empty
    public static func validateNotEmpty(_ string: String, fieldName: String) -> ValidationResult<String> {
        if string.trimmed.isEmpty {
            return .invalid("\(fieldName) cannot be empty")
        }
        return .valid(string.trimmed)
    }

    /// Validate string length
    public static func validateLength(
        _ string: String,
        fieldName: String,
        min: Int? = nil,
        max: Int? = nil
    ) -> ValidationResult<String> {
        let trimmed = string.trimmed

        if let min = min, trimmed.count < min {
            return .invalid("\(fieldName) must be at least \(min) characters")
        }

        if let max = max, trimmed.count > max {
            return .invalid("\(fieldName) must be at most \(max) characters")
        }

        return .valid(trimmed)
    }

    /// Validate a numeric value is within range
    public static func validateRange<T: Comparable & Numeric>(
        _ value: T,
        fieldName: String,
        min: T? = nil,
        max: T? = nil
    ) -> ValidationResult<T> {
        if let min = min, value < min {
            return .invalid("\(fieldName) must be at least \(min)")
        }

        if let max = max, value > max {
            return .invalid("\(fieldName) must be at most \(max)")
        }

        return .valid(value)
    }

    /// Validate an array is not empty
    public static func validateNotEmpty<T>(
        _ array: [T],
        fieldName: String
    ) -> ValidationResult<[T]> {
        if array.isEmpty {
            return .invalid("\(fieldName) cannot be empty")
        }
        return .valid(array)
    }

    /// Validate array size
    public static func validateArraySize<T>(
        _ array: [T],
        fieldName: String,
        min: Int? = nil,
        max: Int? = nil
    ) -> ValidationResult<[T]> {
        if let min = min, array.count < min {
            return .invalid("\(fieldName) must contain at least \(min) items")
        }

        if let max = max, array.count > max {
            return .invalid("\(fieldName) must contain at most \(max) items")
        }

        return .valid(array)
    }

    /// Combine multiple validations
    public static func combine<T>(_ validations: ValidationResult<T>...) -> ValidationResult<[T]> {
        var results: [T] = []

        for validation in validations {
            switch validation {
            case let .valid(value):
                results.append(value)
            case let .invalid(error):
                return .invalid(error)
            }
        }

        return .valid(results)
    }

    /// Validate all items in a collection
    public static func validateAll<T>(
        _ items: [T],
        validator: (T) -> ValidationResult<T>
    ) -> ValidationResult<[T]> {
        var validatedItems: [T] = []

        for item in items {
            switch validator(item) {
            case let .valid(validated):
                validatedItems.append(validated)
            case let .invalid(error):
                return .invalid(error)
            }
        }

        return .valid(validatedItems)
    }
}

// MARK: - NDK-specific Validations

public extension ValidationUtils {
    /// Validate a Nostr public key
    static func validatePublicKey(_ pubkey: String) -> ValidationResult<PublicKey> {
        if !HexValidator.isValid32ByteHex(pubkey) {
            return .invalid("Invalid public key format")
        }
        return .valid(pubkey)
    }

    /// Validate a Nostr private key
    static func validatePrivateKey(_ privkey: String) -> ValidationResult<PrivateKey> {
        if !HexValidator.isValid32ByteHex(privkey) {
            return .invalid("Invalid private key format")
        }
        return .valid(privkey)
    }

    /// Validate an event ID
    static func validateEventID(_ id: String) -> ValidationResult<EventID> {
        if !HexValidator.isValid32ByteHex(id) {
            return .invalid("Invalid event ID format")
        }
        return .valid(id)
    }

    /// Validate a relay URL
    static func validateRelayURL(_ url: String) -> ValidationResult<String> {
        guard let normalized = URLNormalizer.tryNormalizeRelayUrl(url) else {
            return .invalid("Invalid relay URL format")
        }
        return .valid(normalized)
    }

    /// Validate event content length
    static func validateEventContent(_ content: String) -> ValidationResult<String> {
        return validateLength(
            content,
            fieldName: "Event content",
            max: 65536 // 64KB - standard Nostr content limit
        )
    }
}
