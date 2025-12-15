import Foundation

/// Common encryption protocols and types for NDKSwift
///
/// This module provides unified interfaces for encryption functionality
/// in Nostr applications, supporting both NIP-04 and NIP-44
/// encryption standards.

/// Protocol for Nostr encryption implementations
public protocol NDKEncryption: Sendable {
    /// Encrypt a message
    /// - Parameters:
    ///   - message: The plaintext message to encrypt
    ///   - privateKey: Sender's private key (hex)
    ///   - pubkey: Recipient's public key (hex)
    /// - Returns: Encrypted message string
    func encrypt(message: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String

    /// Decrypt a message
    /// - Parameters:
    ///   - encrypted: The encrypted message
    ///   - privateKey: Recipient's private key (hex)
    ///   - pubkey: Sender's public key (hex)
    /// - Returns: Decrypted plaintext message
    func decrypt(encrypted: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String
}

/// Encryption errors
public enum NDKEncryptionError: LocalizedError, Sendable {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case unsupportedVersion
    case invalidFormat

    public var errorDescription: String? {
        switch self {
        case let .encryptionFailed(message):
            return "Encryption failed: \(message)"
        case let .decryptionFailed(message):
            return "Decryption failed: \(message)"
        case .unsupportedVersion:
            return "Unsupported encryption version"
        case .invalidFormat:
            return "Invalid encrypted message format"
        }
    }
}

/// NIP-04 encryption implementation
public struct NIP04Encryption: NDKEncryption {
    public init() {}

    public func encrypt(message: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        return try Crypto.nip04Encrypt(message: message, privateKey: privateKey, pubkey: pubkey)
    }

    public func decrypt(encrypted: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        return try Crypto.nip04Decrypt(encrypted: encrypted, privateKey: privateKey, pubkey: pubkey)
    }
}

/// NIP-44 encryption implementation (recommended)
public struct NIP44Encryption: NDKEncryption {
    public init() {}

    public func encrypt(message: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        return try Crypto.nip44Encrypt(message: message, privateKey: privateKey, pubkey: pubkey)
    }

    public func decrypt(encrypted: String, privateKey: PrivateKey, pubkey: PublicKey) throws -> String {
        return try Crypto.nip44Decrypt(encrypted: encrypted, privateKey: privateKey, pubkey: pubkey)
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
        ndk: NDK,
        useNIP44: Bool = true
    ) async throws -> NDKEvent {
        let scheme: NDKEncryptionScheme = useNIP44 ? .nip44 : .nip04

        let encryptedContent = try await signer.encrypt(recipientPubkey: recipientPubkey, value: content, scheme: scheme)

        let event = try await NDKEventBuilder(ndk: ndk)
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
        guard kind == EventKind.encryptedDirectMessage else {
            throw NDKEncryptionError.invalidFormat
        }

        // Get viewer pubkey for cache
        let viewerPubkey = try await signer.pubkey

        // Check cache first (if available)
        if let cache = ndk?.cache,
           let cached = await cache.getDecryptedContent(for: id, viewerPubkey: viewerPubkey)
        {
            return cached
        }

        let senderKey = senderPubkey ?? self.pubkey

        // Try to detect the encryption scheme based on content format
        let scheme: NDKEncryptionScheme
        if content.contains("?iv=") {
            scheme = .nip04
        } else {
            scheme = .nip44
        }

        let decrypted = try await signer.decrypt(senderPubkey: senderKey, value: content, scheme: scheme)

        // Store in cache (if available)
        if let cache = ndk?.cache {
            await cache.storeDecryptedContent(decrypted, for: id, viewerPubkey: viewerPubkey)
        }

        return decrypted
    }
}
