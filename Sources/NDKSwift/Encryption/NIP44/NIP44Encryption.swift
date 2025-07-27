import Foundation
import CryptoKit

import CryptoSwift
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
    public enum NIP44Error: LocalizedError {
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
                return ErrorMessageConstants.withContext(ErrorMessageConstants.invalid("payload size"), context: "must be \(Constants.minPayloadSize)-\(Constants.maxPayloadSize) chars")
            case .invalidDataSize:
                return ErrorMessageConstants.withContext(ErrorMessageConstants.invalid("data size"), context: "must be \(Constants.minDataSize)-\(Constants.maxDataSize) bytes")
            case .invalidMAC:
                return ErrorMessageConstants.invalid("message authentication code")
            case .invalidPadding:
                return ErrorMessageConstants.invalid("padding format")
            case .invalidNonce:
                return ErrorMessageConstants.withContext(ErrorMessageConstants.invalid("nonce"), context: "must be \(Constants.nonceSize) bytes")
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
        static let minPayloadSize = 132
        static let maxPayloadSize = 87472
        static let minDataSize = 99
        static let maxDataSize = 65603
        static let nonceSize = 32
        static let sharedSecretSize = 32
        static let conversationKeySize = 32
        static let macSize = 32
        static let chunkSizeThreshold = 256
        static let expandedKeySize = 76  // 32 (chacha key) + 12 (nonce) + 32 (hmac key)
        static let chachaKeySize = 32
        static let chachaNonceSize = 12
        static let hmacKeySize = 32
    }

    /// Calculate padded length for NIP-44
    public static func calcPaddedLen(_ unpadded: Int) -> Int {
        if unpadded <= Constants.minPaddedSize {
            return Constants.minPaddedSize
        }

        // Use floor(log2()) explicitly to match nostr-tools
        let log = floor(log2(Double(unpadded - 1)))
        let nextPower = 1 << (Int(log) + 1)
        let chunk = nextPower <= Constants.chunkSizeThreshold ? Constants.minPaddedSize : nextPower / 8

        // Use floor division explicitly
        return chunk * (((unpadded - 1) / chunk) + 1)
    }

    /// Pad plaintext according to NIP-44
    static func pad(_ plaintext: String) throws -> Data {
        guard let unpadded = plaintext.data(using: .utf8) else {
            throw Crypto.CryptoError.invalidPoint
        }

        let unpaddedLen = unpadded.count
        guard unpaddedLen >= Constants.minPlaintextSize &&
              unpaddedLen <= Constants.maxPlaintextSize else {
            throw NIP44Error.invalidPayloadSize
        }

        // Write length as big-endian uint16
        var padded = Data()
        padded.append(UInt8((unpaddedLen >> 8) & 0xFF))
        padded.append(UInt8(unpaddedLen & 0xFF))
        padded.append(unpadded)

        // Add zero padding
        let targetLen = calcPaddedLen(unpaddedLen)
        let paddingLen = targetLen - unpaddedLen
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
        let unpaddedLen = Int(padded[0]) << 8 | Int(padded[1])

        guard unpaddedLen > 0,
              padded.count >= 2 + unpaddedLen,
              padded.count == calcPaddedLen(unpaddedLen) + 2 else {
            throw NIP44Error.invalidPadding
        }

        let unpadded = padded[2..<(2 + unpaddedLen)]
        guard let plaintext = String(data: unpadded, encoding: .utf8) else {
            throw NIP44Error.invalidPadding
        }

        return plaintext
    }

    /// Get conversation key for NIP-44
    /// - Parameters:
    ///   - privateKey: Sender's private key (hex)
    ///   - pubkey: Recipient's public key (hex)
    /// - Returns: 32-byte conversation key
    public static func getConversationKey(privateKey: PrivateKey, pubkey: PublicKey) throws -> Data {
        // Compute shared secret using ECDH
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw Crypto.CryptoError.invalidKeyLength
        }

        guard let pubkeyData = Data(hexString: pubkey), pubkeyData.count == 32 else {
            throw Crypto.CryptoError.invalidKeyLength
        }

        // Try both possible y-coordinate parities (even=0x02, odd=0x03)
        // Nostr uses x-only keys, so we need to try both possibilities
        var pubkey = secp256k1_pubkey()

        // First try with even y-coordinate (0x02 prefix)
        var publicKeyBytes = [UInt8]([0x02]) + [UInt8](pubkeyData)
        var parseResult = secp256k1_ec_pubkey_parse(secp256k1.Context.rawRepresentation, &pubkey, publicKeyBytes, publicKeyBytes.count)

        // If that fails, try with odd y-coordinate (0x03 prefix)
        if parseResult != 1 {
            publicKeyBytes[0] = 0x03
            parseResult = secp256k1_ec_pubkey_parse(secp256k1.Context.rawRepresentation, &pubkey, publicKeyBytes, publicKeyBytes.count)
        }

        guard parseResult == 1 else {
            throw Crypto.CryptoError.invalidPoint
        }

        // Compute shared secret using custom ECDH that extracts only x-coordinate
        var sharedSecret = [UInt8](repeating: 0, count: Constants.sharedSecretSize)
        let privateKeyBytes = [UInt8](privKeyData)

        // Use secp256k1_ecdh with custom callback to extract only x-coordinate
        guard secp256k1_ecdh(secp256k1.Context.rawRepresentation, &sharedSecret, &pubkey, privateKeyBytes, { (output, x32, _, _) in
            // Copy only the x-coordinate (32 bytes for secp256k1)
            memcpy(output, x32, Constants.sharedSecretSize)
            return 1
        }, nil) != 0 else {
            throw Crypto.CryptoError.invalidPoint
        }

        // Use HKDF-extract with sha256 using CryptoKit
        let salt = Data("nip44-v2".utf8)
        let conversationKey = CryptoKit.HKDF<CryptoKit.SHA256>.extract(
            inputKeyMaterial: SymmetricKey(data: Data(sharedSecret)),
            salt: salt
        )

        return Data(conversationKey)
    }

    /// Get message keys for NIP-44
    static func getMessageKeys(conversationKey: Data, nonce: Data) throws -> (chachaKey: Data, chachaNonce: Data, hmacKey: Data) {
        guard conversationKey.count == Constants.conversationKeySize else {
            throw Crypto.CryptoError.invalidKeyLength
        }
        guard nonce.count == Constants.nonceSize else {
            throw NIP44Error.invalidNonce
        }

        // Use HKDF-expand with sha256 using CryptoKit
        let keys = CryptoKit.HKDF<CryptoKit.SHA256>.expand(
            pseudoRandomKey: SymmetricKey(data: conversationKey),
            info: nonce,
            outputByteCount: Constants.expandedKeySize
        )

        // Convert SymmetricKey to Data
        let keysData = keys.withUnsafeBytes { Data($0) }
        let chachaKey = Data(keysData[0..<32])
        let chachaNonce = Data(keysData[32..<44])
        let hmacKey = Data(keysData[44..<76])

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

        // Calculate HMAC using CryptoKit
        let mac = CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(
            for: aad,
            using: SymmetricKey(data: hmacKey)
        )

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
        guard plen >= Constants.minPayloadSize && plen <= Constants.maxPayloadSize else {
            throw NIP44Error.invalidPayloadSize
        }

        // Decode base64
        guard let data = Data(base64Encoded: payload) else {
            throw NIP44Error.invalidPayloadSize
        }

        let dlen = data.count
        guard dlen >= Constants.minDataSize && dlen <= Constants.maxDataSize else {
            throw NIP44Error.invalidDataSize
        }

        // Parse components
        let version = data[0]
        guard version == Constants.version else {
            throw NIP44Error.unsupportedVersion
        }

        let nonce = data[1..<(1 + Constants.nonceSize)]
        let ciphertext = data[(1 + Constants.nonceSize)..<(dlen - Constants.macSize)]
        let mac = data[(dlen - Constants.macSize)..<dlen]

        // Get message keys
        let (chachaKey, chachaNonce, hmacKey) = try getMessageKeys(conversationKey: conversationKey, nonce: Data(nonce))

        // Verify MAC
        var aad = Data()
        aad.append(nonce)
        aad.append(ciphertext)

        // Calculate HMAC using CryptoKit
        let calculatedMac = CryptoKit.HMAC<CryptoKit.SHA256>.authenticationCode(
            for: aad,
            using: SymmetricKey(data: hmacKey)
        )

        // Verify MAC
        guard Data(calculatedMac) == mac else {
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
    ///   - pubkey: Recipient's public key (hex)
    /// - Returns: Base64-encoded encrypted payload
    public static func encrypt(message: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        let conversationKey = try getConversationKey(privateKey: privateKey, pubkey: pubkey)
        let nonce = Crypto.randomBytes(count: Constants.nonceSize)
        return try encrypt(plaintext: message, conversationKey: conversationKey, nonce: nonce)
    }

    /// High-level decrypt function using private/public keys
    /// - Parameters:
    ///   - encrypted: Base64-encoded encrypted payload
    ///   - privateKey: Recipient's private key (hex)
    ///   - pubkey: Sender's public key (hex)
    /// - Returns: Decrypted plaintext message
    public static func decrypt(encrypted: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        let conversationKey = try getConversationKey(privateKey: privateKey, pubkey: pubkey)
        return try decrypt(payload: encrypted, conversationKey: conversationKey)
    }
}

// MARK: - Note: Crypto extensions moved to Crypto.swift to fix compilation ordering