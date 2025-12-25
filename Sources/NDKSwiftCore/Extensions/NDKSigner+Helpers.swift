import Foundation

// MARK: - NDK Pubkey Helper Extensions

public extension NDK {
    /// Require a signer and return the current pubkey
    /// Throws an error if no signer is configured
    func requireCurrentPubkey() async throws -> PublicKey {
        let signer = try requireSigner()
        return try await signer.pubkey
    }
}
