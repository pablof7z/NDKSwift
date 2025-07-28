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
        
        /// Compressed pubkey prefix for even y-coordinate
        public static let compressedPubkeyPrefixEven: UInt8 = 0x02
        
        /// Compressed pubkey prefix for odd y-coordinate
        public static let compressedPubkeyPrefixOdd: UInt8 = 0x03
    }
    
    /// Common crypto sizes in bytes
    public enum Size {
        /// Size of a private key in bytes
        public static let privateKey = 32
        
        /// Size of a public key in bytes (uncompressed x-coordinate only)
        public static let publicKey = 32
        
        /// Size of a signature in bytes
        public static let signature = 64
        
        /// Size of an event ID in bytes (SHA-256 hash)
        public static let eventId = 32
        
        /// Size of a shared secret in bytes
        public static let sharedSecret = 32
        
        /// Size of a conversation key in bytes (NIP-44)
        public static let conversationKey = 32
        
        /// Size of a nonce in bytes (NIP-44)
        public static let nonce = 32
        
        /// Size of a MAC in bytes (NIP-44)
        public static let mac = 32
    }
}