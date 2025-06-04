import Foundation
import CryptoSwift
import secp256k1
#if canImport(Security)
import Security
#endif

/// Cryptographic utilities for Nostr
public enum Crypto {
    
    /// Errors that can occur during cryptographic operations
    public enum CryptoError: Error, LocalizedError {
        case invalidKeyLength
        case invalidSignatureLength
        case signingFailed
        case verificationFailed
        case invalidPoint
        case invalidScalar
        
        public var errorDescription: String? {
            switch self {
            case .invalidKeyLength:
                return "Invalid key length (expected 32 bytes)"
            case .invalidSignatureLength:
                return "Invalid signature length (expected 64 bytes)"
            case .signingFailed:
                return "Failed to sign message"
            case .verificationFailed:
                return "Failed to verify signature"
            case .invalidPoint:
                return "Invalid elliptic curve point"
            case .invalidScalar:
                return "Invalid scalar value"
            }
        }
    }
    
    /// Generate a new private key
    public static func generatePrivateKey() -> PrivateKey {
        var bytes = [UInt8](repeating: 0, count: 32)
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        #else
        // Fallback for Linux
        for i in 0..<32 {
            bytes[i] = UInt8.random(in: 0...255)
        }
        #endif
        return Data(bytes).hexString
    }
    
    /// Derive public key from private key using secp256k1
    public static func getPublicKey(from privateKey: PrivateKey) throws -> PublicKey {
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        // For Schnorr signatures in Nostr, we need the x-only public key (32 bytes)
        let privKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privKeyData)
        let xonlyPubKey = privKey.xonly
        return Data(xonlyPubKey.bytes).hexString
    }
    
    /// Sign a message with a private key using Schnorr signatures
    public static func sign(message: Data, privateKey: PrivateKey) throws -> Signature {
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        let privKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privKeyData)
        
        // For Nostr, we sign the message directly (it's already the event ID hash)
        // We pass nil for auxiliaryRand to use the default BIP340 nonce function
        var messageBytes = Array(message)
        let signature = try privKey.signature(message: &messageBytes, auxiliaryRand: nil)
        
        return signature.dataRepresentation.hexString
    }
    
    /// Verify a signature using Schnorr verification
    public static func verify(signature: Signature, message: Data, publicKey: PublicKey) throws -> Bool {
        guard let sigData = Data(hexString: signature), sigData.count == 64 else {
            throw CryptoError.invalidSignatureLength
        }
        
        guard let pubKeyData = Data(hexString: publicKey), pubKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        let xonlyKey = secp256k1.Schnorr.XonlyKey(dataRepresentation: pubKeyData)
        let schnorrSig = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: sigData)
        
        var messageBytes = Array(message)
        return xonlyKey.isValid(schnorrSig, for: &messageBytes)
    }
    
    /// SHA256 hash
    public static func sha256(_ data: Data) -> Data {
        return data.sha256()
    }
    
    /// Generate random bytes
    public static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        #else
        // Fallback for Linux
        for i in 0..<count {
            bytes[i] = UInt8.random(in: 0...255)
        }
        #endif
        return Data(bytes)
    }
}

/// NIP-04 Encryption (deprecated but still used)
public extension Crypto {
    
    /// Encrypt a message using NIP-04
    static func nip04Encrypt(message: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        // Simplified implementation for development
        // In production, use proper ECDH and AES encryption
        let iv = randomBytes(count: 16)
        let encrypted = try encryptAES(message: message, key: privateKey + publicKey, iv: iv)
        
        return encrypted.base64EncodedString() + "?iv=" + iv.base64EncodedString()
    }
    
    /// Decrypt a message using NIP-04
    static func nip04Decrypt(encrypted: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        // Simplified implementation for development
        let parts = encrypted.split(separator: "?")
        guard parts.count == 2,
              let encryptedData = Data(base64Encoded: String(parts[0])),
              let ivPart = parts[1].split(separator: "=").last,
              let iv = Data(base64Encoded: String(ivPart)) else {
            throw CryptoError.invalidPoint
        }
        
        return try decryptAES(encrypted: encryptedData, key: privateKey + publicKey, iv: iv)
    }
    
    private static func encryptAES(message: String, key: String, iv: Data) throws -> Data {
        guard let messageData = message.data(using: .utf8),
              let keyData = Data(hexString: key) else {
            throw CryptoError.invalidPoint
        }
        
        // Use first 32 bytes of key for AES-256
        let aesKey = Array(keyData.prefix(32))
        let aes = try AES(key: aesKey, blockMode: CBC(iv: Array(iv)))
        let encrypted = try aes.encrypt(Array(messageData))
        
        return Data(encrypted)
    }
    
    private static func decryptAES(encrypted: Data, key: String, iv: Data) throws -> String {
        guard let keyData = Data(hexString: key) else {
            throw CryptoError.invalidPoint
        }
        
        let aesKey = Array(keyData.prefix(32))
        let aes = try AES(key: aesKey, blockMode: CBC(iv: Array(iv)))
        let decrypted = try aes.decrypt(Array(encrypted))
        
        guard let message = String(data: Data(decrypted), encoding: .utf8) else {
            throw CryptoError.invalidPoint
        }
        
        return message
    }
}