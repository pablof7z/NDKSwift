import CryptoSwift
import Foundation
import P256K
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
            for i in 0 ..< 32 {
                bytes[i] = UInt8.random(in: 0 ... 255)
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
        let privKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privKeyData)
        let xonlyPubKey = privKey.publicKey.xonly
        return Data(xonlyPubKey.bytes).hexString
    }

    /// Sign a message with a private key using Schnorr signatures
    public static func sign(message: Data, privateKey: PrivateKey) throws -> Signature {
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }

        let privKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privKeyData)

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

        let xonlyKey = P256K.Schnorr.XonlyKey(dataRepresentation: pubKeyData)
        let schnorrSig = try P256K.Schnorr.SchnorrSignature(dataRepresentation: sigData)

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
            for i in 0 ..< count {
                bytes[i] = UInt8.random(in: 0 ... 255)
            }
        #endif
        return Data(bytes)
    }
}

/// NIP-04 Encryption (deprecated but still widely used)
public extension Crypto {
    /// Compute shared secret using ECDH
    static func computeSharedSecret(privateKey: PrivateKey, publicKey: PublicKey) throws -> Data {
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        guard let pubKeyData = Data(hexString: publicKey), pubKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        // Create private key for key agreement
        let privKey = try P256K.KeyAgreement.PrivateKey(dataRepresentation: privKeyData)
        
        // For x-only pubkey, we need to try both possible y coordinates
        // First try with 02 prefix (even y)
        let fullPubKey = Data([0x02]) + pubKeyData
        
        let pubKey: P256K.KeyAgreement.PublicKey
        do {
            pubKey = try P256K.KeyAgreement.PublicKey(dataRepresentation: fullPubKey)
        } catch {
            // If that fails, try with 03 prefix (odd y)
            let fullPubKeyOdd = Data([0x03]) + pubKeyData
            pubKey = try P256K.KeyAgreement.PublicKey(dataRepresentation: fullPubKeyOdd)
        }
        
        // Get shared secret (returns x coordinate only)
        let sharedSecret = try privKey.sharedSecretFromKeyAgreement(with: pubKey)
        
        // Return the raw bytes (x-coordinate) as per NIP-04
        let sharedData = Data(sharedSecret.bytes)
        
        // If the shared secret has a prefix byte, remove it
        if sharedData.count == 33 && (sharedData[0] == 0x02 || sharedData[0] == 0x03) {
            return sharedData.dropFirst()
        }
        
        return sharedData
    }
    
    /// Encrypt a message using NIP-04
    static func nip04Encrypt(message: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        // Generate random IV
        let iv = randomBytes(count: 16)
        
        // Compute shared secret via ECDH
        let sharedSecret = try computeSharedSecret(privateKey: privateKey, publicKey: publicKey)
        
        // Encrypt using AES-256-CBC with shared secret
        let encrypted = try encryptAES(message: message, key: sharedSecret, iv: iv)
        
        // Return in NIP-04 format: base64(ciphertext)?iv=base64(iv)
        return encrypted.base64EncodedString() + "?iv=" + iv.base64EncodedString()
    }

    /// Decrypt a message using NIP-04
    static func nip04Decrypt(encrypted: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        // Parse the encrypted format
        let parts = encrypted.split(separator: "?")
        guard parts.count == 2,
              let encryptedData = Data(base64Encoded: String(parts[0]))
        else {
            throw CryptoError.invalidPoint
        }
        
        // Extract IV - must handle "iv=base64data" format
        let ivString = String(parts[1])
        guard ivString.hasPrefix("iv="),
              let iv = Data(base64Encoded: String(ivString.dropFirst(3)))
        else {
            throw CryptoError.invalidPoint
        }
        
        // Compute shared secret via ECDH
        let sharedSecret = try computeSharedSecret(privateKey: privateKey, publicKey: publicKey)
        
        // Decrypt using AES-256-CBC with shared secret
        return try decryptAES(encrypted: encryptedData, key: sharedSecret, iv: iv)
    }

