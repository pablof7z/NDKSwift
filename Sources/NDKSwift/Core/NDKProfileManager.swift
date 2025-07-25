import Foundation

/// Configuration for profile management
public struct NDKProfileConfig {
    /// Maximum number of profiles to keep in memory cache
    public var cacheSize: Int

    /// Time interval before cached profiles are considered stale (in seconds)
    public var staleAfter: TimeInterval

    public init(
        cacheSize: Int = NetworkConstants.profileCacheSize,
        staleAfter: TimeInterval = TimeConstants.hour
    ) {
        self.cacheSize = cacheSize
        self.staleAfter = staleAfter
    }

    public static let `default` = NDKProfileConfig()
}

/// Entry in the profile cache
private struct ProfileCacheEntry {
    let profile: NDKUserProfile
    let fetchedAt: Date

    func isStale(after interval: TimeInterval) -> Bool {
        return Date().timeIntervalSince(fetchedAt) > interval
    }
}

/// Manager for efficient profile fetching with caching
///
/// The ProfileManager provides intelligent caching for user profiles with configurable freshness.
/// Use maxAge parameter to control cache behavior:
/// - maxAge: nil - Use default staleAfter from config (typically 1 hour)
/// - maxAge: 0 - Always fetch fresh data, bypass cache
/// - maxAge: 5 * TimeConstants.minute - Use cached data if less than 5 minutes old
///
/// Example usage:
/// ```swift
/// // Feed view - many profiles, older data acceptable
/// for await profile in profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
///     // Use profile (may be nil if not found)
///     break // If you only need one value
/// }
///
/// // Profile page - want fresh data and continuous updates
/// for await profile in profileManager.observe(for: pubkey, maxAge: 0) {
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
    ///   - maxAge: Maximum age of cached data in seconds (0 = always get fresh updates, nil = use default)
    public func observe(for pubkey: PublicKey, maxAge: TimeInterval? = nil) -> AsyncStream<NDKUserProfile?> {
        AsyncStream { continuation in
            Task {
                // Add continuation to active observations
                let wrapper = ContinuationWrapper(continuation)
                if activeObservations[pubkey] == nil {
                    activeObservations[pubkey] = []
                }
                activeObservations[pubkey]?.append(wrapper)

                let effectiveMaxAge = maxAge ?? config.staleAfter

                // Yield cached profile immediately if available and fresh enough
                if effectiveMaxAge > 0, let cached = checkCache(for: pubkey, maxAge: effectiveMaxAge) {
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
                // Always use maxAge: 0 for the data source to ensure live updates
                // The initial cache check already respects the maxAge parameter
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

    private func checkCache(for pubkey: PublicKey, maxAge: TimeInterval) -> NDKUserProfile? {
        guard let entry = profileCache[pubkey] else { return nil }

        // Check if stale based on maxAge
        if entry.isStale(after: maxAge) {
            // Remove stale entry
            profileCache.removeValue(forKey: pubkey)
            cacheOrder.removeAll(value: pubkey)
            return nil
        }

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
        profileCache[pubkey] = ProfileCacheEntry(profile: profile, fetchedAt: Date())
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