import Foundation

/// A signer that uses a private key directly
public final class NDKPrivateKeySigner: NDKSigner {
    private let privateKey: PrivateKey
    private let _pubkey: PublicKey
    private var isReady = true
    
    /// Initialize with a private key
    public init(privateKey: PrivateKey) throws {
        guard let keyData = Data(hexString: privateKey), keyData.count == 32 else {
            throw NDKError.invalidPrivateKey
        }
        
        self.privateKey = privateKey
        self._pubkey = try Crypto.getPublicKey(from: privateKey)
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
        // Ensure event has an ID
        if event.id == nil {
            try event.generateID()
        }
        
        guard let eventId = event.id,
              let idData = Data(hexString: eventId) else {
            throw NDKError.signingFailed
        }
        
        return try Crypto.sign(message: idData, privateKey: privateKey)
    }
    
    public func blockUntilReady() async throws {
        // Private key signer is always ready
        return
    }
    
    public func encryptionEnabled() async -> [NDKEncryptionScheme] {
        return [.nip04]
    }
    
    public func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        switch scheme {
        case .nip04:
            return try Crypto.nip04Encrypt(message: value, privateKey: privateKey, publicKey: recipient.pubkey)
        case .nip44:
            throw NDKError.notImplemented
        }
    }
    
    public func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        switch scheme {
        case .nip04:
            return try Crypto.nip04Decrypt(encrypted: value, privateKey: privateKey, publicKey: sender.pubkey)
        case .nip44:
            throw NDKError.notImplemented
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
}