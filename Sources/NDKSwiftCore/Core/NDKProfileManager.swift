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
    let metadata: NDKUserMetadata
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
/// for await profile in profileManager.subscribe(for: pubkey, maxAge: TimeConstants.hour) {
///     // Use profile (may be nil if not found)
///     break // If you only need one value
/// }
///
/// // Profile page - want real-time updates
/// for await profile in profileManager.subscribe(for: pubkey, maxAge: 0) {
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
        let continuation: AsyncStream<NDKUserMetadata?>.Continuation
        init(_ continuation: AsyncStream<NDKUserMetadata?>.Continuation) {
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
    public func subscribe(for pubkey: PublicKey, maxAge: TimeInterval = TimeConstants.hour) -> AsyncStream<NDKUserMetadata?> {
        AsyncStream { continuation in
            Task {
                // Add continuation to active observations
                let wrapper = ContinuationWrapper(continuation)
                if activeObservations[pubkey] == nil {
                    activeObservations[pubkey] = []
                }
                activeObservations[pubkey]?.append(wrapper)

                // Yield cached metadata immediately if available and maxAge allows it
                if maxAge > 0, let cached = await getCachedMetadata(for: pubkey) {
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

                // Use NDKSubscription for profile updates
                // Pass maxAge through to control subscription behavior
                let dataSource = ndk.subscribe(filter: filter, maxAge: maxAge)

                // Process events from data source
                for await batch in dataSource.events {
                    for event in batch {
                        let metadata = NDKUserMetadata(event: event, ndk: ndk)

                        // Update memory cache
                        updateCache(pubkey: pubkey, metadata: metadata)

                        // Save parsed metadata to SQLite cache
                        if let parsedData = metadata.metadata {
                            do {
                                try await ndk.cache.saveProfileMetadata(
                                    pubkey: pubkey,
                                    metadata: parsedData,
                                    updatedAt: event.createdAt,
                                    eventId: event.id
                                )
                            } catch {
                                NDKLogger.log(.warning, category: .cache, "Failed to save profile metadata for \(pubkey.prefix(8)): \(error.localizedDescription)")
                            }
                        }

                        // Notify all observers for this pubkey
                        activeObservations[pubkey]?.forEach { wrapper in
                            wrapper.continuation.yield(metadata)
                        }

                        // Save event to persistent cache
                        do {
                            try await ndk.cache.saveEvent(event)
                        } catch {
                            NDKLogger.log(.warning, category: .cache, "Failed to save profile event \(event.id.prefix(8)) to cache: \(error.localizedDescription)")
                        }
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

    /// Load metadata from cache without subscribing to updates
    /// - Parameter pubkey: The public key to load
    /// - Returns: The cached metadata if available, nil otherwise
    public func loadMetadata(for pubkey: PublicKey) async -> NDKUserMetadata? {
        return await getCachedMetadata(for: pubkey)
    }

    /// Load multiple metadata entries from cache
    /// - Parameter pubkeys: Array of public keys to load
    /// - Returns: Dictionary mapping pubkeys to their metadata (if found)
    public func loadMetadata(for pubkeys: [PublicKey]) async -> [PublicKey: NDKUserMetadata] {
        var metadata: [PublicKey: NDKUserMetadata] = [:]

        // First check memory cache
        var missingPubkeys: [PublicKey] = []
        for pubkey in pubkeys {
            if let entry = profileCache[pubkey] {
                updateCacheOrder(for: pubkey)
                metadata[pubkey] = entry.metadata
            } else {
                missingPubkeys.append(pubkey)
            }
        }

        // Then check SQLite cache for missing ones
        if !missingPubkeys.isEmpty, let ndk = ndk {
            let cachedProfiles = await ndk.cache.getMultipleProfileMetadata(pubkeys: missingPubkeys)

            for (pubkey, profileData) in cachedProfiles {
                let userMetadata = NDKUserMetadata(
                    pubkey: pubkey,
                    parsedMetadata: profileData.metadata,
                    updatedAt: profileData.updatedAt,
                    eventId: profileData.eventId,
                    ndk: ndk
                )

                // Update memory cache
                updateCache(pubkey: pubkey, metadata: userMetadata)

                metadata[pubkey] = userMetadata
            }
        }

        return metadata
    }

    /// Save metadata to cache
    /// - Parameters:
    ///   - metadata: The metadata to save
    ///   - pubkey: The public key associated with the metadata
    ///   - expiresIn: Optional expiry time in seconds (not implemented)
    public func saveMetadata(_ metadata: NDKUserMetadata, for pubkey: PublicKey, expiresIn _: TimeInterval? = nil) async {
        updateCache(pubkey: pubkey, metadata: metadata)

        // Save parsed metadata to SQLite cache
        if let ndk = ndk, let parsedData = metadata.metadata {
            do {
                try await ndk.cache.saveProfileMetadata(
                    pubkey: pubkey,
                    metadata: parsedData,
                    updatedAt: metadata.updatedAt,
                    eventId: metadata.eventId
                )
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to save profile metadata for \(pubkey.prefix(8)): \(error.localizedDescription)")
            }
        }
    }

    /// Process a metadata event from a relay
    /// - Parameter event: The kind 0 event containing user metadata
    public func processMetadataEvent(_ event: NDKEvent) async {
        guard event.kind == EventKind.metadata else { return }

        let metadata = NDKUserMetadata(event: event, ndk: ndk)
        await saveMetadata(metadata, for: event.pubkey)
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

    private func getCachedMetadata(for pubkey: PublicKey) async -> NDKUserMetadata? {
        // Check memory cache first
        if let entry = profileCache[pubkey] {
            // Update LRU order
            updateCacheOrder(for: pubkey)
            return entry.metadata
        }

        // Check SQLite cache
        guard let ndk = ndk else { return nil }
        if let cached = await ndk.cache.getProfileMetadata(pubkey: pubkey) {
            // Create NDKUserMetadata with pre-parsed data
            let metadata = NDKUserMetadata(
                pubkey: pubkey,
                parsedMetadata: cached.metadata,
                updatedAt: cached.updatedAt,
                eventId: cached.eventId,
                ndk: ndk
            )

            // Update memory cache
            updateCache(pubkey: pubkey, metadata: metadata)

            return metadata
        }

        return nil
    }

    private func updateCache(pubkey: PublicKey, metadata: NDKUserMetadata) {
        // Remove old entry if exists
        if profileCache[pubkey] != nil {
            cacheOrder.removeAll { $0 == pubkey }
        }

        // Add new entry
        profileCache[pubkey] = ProfileCacheEntry(metadata: metadata)
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
        cacheOrder.removeAll { $0 == pubkey }
        cacheOrder.append(pubkey)
    }
}
