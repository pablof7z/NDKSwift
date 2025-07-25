import Foundation

/// Centralized validation requirement descriptions to ensure consistency
public enum ValidationConstants {
    
    // MARK: - Hex Validation Requirements
    
    /// Expected format for 32-byte hex strings (public keys, private keys, event IDs)
    public static let hex64CharacterRequirement = "64 character hex"
    
    /// Expected format for 64-byte hex strings (signatures)
    public static let hex128CharacterRequirement = "128 character hex"
    
    /// Detailed requirement for 32-byte hex
    public static let hex64CharacterDetails = "Must be 64 character hex string"
    
    /// Generic hex format requirement
    public static let hexFormatRequirement = "hex format"
    
    // MARK: - Key Validation Requirements
    
    /// Private key validation requirement
    public static let privateKeyRequirement = "64 character hex string"
    
    /// Public key validation requirement  
    public static let publicKeyRequirement = "64 character hex"
    
    /// Key size requirement in bytes
    public static let keySize32Bytes = "32 bytes"
    
    /// Expected data size for bech32 decoding
    public static let expected32Bytes = "Expected 32 bytes"
    
    // MARK: - Format Expectations
    
    /// Format expectation with count
    /// - Parameter count: The actual character count received
    /// - Returns: Formatted expectation string
    public static func expectedHex64Got(_ count: Int) -> String {
        "Expected 64 character hex, got \(count)"
    }
    
    /// Format expectation for hex strings
    /// - Parameters:
    ///   - expected: Expected character count
    ///   - actual: Actual character count
    /// - Returns: Formatted expectation string
    public static func expectedHexLength(expected: Int, actual: Int) -> String {
        "Expected \(expected) character hex, got \(actual)"
    }
}