    private static func encryptAES(message: String, key: Data, iv: Data) throws -> Data {
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.invalidPoint
        }
        
        // Ensure key is 32 bytes for AES-256
        guard key.count == 32 else {
            throw CryptoError.invalidKeyLength
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
            throw CryptoError.invalidKeyLength
        }

        let aes = try AES(key: Array(key), blockMode: CBC(iv: Array(iv)), padding: .noPadding)
        let decrypted = try aes.decrypt(Array(encrypted))
        
        // Remove PKCS7 padding
        let unpaddedData = try pkcs7Unpad(Data(decrypted))

        guard let message = String(data: unpaddedData, encoding: .utf8) else {
            throw CryptoError.invalidPoint
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
            throw CryptoError.invalidPoint
        }
        
        let paddingLength = Int(lastByte)
        guard paddingLength > 0 && paddingLength <= 16 && paddingLength <= data.count else {
            throw CryptoError.invalidPoint
        }
        
        // Verify all padding bytes are the same
        let paddingStart = data.count - paddingLength
        for i in paddingStart..<data.count {
            if data[i] != lastByte {
                throw CryptoError.invalidPoint
            }
        }
        
        return data.prefix(paddingStart)
    }
}

/// NIP-44 Encryption (versioned, modern encryption standard)
public extension Crypto {
    /// NIP-44 specific errors
    enum NIP44Error: Error, LocalizedError {
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
    struct NIP44Constants {
        static let version: UInt8 = 0x02
        static let salt = "nip44-v2".data(using: .utf8)!
        static let minPlaintextSize = 1
        static let maxPlaintextSize = 65535
        static let minPaddedSize = 32
    }
    
    /// Calculate padded length for NIP-44
    static func nip44CalcPaddedLen(_ unpadded: Int) -> Int {
        if unpadded <= 32 {
            return 32
        }
        
        let nextPower = 1 << (Int(log2(Double(unpadded - 1))) + 1)
        let chunk = nextPower <= 256 ? 32 : nextPower / 8
        
        return chunk * ((unpadded - 1) / chunk + 1)
    }
    
    /// Pad plaintext according to NIP-44
    static func nip44Pad(_ plaintext: String) throws -> Data {
        guard let unpadded = plaintext.data(using: .utf8) else {
            throw CryptoError.invalidPoint
        }
        
        let unpadded_len = unpadded.count
        guard unpadded_len >= NIP44Constants.minPlaintextSize && 
              unpadded_len <= NIP44Constants.maxPlaintextSize else {
            throw NIP44Error.invalidPayloadSize
        }
        
        // Write length as big-endian uint16
        var padded = Data()
        padded.append(UInt8((unpadded_len >> 8) & 0xFF))
        padded.append(UInt8(unpadded_len & 0xFF))
        padded.append(unpadded)
        
        // Add zero padding
        let targetLen = nip44CalcPaddedLen(unpadded_len)
        let paddingLen = targetLen - unpadded_len
        if paddingLen > 0 {
            padded.append(Data(repeating: 0, count: paddingLen))
        }
        
        return padded
    }
    
    /// Unpad plaintext according to NIP-44
    static func nip44Unpad(_ padded: Data) throws -> String {
        guard padded.count >= 2 else {
            throw NIP44Error.invalidPadding
        }
        
        // Read big-endian uint16 length
        let unpadded_len = Int(padded[0]) << 8 | Int(padded[1])
        
        guard unpadded_len > 0,
              padded.count >= 2 + unpadded_len,
              padded.count == nip44CalcPaddedLen(unpadded_len) + 2 else {
            throw NIP44Error.invalidPadding
        }
        
        let unpadded = padded[2..<(2 + unpadded_len)]
        guard let plaintext = String(data: unpadded, encoding: .utf8) else {
            throw NIP44Error.invalidPadding
        }
        
        return plaintext
    }
    
