import CryptoSwift
import Foundation
import secp256k1

/// NIP-04: Encrypted Direct Messages (Deprecated)
///
/// This module implements the NIP-04 encryption standard for Nostr.
/// Note: NIP-04 is deprecated in favor of NIP-44, which provides better security.
/// This implementation is maintained for backward compatibility.
///
/// Issues with NIP-04:
/// - No padding (leaks message length)
/// - Uses AES-CBC which can be vulnerable to padding oracle attacks
/// - No authenticated encryption
/// - Weak key derivation
///
/// Specification: https://github.com/nostr-protocol/nips/blob/master/04.md
public enum NIP04 {

    /// Compute shared secret using ECDH
    /// - Parameters:
    ///   - privateKey: Sender's private key (hex)
    ///   - pubkey: Recipient's public key (hex)
    /// - Returns: 32-byte shared secret
    static func computeSharedSecret(privateKey: PrivateKey, pubkey: PublicKey) throws -> Data {
        let privKeyData: Data
        do {
            privKeyData = try HexValidator.validate32ByteHex(privateKey)
        } catch {
            throw Crypto.CryptoError.invalidKeyLength
        }

        let pubkeyData: Data
        do {
            pubkeyData = try HexValidator.validate32ByteHex(pubkey)
        } catch {
            throw Crypto.CryptoError.invalidKeyLength
        }

        // Create private key for key agreement
        let privKey = try secp256k1.KeyAgreement.PrivateKey(dataRepresentation: privKeyData)

        // For x-only pubkey, we need to try both possible y coordinates
        // First try with 02 prefix (even y)
        let fullPubkey = Data([0x02]) + pubkeyData

        let pubkey: secp256k1.KeyAgreement.PublicKey
        do {
            pubkey = try secp256k1.KeyAgreement.PublicKey(dataRepresentation: fullPubkey)
        } catch {
            // If that fails, try with 03 prefix (odd y)
            let fullPubkeyOdd = Data([0x03]) + pubkeyData
            pubkey = try secp256k1.KeyAgreement.PublicKey(dataRepresentation: fullPubkeyOdd)
        }

        // Get shared secret (returns x coordinate only)
        let sharedSecret = try privKey.sharedSecretFromKeyAgreement(with: pubkey)

        // Return the raw bytes (x-coordinate) as per NIP-04
        let sharedData = Data(sharedSecret.bytes)

        // If the shared secret has a prefix byte, remove it
        if sharedData.count == 33 && (sharedData[0] == 0x02 || sharedData[0] == 0x03) {
            return sharedData.dropFirst()
        }

        return sharedData
    }

    /// Encrypt a message using NIP-04
    /// - Parameters:
    ///   - message: The plaintext message to encrypt
    ///   - privateKey: Sender's private key (hex)
    ///   - pubkey: Recipient's public key (hex)
    /// - Returns: Encrypted message in format: base64(ciphertext)?iv=base64(iv)
    public static func encrypt(message: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        // Generate random IV
        let iv = Crypto.randomBytes(count: 16)

        // Compute shared secret via ECDH
        let sharedSecret = try computeSharedSecret(privateKey: privateKey, pubkey: pubkey)

        // Encrypt using AES-256-CBC with shared secret
        let encrypted = try encryptAES(message: message, key: sharedSecret, iv: iv)

        // Return in NIP-04 format: base64(ciphertext)?iv=base64(iv)
        return "\(encrypted.base64EncodedString())?iv=\(iv.base64EncodedString())"
    }

