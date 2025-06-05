import Foundation

/// Protocol for signing Nostr events
public protocol NDKSigner {
    /// The public key associated with this signer
    var pubkey: PublicKey { get async throws }

    /// Sign an event
    func sign(_ event: NDKEvent) async throws -> Signature

    /// Sign an event in place (mutating)
    func sign(event: inout NDKEvent) async throws

    /// Block until the signer is ready (e.g., user has unlocked it)
    func blockUntilReady() async throws

    /// Get the user associated with this signer
    func user() async throws -> NDKUser

    /// Get relays recommended by this signer (optional)
    func relays(ndk: NDK?) async -> [NDKRelay]

    /// Check which encryption schemes are supported
    func encryptionEnabled() async -> [NDKEncryptionScheme]

    /// Encrypt a message
    func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String

    /// Decrypt a message
    func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String
}

/// Default implementations
public extension NDKSigner {
    func relays(ndk _: NDK?) async -> [NDKRelay] {
        return []
    }

    func encryptionEnabled() async -> [NDKEncryptionScheme] {
        return []
    }

    func user() async throws -> NDKUser {
        let pubkey = try await self.pubkey
        return NDKUser(pubkey: pubkey)
    }

    func sign(event: inout NDKEvent) async throws {
        let signature = try await sign(event)
        event.sig = signature
    }

    func blockUntilReady() async throws {
        // Default implementation does nothing
    }
}

/// Encryption schemes supported by signers
public enum NDKEncryptionScheme: String, CaseIterable {
    case nip04
    case nip44
}
