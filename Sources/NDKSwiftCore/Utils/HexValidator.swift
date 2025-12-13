import Foundation

/// Utility for validating hex strings and converting them to Data
public enum HexValidator {
    /// Errors that can occur during hex validation
    public enum HexValidationError: LocalizedError {
        case invalidHexString(String)
        case invalidLength(expected: Int, actual: Int)
        case invalidFormat

        public var errorDescription: String? {
            switch self {
            case let .invalidHexString(hex):
                return "Invalid hex string: \(hex)"
            case let .invalidLength(expected, actual):
                return "Invalid hex string length: expected \(expected) bytes, got \(actual) bytes"
            case .invalidFormat:
                return "Invalid hex string format"
            }
        }
    }

    /// Validate and convert a hex string to Data with the specified byte length
    /// - Parameters:
    ///   - hexString: The hex string to validate
    ///   - expectedByteCount: The expected number of bytes (nil for any length)
    /// - Returns: The validated Data
    /// - Throws: HexValidationError if validation fails
    public static func validateHex(_ hexString: String, expectedByteCount: Int? = nil) throws -> Data {
        // Quick validation: check length first if expected count is provided
        if let expectedCount = expectedByteCount {
            let expectedHexLength = expectedCount * 2
            guard hexString.count == expectedHexLength else {
                throw HexValidationError.invalidLength(expected: expectedCount, actual: hexString.count / 2)
            }
        }

        guard let data = Data(hexString: hexString) else {
            throw HexValidationError.invalidHexString(hexString)
        }

        return data
    }

    /// Validate a 32-byte hex string (commonly used for private keys, public keys, etc.)
    /// - Parameter hexString: The hex string to validate
    /// - Returns: The validated 32-byte Data
    /// - Throws: HexValidationError if validation fails
    public static func validate32ByteHex(_ hexString: String) throws -> Data {
        return try validateHex(hexString, expectedByteCount: 32)
    }

    /// Validate a 64-byte hex string (commonly used for signatures)
    /// - Parameter hexString: The hex string to validate
    /// - Returns: The validated 64-byte Data
    /// - Throws: HexValidationError if validation fails
    public static func validate64ByteHex(_ hexString: String) throws -> Data {
        return try validateHex(hexString, expectedByteCount: 64)
    }

    /// Check if a string is a valid hex string with the specified byte length
    /// - Parameters:
    ///   - hexString: The hex string to check
    ///   - expectedByteCount: The expected number of bytes (nil for any length)
    /// - Returns: True if the hex string is valid, false otherwise
    public static func isValidHex(_ hexString: String, expectedByteCount: Int? = nil) -> Bool {
        do {
            _ = try validateHex(hexString, expectedByteCount: expectedByteCount)
            return true
        } catch {
            return false
        }
    }

    /// Check if a string is a valid 32-byte hex string
    /// - Parameter hexString: The hex string to check
    /// - Returns: True if the hex string is valid 32-byte hex, false otherwise
    public static func isValid32ByteHex(_ hexString: String) -> Bool {
        return isValidHex(hexString, expectedByteCount: 32)
    }

    /// Check if a string is a valid 64-byte hex string
    /// - Parameter hexString: The hex string to check
    /// - Returns: True if the hex string is valid 64-byte hex, false otherwise
    public static func isValid64ByteHex(_ hexString: String) -> Bool {
        return isValidHex(hexString, expectedByteCount: 64)
    }

    // MARK: - Safe Data Conversion

    /// Safely convert a hex string to Data
    /// - Parameter hexString: The hex string to convert
    /// - Returns: The Data if valid, nil otherwise
    public static func data(from hexString: String) -> Data? {
        return try? validateHex(hexString)
    }

    /// Safely convert a 32-byte hex string to Data
    /// - Parameter hexString: The hex string to convert
    /// - Returns: The 32-byte Data if valid, nil otherwise
    public static func data32(from hexString: String) -> Data? {
        return try? validate32ByteHex(hexString)
    }

    /// Safely convert a 64-byte hex string to Data
    /// - Parameter hexString: The hex string to convert
    /// - Returns: The 64-byte Data if valid, nil otherwise
    public static func data64(from hexString: String) -> Data? {
        return try? validate64ByteHex(hexString)
    }
}
