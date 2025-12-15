import Foundation

// MARK: - NDK User Helper Extensions

public extension NDK {
    /// Get the current active user from the signer
    /// Returns nil if no signer is configured
    var currentUser: NDKUser? {
        get async {
            guard let signer else { return nil }
            do {
                let pubkey = try await signer.pubkey
                return getUser(pubkey)
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
        let pubkey = try await signer.pubkey
        guard let user = getUser(pubkey) else {
            throw NDKError.invalidDataFormat("pubkey", details: "Invalid pubkey from signer")
        }
        return user
    }
}
