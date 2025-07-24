import Foundation

/// Constants for crypto operations
public enum CryptoConstants {
    
    /// Crypto operation names
    public enum Operation {
        /// Key derivation operation
        public static let keyDerivation = "Key derivation"
        
        /// Signing operation
        public static let signing = "Signing"
        
        /// Encryption operation
        public static let encryption = "Encryption"
        
        /// Decryption operation
        public static let decryption = "Decryption"
        
        /// Key generation operation
        public static let keyGeneration = "Key generation"
        
        /// Signature verification operation
        public static let signatureVerification = "Signature verification"
    }
    
    /// NIP identifiers for crypto operations
    public enum NIP {
        /// NIP-04 encryption standard
        public static let nip04 = "NIP-04"
        
        /// NIP-44 encryption standard
        public static let nip44 = "NIP-44"
        
        /// NIP-46 remote signer standard
        public static let nip46 = "NIP-46"
    }
}