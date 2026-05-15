import CryptoSwift
import Foundation
import secp256k1
#if canImport(Security)
    import Security
#endif
#if os(Linux)
    import Glibc
#endif

/// Cryptographic utilities for Nostr
public enum Crypto {
    /// Cryptographic constants
    public enum Constants {
        /// secp256k1 private key size in bytes
        public static let privateKeySize = CryptoConstants.Size.privateKey
        /// secp256k1 signature size in bytes
        public static let signatureSize = CryptoConstants.Size.signature
    }

    /// Errors that can occur during cryptographic operations
    public enum CryptoError: LocalizedError, Equatable {
        case invalidKeyLength
        case invalidSignatureLength
        case signingFailed
        case verificationFailed
        case invalidPoint
        case invalidScalar
        case randomGenerationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidKeyLength:
                return ErrorMessageConstants.invalid("key length (expected \(Constants.privateKeySize) bytes)")
            case .invalidSignatureLength:
                return ErrorMessageConstants.invalid("signature length (expected \(Constants.signatureSize) bytes)")
            case .signingFailed:
                return ErrorMessageConstants.Messages.signingFailed
            case .verificationFailed:
                return ErrorMessageConstants.Messages.verificationFailed
            case .invalidPoint:
                return ErrorMessageConstants.invalid("elliptic curve point")
            case .invalidScalar:
                return ErrorMessageConstants.invalid("scalar value")
            case .randomGenerationFailed(let reason):
                return "Failed to generate secure random bytes: \(reason)"
            }
        }
    }

    /// Generate a new private key (internal use only - use NDKPrivateKeySigner.generate() instead)
    static func generatePrivateKey() throws -> PrivateKey {
        return try randomBytes(count: Constants.privateKeySize).hexString
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
    public static func verify(signature: Signature, message: Data, pubkey: PublicKey) throws -> Bool {
        let sigData: Data
        do {
            sigData = try HexValidator.validate64ByteHex(signature)
        } catch {
            throw CryptoError.invalidSignatureLength
        }

        let pubkeyData: Data
        do {
            pubkeyData = try HexValidator.validate32ByteHex(pubkey)
        } catch {
            throw CryptoError.invalidKeyLength
        }

        let xonlyKey = secp256k1.Schnorr.XonlyKey(dataRepresentation: pubkeyData)
        let schnorrSig = try secp256k1.Schnorr.SchnorrSignature(dataRepresentation: sigData)

        var messageBytes = Array(message)
        return xonlyKey.isValid(schnorrSig, for: &messageBytes)
    }

    /// SHA256 hash
    public static func sha256(_ data: Data) -> Data {
        return data.sha256()
    }

    /// Generate random bytes
    public static func randomBytes(count: Int) throws -> Data {
        guard count >= 0 else {
            throw CryptoError.randomGenerationFailed("negative byte count")
        }
        guard count > 0 else {
            return Data()
        }

        var bytes = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
            let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
                guard let baseAddress = buffer.baseAddress else {
                    return errSecParam
                }
                return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
            }
            guard status == errSecSuccess else {
                throw CryptoError.randomGenerationFailed("SecRandomCopyBytes failed with status \(status)")
            }
        #elseif os(Linux)
            var offset = 0
            while offset < count {
                let readCount = bytes.withUnsafeMutableBytes { buffer -> Int in
                    guard let baseAddress = buffer.baseAddress else {
                        return -1
                    }
                    return Glibc.getrandom(baseAddress.advanced(by: offset), count - offset, 0)
                }

                if readCount < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw CryptoError.randomGenerationFailed("getrandom failed with errno \(errno)")
                }
                guard readCount > 0 else {
                    throw CryptoError.randomGenerationFailed("getrandom returned no bytes")
                }

                offset += readCount
            }
        #else
            throw CryptoError.randomGenerationFailed("no secure random byte generator is available")
        #endif
        return Data(bytes)
    }

    // MARK: - NIP-44 Encryption

    /// Encrypt a message using NIP-44
    static func nip44Encrypt(message: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        return try NIP44.encrypt(message: message, privateKey: privateKey, pubkey: pubkey)
    }

    /// Decrypt a message using NIP-44
    static func nip44Decrypt(encrypted: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        return try NIP44.decrypt(encrypted: encrypted, privateKey: privateKey, pubkey: pubkey)
    }

    typealias NIP44Error = NIP44.NIP44Error
}
