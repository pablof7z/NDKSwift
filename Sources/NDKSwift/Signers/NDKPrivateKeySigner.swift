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
            throw NDKError.cryptoOperation("Key derivation", nip: nil, error: error)
        } catch {
            throw NDKError.cryptoOperation("Key derivation", nip: nil, error: error)
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
            throw NDKError.parseError(for: "event ID", details: error.localizedDescription)
        }

        do {
            return try Crypto.sign(message: idData, privateKey: privateKey)
        } catch let error as Crypto.CryptoError {
            throw NDKError.cryptoOperation("Signing", nip: nil, error: error)
        } catch {
            throw NDKError.cryptoOperation("Signing", nip: nil, error: error)
        }
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
            } catch {
                throw NDKError.cryptoOperation("Encryption", nip: "NIP-04", error: error)
            }
        case .nip44:
            do {
                return try Crypto.nip44Encrypt(message: value, privateKey: privateKey, publicKey: recipient.pubkey)
            } catch {
                throw NDKError.cryptoOperation("Encryption", nip: "NIP-44", error: error)
            }
        }
    }

    public func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        switch scheme {
        case .nip04:
            do {
                return try Crypto.nip04Decrypt(encrypted: value, privateKey: privateKey, publicKey: sender.pubkey)
            } catch {
                throw NDKError.cryptoOperation("Decryption", nip: "NIP-04", error: error)
            }
        case .nip44:
            do {
                return try Crypto.nip44Decrypt(encrypted: value, privateKey: privateKey, publicKey: sender.pubkey)
            } catch {
                throw NDKError.cryptoOperation("Decryption", nip: "NIP-44", error: error)
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
