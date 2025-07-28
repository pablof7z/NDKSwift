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
/// Use the maxAge parameter to control network behavior (consistent with ndk.observe):
/// - maxAge: 0 - Always check relays for real-time updates
/// - maxAge: >0 - Return cached data immediately if available
///
/// Example usage:
/// ```swift
/// // Feed view - many profiles, use cache
/// for await profile in profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
///     // Use profile (may be nil if not found)
///     break // If you only need one value
/// }
///
/// // Profile page - want real-time updates
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

    /// Initialize a new profile manager
    /// - Parameters:
    ///   - ndk: The NDK instance to use for fetching profiles
    ///   - config: Configuration for cache behavior
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
    ///   - maxAge: Maximum age of cached data in seconds (0 = always get real-time updates)
    public func observe(for pubkey: PublicKey, maxAge: TimeInterval = TimeConstants.hour) -> AsyncStream<NDKUserProfile?> {
        AsyncStream { continuation in
            Task {
                // Add continuation to active observations
                let wrapper = ContinuationWrapper(continuation)
                if activeObservations[pubkey] == nil {
                    activeObservations[pubkey] = []
                }
                activeObservations[pubkey]?.append(wrapper)

                // Yield cached profile immediately if available and maxAge allows it
                if maxAge > 0, let cached = getCachedProfile(for: pubkey) {
                    continuation.yield(cached)
                }

                // Set up subscription for profile updates
                guard let ndk = ndk else {
                    continuation.finish()
                    return
                }

                let filter = NDKFilter(
                    authors: [pubkey],
                    kinds: [EventKind.metadata]
                )

                // Use NDKDataSource for profile updates
                // Pass maxAge through to control subscription behavior
                let dataSource = ndk.observe(filter: filter, maxAge: maxAge)

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

    /// Load a profile from cache without subscribing to updates
    /// - Parameter pubkey: The public key to load
    /// - Returns: The cached profile if available, nil otherwise
    public func loadProfile(for pubkey: PublicKey) async -> NDKUserProfile? {
        return getCachedProfile(for: pubkey)
    }
    
    /// Load multiple profiles from cache
    /// - Parameter pubkeys: Array of public keys to load
    /// - Returns: Dictionary mapping pubkeys to their profiles (if found)
    public func loadProfiles(for pubkeys: [PublicKey]) async -> [PublicKey: NDKUserProfile] {
        var profiles: [PublicKey: NDKUserProfile] = [:]
        for pubkey in pubkeys {
            if let profile = getCachedProfile(for: pubkey) {
                profiles[pubkey] = profile
            }
        }
        return profiles
    }
    
    /// Save a profile to cache
    /// - Parameters:
    ///   - profile: The profile to save
    ///   - pubkey: The public key associated with the profile
    ///   - expiresIn: Optional expiry time in seconds (not implemented)
    public func saveProfile(_ profile: NDKUserProfile, for pubkey: PublicKey, expiresIn: TimeInterval? = nil) async {
        updateCache(pubkey: pubkey, profile: profile)
        
        // Also save to persistent cache if available
        if let ndk = ndk {
            try? await ndk.cache.saveProfile(profile, pubkey: pubkey)
        }
    }
    
    /// Process a profile event from a relay
    /// - Parameter event: The kind 0 event containing profile metadata
    public func processProfileEvent(_ event: NDKEvent) async {
        guard event.kind == EventKind.metadata else { return }
        
        if let profileData = event.content.data(using: .utf8),
           let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
            await saveProfile(profile, for: event.pubkey)
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