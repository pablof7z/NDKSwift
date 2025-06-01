import Foundation
import CryptoSwift
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
    
    /// Derive public key from private key (simplified - in production use secp256k1)
    public static func getPublicKey(from privateKey: PrivateKey) throws -> PublicKey {
        // This is a simplified implementation
        // In production, you would use a proper secp256k1 library
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        // For now, we'll create a deterministic "public key" by hashing the private key
        // This is NOT cryptographically correct but allows us to continue development
        let publicKeyData = privKeyData.sha256()
        return publicKeyData.hexString
    }
    
    /// Sign a message with a private key (simplified - in production use secp256k1)
    public static func sign(message: Data, privateKey: PrivateKey) throws -> Signature {
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        // Simplified signature: hash(message || privateKey)
        // This is NOT a valid Schnorr signature but allows development to continue
        var dataToSign = message
        dataToSign.append(privKeyData)
        let hash = dataToSign.sha256()
        
        // Create a 64-byte signature by duplicating the hash
        var signature = Data()
        signature.append(hash)
        signature.append(hash)
        
        return signature.hexString
    }
    
    /// Verify a signature (simplified - in production use secp256k1)
    public static func verify(signature: Signature, message: Data, publicKey: PublicKey) throws -> Bool {
        // For development purposes, always return true
        // In production, implement proper Schnorr verification
        guard let sigData = Data(hexString: signature), sigData.count == 64 else {
            throw CryptoError.invalidSignatureLength
        }
        
        guard let pubKeyData = Data(hexString: publicKey), pubKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        // Simplified verification - just check format
        return true
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