    /// Get conversation key for NIP-44
    static func nip44GetConversationKey(privateKey: PrivateKey, publicKey: PublicKey) throws -> Data {
        // Compute shared secret using ECDH
        guard let privKeyData = Data(hexString: privateKey), privKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        guard let pubKeyData = Data(hexString: publicKey), pubKeyData.count == 32 else {
            throw CryptoError.invalidKeyLength
        }
        
        // Use secp256k1 ECDH to get shared x coordinate (unhashed)
        let privKey = try P256K.KeyAgreement.PrivateKey(dataRepresentation: privKeyData)
        
        // For x-only pubkey, we need to try both possible y coordinates
        // First try with 02 prefix (even y)
        let fullPubKey = Data([0x02]) + pubKeyData
        
        let pubKey: P256K.KeyAgreement.PublicKey
        do {
            pubKey = try P256K.KeyAgreement.PublicKey(dataRepresentation: fullPubKey)
        } catch {
            // If that fails, try with 03 prefix (odd y)
            let fullPubKeyOdd = Data([0x03]) + pubKeyData
            pubKey = try P256K.KeyAgreement.PublicKey(dataRepresentation: fullPubKeyOdd)
        }
        
        // Get shared secret (x coordinate only as per NIP-44)
        let sharedSecret = try privKey.sharedSecretFromKeyAgreement(with: pubKey)
        let shared_x = Data(sharedSecret.bytes)
        
        // Use HKDF-extract with sha256
        // For HKDF-extract, we need to use the salt as salt and shared_x as IKM
        let hkdf = try HKDF(password: Array(shared_x), salt: Array(NIP44Constants.salt), keyLength: 32, variant: .sha2(.sha256))
        let conversationKey = try hkdf.calculate()
        
        // HKDF-extract output is always 32 bytes for SHA256
        return Data(conversationKey.prefix(32))
    }
    
    /// Get message keys for NIP-44
    static func nip44GetMessageKeys(conversationKey: Data, nonce: Data) throws -> (chachaKey: Data, chachaNonce: Data, hmacKey: Data) {
        guard conversationKey.count == 32 else {
            throw CryptoError.invalidKeyLength
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
    
    /// Encrypt using NIP-44
    static func nip44Encrypt(plaintext: String, conversationKey: Data, nonce: Data) throws -> String {
        // Get message keys
        let (chachaKey, chachaNonce, hmacKey) = try nip44GetMessageKeys(conversationKey: conversationKey, nonce: nonce)
        
        // Pad plaintext
        let padded = try nip44Pad(plaintext)
        
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
        payload.append(NIP44Constants.version)
        payload.append(nonce)
        payload.append(Data(ciphertext))
        payload.append(Data(mac))
        
        return payload.base64EncodedString()
    }
    
    /// Decrypt using NIP-44
    static func nip44Decrypt(payload: String, conversationKey: Data) throws -> String {
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
        guard version == NIP44Constants.version else {
            throw NIP44Error.unsupportedVersion
        }
        
        let nonce = data[1..<33]
        let ciphertext = data[33..<(dlen - 32)]
        let mac = data[(dlen - 32)..<dlen]
        
        // Get message keys
        let (chachaKey, chachaNonce, hmacKey) = try nip44GetMessageKeys(conversationKey: conversationKey, nonce: Data(nonce))
        
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
        return try nip44Unpad(Data(decrypted))
    }
    
    /// High-level NIP-44 encrypt function using private/public keys
    static func nip44Encrypt(message: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        let conversationKey = try nip44GetConversationKey(privateKey: privateKey, publicKey: publicKey)
        let nonce = randomBytes(count: 32)
        return try nip44Encrypt(plaintext: message, conversationKey: conversationKey, nonce: nonce)
    }
    
    /// High-level NIP-44 decrypt function using private/public keys
    static func nip44Decrypt(encrypted: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        let conversationKey = try nip44GetConversationKey(privateKey: privateKey, publicKey: publicKey)
        return try nip44Decrypt(payload: encrypted, conversationKey: conversationKey)
    }
}
