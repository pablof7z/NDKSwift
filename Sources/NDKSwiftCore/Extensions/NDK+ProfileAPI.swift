import Foundation

// MARK: - Profile API Extensions

extension NDK {
    /// Get observable profile for a pubkey
    /// Returns the same NDKProfile instance for the same pubkey (deduplication)
    /// Profile automatically subscribes to updates and caches data
    @MainActor
    public func profile(for pubkey: PublicKey) -> NDKProfile {
        profileCache.get(pubkey)!
    }

    /// Get profile updates as AsyncStream
    /// Use this for non-SwiftUI code that needs profile updates
    /// For SwiftUI, prefer using `ndk.profile(for:)` which returns @Observable NDKProfile
    public func profileUpdates(for pubkey: PublicKey) -> AsyncStream<NDKUserMetadata?> {
        profileManager.subscribe(for: pubkey, maxAge: 0)
    }
}

extension NDKUser {
    /// Get observable profile for this user
    /// Convenience property that delegates to ndk.profile(for:)
    @MainActor
    public var profile: NDKProfile {
        ndk.profile(for: pubkey)
    }
}
