import Foundation

/// LRU cache for observable profile instances with bounded size
@MainActor
public final class NDKProfileCache {
    /// Maximum number of profiles to cache
    private let maxSize: Int

    /// Cache storage with access tracking for LRU eviction
    private var cache: [PublicKey: CacheEntry] = [:]

    /// Access order for LRU eviction (most recently accessed at end)
    private var accessOrder: [PublicKey] = []

    private weak var ndk: NDK?

    private struct CacheEntry {
        let profile: NDKProfile
        var lastAccess: Date
    }

    init(ndk: NDK, maxSize: Int = 500) {
        self.ndk = ndk
        self.maxSize = maxSize
    }

    /// Get or create an observable profile for a pubkey
    /// Returns nil if NDK reference is lost (should not happen in normal usage)
    public func get(_ pubkey: PublicKey) -> NDKProfile? {
        // Return existing profile and update access
        if var entry = cache[pubkey] {
            entry.lastAccess = Date()
            cache[pubkey] = entry
            updateAccessOrder(pubkey)
            return entry.profile
        }

        guard let ndk else {
            NDKLogger.log(.error, category: .general, "NDKProfileCache: NDK reference lost, cannot create profile")
            return nil
        }

        // Evict if at capacity
        if cache.count >= maxSize {
            evictLeastRecentlyUsed()
        }

        let profile = NDKProfile(pubkey: pubkey, ndk: ndk)
        cache[pubkey] = CacheEntry(profile: profile, lastAccess: Date())
        accessOrder.append(pubkey)
        return profile
    }

    /// Clear a specific profile from cache
    public func clear(_ pubkey: PublicKey) {
        cache.removeValue(forKey: pubkey)
        accessOrder.removeAll { $0 == pubkey }
    }

    /// Clear all cached profiles
    public func clearAll() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    /// Number of cached profiles
    public var count: Int {
        cache.count
    }

    // MARK: - Private

    private func updateAccessOrder(_ pubkey: PublicKey) {
        accessOrder.removeAll { $0 == pubkey }
        accessOrder.append(pubkey)
    }

    private func evictLeastRecentlyUsed() {
        guard let lruKey = accessOrder.first else { return }
        cache.removeValue(forKey: lruKey)
        accessOrder.removeFirst()
    }
}
