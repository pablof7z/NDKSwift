import CryptoSwift
import Foundation
import secp256k1

/// NIP-44: Encrypted Direct Messages (Version 2)
/// 
/// This module implements the NIP-44 encryption standard for Nostr, providing
/// end-to-end encrypted messaging with forward secrecy and improved security
/// over the deprecated NIP-04 standard.
///
/// Key features:
/// - ChaCha20 encryption with Poly1305 authentication
/// - HKDF key derivation for conversation and message keys
/// - Padding to hide message lengths
/// - Version byte for future extensibility
///
/// Specification: https://github.com/nostr-protocol/nips/blob/master/44.md
public enum NIP44 {
    
    /// NIP-44 specific errors
    public enum NIP44Error: Error, LocalizedError {
        case unsupportedVersion
        case invalidPayloadSize
        case invalidDataSize
        case invalidMAC
        case invalidPadding
        case invalidNonce
        
        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return "Unsupported NIP-44 version"
            case .invalidPayloadSize:
                return "Invalid payload size (must be 132-87472 chars)"
            case .invalidDataSize:
                return "Invalid data size (must be 99-65603 bytes)"
            case .invalidMAC:
                return "Invalid message authentication code"
            case .invalidPadding:
                return "Invalid padding format"
            case .invalidNonce:
                return "Invalid nonce (must be 32 bytes)"
            }
        }
    }
    
    /// NIP-44 constants
    private struct Constants {
        static let version: UInt8 = 0x02
        static let salt = "nip44-v2".data(using: .utf8)!
        static let minPlaintextSize = 1
        static let maxPlaintextSize = 65535
        static let minPaddedSize = 32
    }
    
    /// Calculate padded length for NIP-44
    public static func calcPaddedLen(_ unpadded: Int) -> Int {
        if unpadded <= 32 {
            return 32
        }
        
        let nextPower = 1 << (Int(log2(Double(unpadded - 1))) + 1)
        let chunk = nextPower <= 256 ? 32 : nextPower / 8
        
        return chunk * ((unpadded - 1) / chunk + 1)
    }
    
    /// Pad plaintext according to NIP-44
    static func pad(_ plaintext: String) throws -> Data {
        guard let unpadded = plaintext.data(using: .utf8) else {
            throw Crypto.CryptoError.invalidPoint
        }
        
        let unpadded_len = unpadded.count
        guard unpadded_len >= Constants.minPlaintextSize && 
              unpadded_len <= Constants.maxPlaintextSize else {
            throw NIP44Error.invalidPayloadSize
        }
        
        // Write length as big-endian uint16
        var padded = Data()
        padded.append(UInt8((unpadded_len >> 8) & 0xFF))
        padded.append(UInt8(unpadded_len & 0xFF))
        padded.append(unpadded)
        
        // Add zero padding
        let targetLen = calcPaddedLen(unpadded_len)
        let paddingLen = targetLen - unpadded_len
        if paddingLen > 0 {
            padded.append(Data(repeating: 0, count: paddingLen))
        }
        
        return padded
    }
    
    /// Unpad plaintext according to NIP-44
    static func unpad(_ padded: Data) throws -> String {
        guard padded.count >= 2 else {
            throw NIP44Error.invalidPadding
        }
        
        // Read big-endian uint16 length
        let unpadded_len = Int(padded[0]) << 8 | Int(padded[1])
        
        guard unpadded_len > 0,
              padded.count >= 2 + unpadded_len,
              padded.count == calcPaddedLen(unpadded_len) + 2 else {
            throw NIP44Error.invalidPadding
        }
        
        let unpadded = padded[2..<(2 + unpadded_len)]
        guard let plaintext = String(data: unpadded, encoding: .utf8) else {
            throw NIP44Error.invalidPadding
        }
        
        return plaintext
    }
    
    /// Get conversation key for NIP-44
    /// - Parameters:
    ///   - privateKey: Sender's private key (hex)
    ///   - publicKey: Recipient's public key (hex)
    /// - Returns: 32-byte conversation key
    public static func getConversationKey(privateKey: PrivateKey, publicKey: PublicKey) throws -> Data {
        // Compute shared secret using ECDH
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw Crypto.CryptoError.invalidKeyLength
        }
        
        guard let pubKeyData = Data(hexString: publicKey), pubKeyData.count == 32 else {
            throw Crypto.CryptoError.invalidKeyLength
        }
        
        // Use secp256k1 ECDH to get shared x coordinate (unhashed)
        let privKey = try secp256k1.KeyAgreement.PrivateKey(dataRepresentation: privKeyData)
        
        // For x-only pubkey, we need to try both possible y coordinates
        // First try with 02 prefix (even y)
        let fullPubKey = Data([0x02]) + pubKeyData
        
        let pubKey: secp256k1.KeyAgreement.PublicKey
        do {
            pubKey = try secp256k1.KeyAgreement.PublicKey(dataRepresentation: fullPubKey)
        } catch {
            // If that fails, try with 03 prefix (odd y)
            let fullPubKeyOdd = Data([0x03]) + pubKeyData
            pubKey = try secp256k1.KeyAgreement.PublicKey(dataRepresentation: fullPubKeyOdd)
        }
        
        // Get shared secret (x coordinate only as per NIP-44)
        let sharedSecret = try privKey.sharedSecretFromKeyAgreement(with: pubKey)
        let shared_x = Data(sharedSecret.bytes)
        
        // Use HKDF-extract with sha256
        // For HKDF-extract, we need to use the salt as salt and shared_x as IKM
        let hkdf = try HKDF(password: Array(shared_x), salt: Array(Constants.salt), keyLength: 32, variant: .sha2(.sha256))
        let conversationKey = try hkdf.calculate()
        
        // HKDF-extract output is always 32 bytes for SHA256
        return Data(conversationKey.prefix(32))
    }
    
    /// Get message keys for NIP-44
    static func getMessageKeys(conversationKey: Data, nonce: Data) throws -> (chachaKey: Data, chachaNonce: Data, hmacKey: Data) {
        guard conversationKey.count == 32 else {
            throw Crypto.CryptoError.invalidKeyLength
        }
        guard nonce.count == 32 else {
            throw NIP44Error.invalidNonce
        }
        
        // Use HKDF-expand with sha256
        let hkdf = try HKDF(password: Array(conversationKey), info: Array(nonce), keyLength: 76, variant: .sha2(.sha256))
        let keys = try hkdf.calculate()
        
        let chachaKey = Data(keys[0..<32])
        let chachaNonce = Data(keys[32..<44])
        let hmacKey = Data(keys[44..<76])
        
        return (chachaKey, chachaNonce, hmacKey)
    }
    
    /// Encrypt using NIP-44 with explicit nonce (for testing)
    static func encrypt(plaintext: String, conversationKey: Data, nonce: Data) throws -> String {
        // Get message keys
        let (chachaKey, chachaNonce, hmacKey) = try getMessageKeys(conversationKey: conversationKey, nonce: nonce)
        
        // Pad plaintext
        let padded = try pad(plaintext)
        
        // Encrypt with ChaCha20
        let chacha = try ChaCha20(key: Array(chachaKey), iv: Array(chachaNonce))
        let ciphertext = try chacha.encrypt(Array(padded))
        
        // Calculate HMAC with AAD (nonce + ciphertext)
        var aad = Data()
        aad.append(nonce)
        aad.append(Data(ciphertext))
        
        let hmac = HMAC(key: Array(hmacKey), variant: .sha2(.sha256))
        let mac = try hmac.authenticate(Array(aad))
        
        // Construct payload: version + nonce + ciphertext + mac
        var payload = Data()
        payload.append(Constants.version)
        payload.append(nonce)
        payload.append(Data(ciphertext))
        payload.append(Data(mac))
        
        return payload.base64EncodedString()
    }
    
    /// Decrypt using NIP-44
    public static func decrypt(payload: String, conversationKey: Data) throws -> String {
        // Check for future-proof flag
        if payload.hasPrefix("#") {
            throw NIP44Error.unsupportedVersion
        }
        
        // Validate base64 length
        let plen = payload.count
        guard plen >= 132 && plen <= 87472 else {
            throw NIP44Error.invalidPayloadSize
        }
        
        // Decode base64
        guard let data = Data(base64Encoded: payload) else {
            throw NIP44Error.invalidPayloadSize
        }
        
        let dlen = data.count
        guard dlen >= 99 && dlen <= 65603 else {
            throw NIP44Error.invalidDataSize
        }
        
        // Parse components
        let version = data[0]
        guard version == Constants.version else {
            throw NIP44Error.unsupportedVersion
        }
        
        let nonce = data[1..<33]
        let ciphertext = data[33..<(dlen - 32)]
        let mac = data[(dlen - 32)..<dlen]
        
        // Get message keys
        let (chachaKey, chachaNonce, hmacKey) = try getMessageKeys(conversationKey: conversationKey, nonce: Data(nonce))
        
        // Verify MAC
        var aad = Data()
        aad.append(nonce)
        aad.append(ciphertext)
        
        let hmac = HMAC(key: Array(hmacKey), variant: .sha2(.sha256))
        let calculatedMac = try hmac.authenticate(Array(aad))
        
        // Constant-time comparison
        guard mac.count == calculatedMac.count else {
            throw NIP44Error.invalidMAC
        }
        
        var equal = true
        for i in 0..<mac.count {
            equal = equal && (mac[i] == calculatedMac[i])
        }
        
        guard equal else {
            throw NIP44Error.invalidMAC
        }
        
        // Decrypt with ChaCha20
        let chacha = try ChaCha20(key: Array(chachaKey), iv: Array(chachaNonce))
        let decrypted = try chacha.decrypt(Array(ciphertext))
        
        // Unpad plaintext
        return try unpad(Data(decrypted))
    }
    
    /// High-level encrypt function using private/public keys
    /// - Parameters:
    ///   - message: The plaintext message to encrypt
    ///   - privateKey: Sender's private key (hex)
    ///   - publicKey: Recipient's public key (hex)
    /// - Returns: Base64-encoded encrypted payload
    public static func encrypt(message: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        let conversationKey = try getConversationKey(privateKey: privateKey, publicKey: publicKey)
        let nonce = Crypto.randomBytes(count: 32)
        return try encrypt(plaintext: message, conversationKey: conversationKey, nonce: nonce)
    }
    
    /// High-level decrypt function using private/public keys
    /// - Parameters:
    ///   - encrypted: Base64-encoded encrypted payload
    ///   - privateKey: Recipient's private key (hex)
    ///   - publicKey: Sender's public key (hex)
    /// - Returns: Decrypted plaintext message
    public static func decrypt(encrypted: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        let conversationKey = try getConversationKey(privateKey: privateKey, publicKey: publicKey)
        return try decrypt(payload: encrypted, conversationKey: conversationKey)
    }
}

// MARK: - Note: Crypto extensions moved to Crypto.swift to fix compilation ordering