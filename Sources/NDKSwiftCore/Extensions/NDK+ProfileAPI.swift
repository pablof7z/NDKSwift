import Foundation

// MARK: - Profile API Extensions

extension NDK {
    /// Get observable profile for a pubkey
    /// Returns the same NDKProfile instance for the same pubkey (deduplication)
    /// Profile automatically subscribes to updates and caches data
    @MainActor
    public func profile(for pubkey: PublicKey) -> NDKProfile {
        getOrCreateProfile(pubkey)
    }
}
