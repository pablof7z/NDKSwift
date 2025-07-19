import CryptoSwift
import Foundation
import secp256k1
#if canImport(Security)
    import Security
#endif

/// Cryptographic utilities for Nostr
public enum Crypto {
    /// Cryptographic constants
    public enum Constants {
        /// secp256k1 private key size in bytes
        public static let privateKeySize = 32
        /// secp256k1 signature size in bytes
        public static let signatureSize = 64
    }
    
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
                return "Invalid key length (expected \(Constants.privateKeySize) bytes)"
            case .invalidSignatureLength:
                return "Invalid signature length (expected \(Constants.signatureSize) bytes)"
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
        return randomBytes(count: Constants.privateKeySize).hexString
    }

    /// Derive public key from private key using secp256k1
    public static func getPublicKey(from privateKey: PrivateKey) throws -> PublicKey {
        let privKeyData: Data
        do {
            privKeyData = try HexValidator.validate32ByteHex(privateKey)
        } catch {
            throw CryptoError.invalidKeyLength
        }

        // For Schnorr signatures in Nostr, we need the x-only public key (32 bytes)
        let privKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privKeyData)
        let xonlyPubKey = privKey.publicKey.xonly
        return Data(xonlyPubKey.bytes).hexString
    }

    /// Sign a message with a private key using Schnorr signatures
    public static func sign(message: Data, privateKey: PrivateKey) throws -> Signature {
        let privKeyData: Data
        do {
            privKeyData = try HexValidator.validate32ByteHex(privateKey)
        } catch {
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
        let sigData: Data
        do {
            sigData = try HexValidator.validate64ByteHex(signature)
        } catch {
            throw CryptoError.invalidSignatureLength
        }

        let pubKeyData: Data
        do {
            pubKeyData = try HexValidator.validate32ByteHex(publicKey)
        } catch {
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
            for i in 0 ..< count {
                bytes[i] = UInt8.random(in: 0 ... 255)
            }
        #endif
        return Data(bytes)
    }

    // MARK: - NIP-44 Encryption
    
    /// Encrypt a message using NIP-44
    static func nip44Encrypt(message: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        return try NIP44.encrypt(message: message, privateKey: privateKey, publicKey: publicKey)
    }
    
    /// Decrypt a message using NIP-44
    static func nip44Decrypt(encrypted: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        return try NIP44.decrypt(encrypted: encrypted, privateKey: privateKey, publicKey: publicKey)
    }
    
    typealias NIP44Error = NIP44.NIP44Error
}