    /// Decrypt a message using NIP-04
    /// - Parameters:
    ///   - encrypted: Encrypted message in format: base64(ciphertext)?iv=base64(iv)
    ///   - privateKey: Recipient's private key (hex)
    ///   - pubkey: Sender's public key (hex)
    /// - Returns: Decrypted plaintext message
    public static func decrypt(encrypted: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        // Parse the encrypted format
        let parts = encrypted.split(separator: "?")
        guard parts.count == 2,
              let encryptedData = Data(base64Encoded: String(parts[0]))
        else {
            throw Crypto.CryptoError.invalidPoint
        }

        // Extract IV - must handle "iv=base64data" format
        let ivString = String(parts[1])
        guard ivString.hasPrefix("iv="),
              let iv = Data(base64Encoded: String(ivString.dropFirst(3)))
        else {
            throw Crypto.CryptoError.invalidPoint
        }

        // Compute shared secret via ECDH
        let sharedSecret = try computeSharedSecret(privateKey: privateKey, pubkey: pubkey)

        // Decrypt using AES-256-CBC with shared secret
        return try decryptAES(encrypted: encryptedData, key: sharedSecret, iv: iv)
    }

    private static func encryptAES(message: String, key: Data, iv: Data) throws -> Data {
        guard let messageData = message.data(using: .utf8) else {
            throw Crypto.CryptoError.invalidPoint
        }

        // Ensure key is 32 bytes for AES-256
        guard key.count == 32 else {
            throw Crypto.CryptoError.invalidKeyLength
        }

        // Apply PKCS7 padding
        let paddedData = try pkcs7Pad(messageData, blockSize: 16)

        let aes = try AES(key: Array(key), blockMode: CBC(iv: Array(iv)), padding: .noPadding)
        let encrypted = try aes.encrypt(Array(paddedData))

        return Data(encrypted)
    }

    private static func decryptAES(encrypted: Data, key: Data, iv: Data) throws -> String {
        // Ensure key is 32 bytes for AES-256
        guard key.count == 32 else {
            throw Crypto.CryptoError.invalidKeyLength
        }

        let aes = try AES(key: Array(key), blockMode: CBC(iv: Array(iv)), padding: .noPadding)
        let decrypted = try aes.decrypt(Array(encrypted))

        // Remove PKCS7 padding
        let unpaddedData = try pkcs7Unpad(Data(decrypted))

        guard let message = String(data: unpaddedData, encoding: .utf8) else {
            throw Crypto.CryptoError.invalidPoint
        }

        return message
    }

    /// PKCS7 padding
    private static func pkcs7Pad(_ data: Data, blockSize: Int) throws -> Data {
        let paddingLength = blockSize - (data.count % blockSize)
        let padding = Data(repeating: UInt8(paddingLength), count: paddingLength)
        return data + padding
    }

    /// Remove PKCS7 padding
    private static func pkcs7Unpad(_ data: Data) throws -> Data {
        guard let lastByte = data.last else {
            throw Crypto.CryptoError.invalidPoint
        }

        let paddingLength = Int(lastByte)
        guard paddingLength > 0 && paddingLength <= 16 && paddingLength <= data.count else {
            throw Crypto.CryptoError.invalidPoint
        }

        // Verify all padding bytes are the same
        let paddingStart = data.count - paddingLength
        for i in paddingStart..<data.count {
            if data[i] != lastByte {
                throw Crypto.CryptoError.invalidPoint
            }
        }

        return data.prefix(paddingStart)
    }
}

// MARK: - Convenience Extensions

public extension Crypto {
    /// Encrypt a message using NIP-04 (deprecated)
    static func nip04Encrypt(message: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        return try NIP04.encrypt(message: message, privateKey: privateKey, pubkey: pubkey)
    }

    /// Decrypt a message using NIP-04 (deprecated)
    static func nip04Decrypt(encrypted: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        return try NIP04.decrypt(encrypted: encrypted, privateKey: privateKey, pubkey: pubkey)
    }

    /// Compute shared secret using ECDH (for NIP-04 compatibility)
    static func computeSharedSecret(privateKey: PrivateKey, pubkey: PublicKey) throws -> Data {
        return try NIP04.computeSharedSecret(privateKey: privateKey, pubkey: pubkey)
    }
}