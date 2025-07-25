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
    
    /// Key format constants
    public enum KeyFormat {
        /// Length of a compressed secp256k1 public key in hex format (33 bytes * 2)
        public static let compressedPublicKeyHexLength = 66
        
        /// Valid prefixes for compressed secp256k1 public keys
        public static let compressedPublicKeyPrefixes = ["02", "03"]
    }
}