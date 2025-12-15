import Foundation

/// Cache for observable profile instances
@MainActor
public final class NDKProfileCache {
    private var cache: [PublicKey: NDKProfile] = [:]
    private weak var ndk: NDK?

    init(ndk: NDK) {
        self.ndk = ndk
    }

    /// Get or create an observable profile for a pubkey
    public func get(_ pubkey: PublicKey) -> NDKProfile {
        if let existing = cache[pubkey] {
            return existing
        }

        guard let ndk else {
            fatalError("NDKProfileCache: NDK reference lost")
        }

        let profile = NDKProfile(pubkey: pubkey, ndk: ndk)
        cache[pubkey] = profile
        return profile
    }

    /// Clear a specific profile from cache
    public func clear(_ pubkey: PublicKey) {
        cache.removeValue(forKey: pubkey)
    }

    /// Clear all cached profiles
    public func clearAll() {
        cache.removeAll()
    }

    /// Number of cached profiles
    public var count: Int {
        cache.count
    }
}
