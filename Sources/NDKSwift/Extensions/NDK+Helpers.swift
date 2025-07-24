/// Helper methods for common NDK operations
public extension NDK {
    /// Ensures a signer is configured and returns it
    /// - Returns: The configured signer
    /// - Throws: NDKError.notConfigured if no signer is available
    func requireSigner() throws -> NDKSigner {
        guard let signer = signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        return signer
    }
}

