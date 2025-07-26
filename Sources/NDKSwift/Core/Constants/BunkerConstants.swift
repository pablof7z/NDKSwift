import Foundation

/// Constants for Bunker operations
public enum BunkerConstants {
    /// Error domain for bunker errors
    public static let errorDomain = "BunkerError"
    
    /// Relay name used in errors
    public static let relayName = "bunker"
    
    /// URL scheme for bunker
    public static let urlScheme = "bunker"
    
    /// Error messages
    public enum ErrorMessages {
        public static let pubkeyNotSet = "Bunker pubkey not set"
        public static let noResponseReceived = "No response received"
        public static let connectionRequired = "bunker connection"
        public static let ndkInstanceRequired = "NDK instance required for bunker signer"
        public static let requiredDataMissing = "required bunker signer data"
    }
}