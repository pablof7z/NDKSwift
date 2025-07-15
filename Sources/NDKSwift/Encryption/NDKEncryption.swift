import Foundation

/// Common encryption protocols and types for NDKSwift
/// 
/// This module provides unified interfaces for encryption functionality
/// in Nostr applications, supporting both NIP-04 (deprecated) and NIP-44
/// encryption standards.

/// Protocol for Nostr encryption implementations
public protocol NDKEncryption {
    /// Encrypt a message
    /// - Parameters:
    ///   - message: The plaintext message to encrypt
    ///   - privateKey: Sender's private key (hex)
    ///   - publicKey: Recipient's public key (hex)
    /// - Returns: Encrypted message string
    func encrypt(message: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String
    
    /// Decrypt a message
    /// - Parameters:
    ///   - encrypted: The encrypted message
    ///   - privateKey: Recipient's private key (hex)
    ///   - publicKey: Sender's public key (hex)
    /// - Returns: Decrypted plaintext message
    func decrypt(encrypted: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String
}

/// Encryption errors
public enum NDKEncryptionError: Error, LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case unsupportedVersion
    case invalidFormat
    
    public var errorDescription: String? {
        switch self {
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .unsupportedVersion:
            return "Unsupported encryption version"
        case .invalidFormat:
            return "Invalid encrypted message format"
        }
    }
}

/// NIP-04 encryption implementation (deprecated)
public struct NIP04Encryption: NDKEncryption {
    public init() {}
    
    public func encrypt(message: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        return try Crypto.nip04Encrypt(message: message, privateKey: privateKey, publicKey: publicKey)
    }
    
    public func decrypt(encrypted: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        return try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: privateKey, publicKey: publicKey)
    }
}

/// NIP-44 encryption implementation (recommended)
public struct NIP44Encryption: NDKEncryption {
    public init() {}
    
    public func encrypt(message: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        return try Crypto.nip44Encrypt(message: message, privateKey: privateKey, publicKey: publicKey)
    }
    
    public func decrypt(encrypted: String, privateKey: PrivateKey, publicKey: PublicKey) throws -> String {
        return try Crypto.nip44Decrypt(encrypted: encrypted, privateKey: privateKey, publicKey: publicKey)
    }
}

/// Default encryption instance (uses NIP-44)
public let defaultEncryption: NDKEncryption = NIP44Encryption()

// MARK: - NDKEvent Extensions

public extension NDKEvent {
    /// Create an encrypted direct message event (NIP-04 or NIP-44)
    /// - Parameters:
    ///   - content: The plaintext message content
    ///   - recipientPubkey: The recipient's public key
    ///   - signer: The signer to use for encryption and signing
    ///   - useNIP44: Whether to use NIP-44 (true) or NIP-04 (false). Defaults to true.
    /// - Returns: An encrypted direct message event
    static func encryptedDirectMessage(
        content: String,
        recipientPubkey: PublicKey,
        signer: NDKSigner,
        useNIP44: Bool = true
    ) async throws -> NDKEvent {
        let user = NDKUser(pubkey: recipientPubkey)
        let scheme: NDKEncryptionScheme = useNIP44 ? .nip44 : .nip04
        
        let encryptedContent = try await signer.encrypt(recipient: user, value: content, scheme: scheme)
        
        let event = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(4) // Encrypted Direct Message
            .tags([["p", recipientPubkey]])
            .build(signer: signer)
        
        return event
    }
    
    /// Decrypt the content of an encrypted direct message
    /// - Parameters:
    ///   - signer: The signer to use for decryption
    ///   - senderPubkey: The sender's public key (optional, will extract from event if not provided)
    ///   - ndk: The NDK instance (optional, used for caching)
    /// - Returns: The decrypted message content
    func decryptedContent(signer: NDKSigner, senderPubkey: PublicKey? = nil, ndk: NDK? = nil) async throws -> String {
        guard kind == 4 else {
            throw NDKEncryptionError.invalidFormat
        }
        
        // Get viewer pubkey for cache
        let viewerPubkey = try await signer.pubkey
        
        // Check cache first (if available)
        if let cache = ndk?.cache,
           let cached = await cache.getDecryptedContent(for: id, viewerPubkey: viewerPubkey) {
            return cached
        }
        
        let pubkey: PublicKey
        if let senderPubkey = senderPubkey {
            pubkey = senderPubkey
        } else {
            pubkey = self.pubkey
        }
        let sender = NDKUser(pubkey: pubkey)
        
        // Try to detect the encryption scheme based on content format
        let scheme: NDKEncryptionScheme
        if content.contains("?iv=") {
            scheme = .nip04
        } else {
            scheme = .nip44
        }
        
        let decrypted = try await signer.decrypt(sender: sender, value: content, scheme: scheme)
        
        // Store in cache (if available)
        if let cache = ndk?.cache {
            await cache.storeDecryptedContent(decrypted, for: id, viewerPubkey: viewerPubkey)
        }
        
        return decrypted
    }
}