import Foundation

/// Configuration for profile management
public struct NDKProfileConfig {
    /// Maximum number of profiles to keep in memory cache
    public var cacheSize: Int

    public init(
        cacheSize: Int = NetworkConstants.profileCacheSize
    ) {
        self.cacheSize = cacheSize
    }

    public static let `default` = NDKProfileConfig()
}

/// Entry in the profile cache
private struct ProfileCacheEntry {
    let profile: NDKUserProfile
}

/// Manager for efficient profile fetching with caching
///
/// The ProfileManager provides an in-memory LRU cache for user profiles that is always
/// synchronized with the database. When profile updates arrive from relays, both the
/// memory cache and database are updated together.
///
/// Use the forceNetworkFetch parameter to control network behavior:
/// - forceNetworkFetch: false (default) - Return cached data immediately if available
/// - forceNetworkFetch: true - Always check relays for updates (useful for profile pages)
///
/// Example usage:
/// ```swift
/// // Feed view - many profiles, use cache
/// for await profile in profileManager.observe(for: pubkey) {
///     // Use profile (may be nil if not found)
///     break // If you only need one value
/// }
///
/// // Profile page - want to check for updates
/// for await profile in profileManager.observe(for: pubkey, forceNetworkFetch: true) {
///     // Handle profile updates
/// }
/// ```
public actor NDKProfileManager {
    private weak var ndk: NDK?
    private let config: NDKProfileConfig

    /// In-memory LRU cache for profiles
    private var profileCache: [PublicKey: ProfileCacheEntry] = [:]
    private var cacheOrder: [PublicKey] = [] // For LRU tracking

    /// Active profile observations
    private class ContinuationWrapper {
        let continuation: AsyncStream<NDKUserProfile?>.Continuation
        init(_ continuation: AsyncStream<NDKUserProfile?>.Continuation) {
            self.continuation = continuation
        }
    }

    private var activeObservations: [PublicKey: [ContinuationWrapper]] = [:]

    public init(ndk: NDK, config: NDKProfileConfig = .default) {
        self.ndk = ndk
        self.config = config
    }


    /// Observe profile updates for a given pubkey
    /// Returns an AsyncSequence that yields the profile immediately if cached,
    /// then yields updates as they arrive from relays
    ///
    /// - Parameters:
    ///   - pubkey: The public key to observe
    ///   - forceNetworkFetch: If true, always check relays for updates even if cached
    public func observe(for pubkey: PublicKey, forceNetworkFetch: Bool = false) -> AsyncStream<NDKUserProfile?> {
        AsyncStream { continuation in
            Task {
                // Add continuation to active observations
                let wrapper = ContinuationWrapper(continuation)
                if activeObservations[pubkey] == nil {
                    activeObservations[pubkey] = []
                }
                activeObservations[pubkey]?.append(wrapper)

                // Yield cached profile immediately if available and not forcing network fetch
                if !forceNetworkFetch, let cached = getCachedProfile(for: pubkey) {
                    continuation.yield(cached)
                }

                // Set up subscription for profile updates
                guard let ndk = ndk else {
                    continuation.finish()
                    return
                }

                let filter = NDKFilter(
                    authors: [pubkey],
                    kinds: [EventKind.metadata],
                    limit: 1
                )

                // Use NDKDataSource for profile updates
                // When forceNetworkFetch is true, we want to check relays immediately
                let dataSource = ndk.observe(filter: filter, maxAge: 0)

                // Process events from data source
                for await event in dataSource.events {
                    if let profileData = event.content.data(using: .utf8),
                       let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
                        // Update cache
                        updateCache(pubkey: pubkey, profile: profile)

                        // Notify all observers for this pubkey
                        activeObservations[pubkey]?.forEach { wrapper in
                            wrapper.continuation.yield(profile)
                        }

                        // Save to persistent cache
                        try? await ndk.cache.saveProfile(profile, pubkey: pubkey)
                    }
                }

                // Clean up when done
                activeObservations[pubkey]?.removeAll { $0 === wrapper }
                if activeObservations[pubkey]?.isEmpty ?? false {
                    activeObservations.removeValue(forKey: pubkey)
                }
                continuation.finish()
            }
        }
    }

    /// Clear the profile cache
    public func clearCache() {
        profileCache.removeAll()
        cacheOrder.removeAll()
    }

    /// Get cache statistics
    public func getCacheStats() -> (size: Int, hitRate: Double) {
        // This would need hit/miss tracking for accurate hit rate
        return (size: profileCache.count, hitRate: 0.0)
    }

    // MARK: - Private Methods

    private func getCachedProfile(for pubkey: PublicKey) -> NDKUserProfile? {
        guard let entry = profileCache[pubkey] else { return nil }

        // Update LRU order
        updateCacheOrder(for: pubkey)

        return entry.profile
    }

    private func updateCache(pubkey: PublicKey, profile: NDKUserProfile) {
        // Remove old entry if exists
        if profileCache[pubkey] != nil {
            cacheOrder.removeAll(value: pubkey)
        }

        // Add new entry
        profileCache[pubkey] = ProfileCacheEntry(profile: profile)
        cacheOrder.append(pubkey)

        // Enforce cache size limit
        while cacheOrder.count > config.cacheSize {
            if let oldestKey = cacheOrder.first {
                profileCache.removeValue(forKey: oldestKey)
                cacheOrder.removeFirst()
            }
        }
    }

    private func updateCacheOrder(for pubkey: PublicKey) {
        // Move to end (most recently used)
        cacheOrder.removeAll(value: pubkey)
        cacheOrder.append(pubkey)
    }

}