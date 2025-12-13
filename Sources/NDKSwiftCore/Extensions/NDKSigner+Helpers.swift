import Foundation

// MARK: - Signer Helper Extensions

public extension NDKSigner {
    /// Create an NDKUser for the current signer's public key
    /// This is a convenience method to reduce code duplication when creating users from signers
    func asUser() async throws -> NDKUser {
        let pubkey = try await self.pubkey
        return NDKUser(pubkey: pubkey)
    }
}

public extension NDK {
    /// Get the current active user from the signer
    /// Returns nil if no signer is configured
    var currentUser: NDKUser? {
        get async {
            guard let signer = signer else { return nil }
            do {
                return try await signer.asUser()
            } catch {
                NDKLogger.log(.warning, category: .signer, "Failed to get current user from signer: \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Require a signer and return the current user
    /// Throws an error if no signer is configured
    func requireCurrentUser() async throws -> NDKUser {
        let signer = try requireSigner()
        return try await signer.asUser()
    }
}
