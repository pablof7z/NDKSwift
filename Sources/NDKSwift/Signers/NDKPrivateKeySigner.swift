import Foundation

/// A signer that uses a private key directly
public final class NDKPrivateKeySigner: NDKSigner {
    private let privateKey: PrivateKey
    private let _pubkey: PublicKey
    private var isReady = true

    /// Initialize with a private key
    public init(privateKey: PrivateKey) throws {
        do {
            _ = try HexValidator.validate32ByteHex(privateKey)
        } catch {
            throw NDKError.invalidPrivateKey(privateKey)
        }

        self.privateKey = privateKey
        do {
            self._pubkey = try Crypto.getPublicKey(from: privateKey)
        } catch let error as Crypto.CryptoError {
            throw NDKError.keyDerivationFailed(error.errorDescription ?? "Failed to derive public key", underlying: error)
        } catch {
            throw NDKError.keyDerivationFailed("Failed to derive public key", underlying: error)
        }
    }

    /// Initialize with an nsec string
    public convenience init(nsec: String) throws {
        let privateKey = try Bech32.privateKey(from: nsec)
        try self.init(privateKey: privateKey)
    }

    /// Generate a new signer with a random private key
    public static func generate() throws -> NDKPrivateKeySigner {
        let privateKey = Crypto.generatePrivateKey()
        return try NDKPrivateKeySigner(privateKey: privateKey)
    }

    // MARK: - NDKSigner Protocol

    public var pubkey: PublicKey {
        get async throws {
            return _pubkey
        }
    }

    public func sign(_ event: NDKEvent) async throws -> Signature {
        let idData: Data
        do {
            idData = try HexValidator.validate32ByteHex(event.id)
        } catch {
            throw NDKError.signingFailed("Failed to sign event: invalid event ID")
        }

        do {
            return try Crypto.sign(message: idData, privateKey: privateKey)
        } catch let error as Crypto.CryptoError {
            throw NDKError.signingFailed(error.errorDescription ?? "Failed to sign event", underlying: error)
        } catch {
            throw NDKError.signingFailed("Failed to sign event", underlying: error)
        }
    }
    
    public func sign(event: inout NDKEvent) async throws {
        // This method is deprecated and should not be used with immutable events
        throw NDKError.notImplemented("Mutating sign method is deprecated. Use NDKEventBuilder instead.")
    }

    public func blockUntilReady() async throws {
        // Private key signer is always ready
    }

    public func encryptionEnabled() async -> [NDKEncryptionScheme] {
        return [.nip04, .nip44]
    }

    public func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        switch scheme {
        case .nip04:
            do {
                return try Crypto.nip04Encrypt(message: value, privateKey: privateKey, publicKey: recipient.pubkey)
            } catch let error as Crypto.CryptoError {
                throw NDKError.encryptionFailed("NIP-04 encryption failed: \(error.errorDescription ?? "")", underlying: error)
            } catch {
                throw NDKError.encryptionFailed("NIP-04 encryption failed", underlying: error)
            }
        case .nip44:
            do {
                return try Crypto.nip44Encrypt(message: value, privateKey: privateKey, publicKey: recipient.pubkey)
            } catch let error as Crypto.NIP44Error {
                throw NDKError.encryptionFailed("NIP-44 encryption failed: \(error.errorDescription ?? "")", underlying: error)
            } catch let error as Crypto.CryptoError {
                throw NDKError.encryptionFailed("NIP-44 encryption failed: \(error.errorDescription ?? "")", underlying: error)
            } catch {
                throw NDKError.encryptionFailed("NIP-44 encryption failed", underlying: error)
            }
        }
    }

    public func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        switch scheme {
        case .nip04:
            do {
                return try Crypto.nip04Decrypt(encrypted: value, privateKey: privateKey, publicKey: sender.pubkey)
            } catch let error as Crypto.CryptoError {
                throw NDKError.decryptionFailed("NIP-04 decryption failed: \(error.errorDescription ?? "")", underlying: error)
            } catch {
                throw NDKError.decryptionFailed("NIP-04 decryption failed", underlying: error)
            }
        case .nip44:
            do {
                return try Crypto.nip44Decrypt(encrypted: value, privateKey: privateKey, publicKey: sender.pubkey)
            } catch let error as Crypto.NIP44Error {
                throw NDKError.decryptionFailed("NIP-44 decryption failed: \(error.errorDescription ?? "")", underlying: error)
            } catch let error as Crypto.CryptoError {
                throw NDKError.decryptionFailed("NIP-44 decryption failed: \(error.errorDescription ?? "")", underlying: error)
            } catch {
                throw NDKError.decryptionFailed("NIP-44 decryption failed", underlying: error)
            }
        }
    }

    // MARK: - Utilities

    /// Get the private key in nsec format
    public var nsec: String {
        get throws {
            return try Bech32.nsec(from: privateKey)
        }
    }

    /// Get the public key in npub format
    public var npub: String {
        get throws {
            return try Bech32.npub(from: _pubkey)
        }
    }

    /// Get the private key (for testing purposes)
    public var privateKeyValue: PrivateKey {
        return privateKey
    }

    /// Serialize the signer to a payload string (deprecated)
    public func toPayload() -> String {
        let payload: [String: Any] = [
            "type": "privatekey",
            "privateKey": privateKey
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }
    
    // MARK: - Serialization (NDKSigner Protocol)
    
    public static var signerType: String {
        return "privatekey"
    }
    
    public func serialize() async throws -> Data {
        let payload: [String: Any] = [
            "privateKey": privateKey
        ]
        return try NDKSignerSerialization.createContainer(type: Self.signerType, payload: payload)
    }
    
    public static func deserialize(_ data: Data, ndk: NDK?) throws -> NDKPrivateKeySigner {
        // The registry already extracted the payload, so we just need to decode it directly
        let payload = try JSONCoding.decode([String: String].self, from: data)
        
        guard let privateKey = payload["privateKey"] else {
            throw NDKSignerRegistryError.deserializationError("Missing or invalid privateKey")
        }
        
        return try NDKPrivateKeySigner(privateKey: privateKey)
    }
}
