/// Helper methods for common NDK operations
public extension NDK {
    /// Ensures a signer is configured and returns it
    /// - Returns: The configured signer
    /// - Throws: NDKError.notConfigured if no signer is available
    func requireSigner() throws -> NDKSigner {
        guard let signer = signer else {
            throw NDKError.notConfigured(ErrorMessageConstants.Messages.noSignerConfigured)
        }
        return signer
    }
}

/// Helper methods for objects that have a weak reference to NDK
public protocol NDKDependent {
    var ndk: NDK? { get }
}

public extension NDKDependent {
    /// Ensures NDK is configured and returns it
    /// - Returns: The configured NDK instance
    /// - Throws: NDKError.notConfigured if NDK is not available
    func requireNDK() throws -> NDK {
        guard let ndk = ndk else {
            throw NDKError.notConfigured(ErrorMessageConstants.Messages.noNDKConfigured)
        }
        return ndk
    }
}
