import Foundation

/// Configuration for profile management
public struct NDKProfileConfig {
    /// Maximum number of profiles to keep in memory cache
    public var cacheSize: Int
    
    /// Time interval before cached profiles are considered stale (in seconds)
    public var staleAfter: TimeInterval
    
    public init(
        cacheSize: Int = 1000,
        staleAfter: TimeInterval = 3600 // 1 hour
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
    
    /// Fetch a single profile with caching and optional force refresh
    /// The subscription manager automatically batches multiple profile requests
    public func fetchProfile(for pubkey: PublicKey, forceRefresh: Bool = false) async throws -> NDKUserProfile? {
        // Check cache first
        if !forceRefresh {
            if let cached = checkCache(for: pubkey) {
                return cached
            }
        }
        
        // Fetch profile - subscription manager handles batching automatically
        return try await fetchSingleProfile(pubkey)
    }
    
    /// Fetch multiple profiles efficiently
    /// The subscription manager will automatically batch these into a single request
    public func fetchProfiles(for pubkeys: [PublicKey], forceRefresh: Bool = false) async throws -> [PublicKey: NDKUserProfile] {
        var results: [PublicKey: NDKUserProfile] = [:]
        var toFetch: [PublicKey] = []
        
        // Check cache for each pubkey
        if !forceRefresh {
            for pubkey in pubkeys {
                if let cached = checkCache(for: pubkey) {
                    results[pubkey] = cached
                } else {
                    toFetch.append(pubkey)
                }
            }
        } else {
            toFetch = pubkeys
        }
        
        // Fetch remaining profiles - subscription manager will batch them automatically
        if !toFetch.isEmpty {
            guard let ndk = ndk else {
                throw NDKError.notConfigured("NDK instance not available")
            }
            
            let filter = NDKFilter(
                authors: toFetch,
                kinds: [EventKind.metadata]
            )
            
            let events = try await ndk.fetchEvents([filter])
            
            // Process events
            for event in events {
                guard let profileData = event.content.data(using: String.Encoding.utf8),
                      let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) else {
                    continue
                }
                
                let eventPubkey = event.pubkey
                results[eventPubkey] = profile
                updateCache(pubkey: eventPubkey, profile: profile)
                
                // Notify any active observations
                if let wrappers = activeObservations[eventPubkey] {
                    for wrapper in wrappers {
                        wrapper.continuation.yield(profile)
                    }
                }
                
                // Save to cache
                Task {
                    try? await ndk.cache.saveProfile(profile, pubkey: eventPubkey)
                }
            }
        }
        
        return results
    }
    
    /// Observe profile updates for a given pubkey
    /// Returns an AsyncSequence that yields the profile immediately if cached,
    /// then yields updates as they arrive from relays
    /// - Parameters:
    ///   - pubkey: The public key to observe
    ///   - closeOnEose: If true, closes the subscription after receiving initial data (EOSE)
    public func observeProfile(for pubkey: PublicKey, closeOnEose: Bool = false) -> AsyncStream<NDKUserProfile?> {
        AsyncStream { continuation in
            Task {
                // Add continuation to active observations
                let wrapper = ContinuationWrapper(continuation)
                if activeObservations[pubkey] == nil {
                    activeObservations[pubkey] = []
                }
                activeObservations[pubkey]?.append(wrapper)
                
                // Yield cached profile immediately if available
                if let cached = checkCache(for: pubkey) {
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
                
                let subscription = await ndk.subscribe(
                    filters: [filter],
                    closeOnEose: closeOnEose
                )
                
                // Process events from subscription
                do {
                    for try await event in subscription {
                        if let profileData = event.content.data(using: .utf8),
                           let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) {
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
                } catch {
                    // Subscription ended or errored
                }
                
                // Clean up when done
                activeObservations[pubkey]?.removeAll { $0 === wrapper }
                if activeObservations[pubkey]?.isEmpty == true {
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
    
    private func checkCache(for pubkey: PublicKey) -> NDKUserProfile? {
        guard let entry = profileCache[pubkey] else { return nil }
        
        // Check if stale
        if entry.isStale(after: config.staleAfter) {
            // Remove stale entry
            profileCache.removeValue(forKey: pubkey)
            cacheOrder.removeAll { $0 == pubkey }
            return nil
        }
        
        // Update LRU order
        updateCacheOrder(for: pubkey)
        
        return entry.profile
    }
    
    private func updateCache(pubkey: PublicKey, profile: NDKUserProfile) {
        // Remove old entry if exists
        if profileCache[pubkey] != nil {
            cacheOrder.removeAll { $0 == pubkey }
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
        cacheOrder.removeAll { $0 == pubkey }
        cacheOrder.append(pubkey)
    }
    
    private func fetchSingleProfile(_ pubkey: PublicKey) async throws -> NDKUserProfile? {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK instance not available")
        }
        
        // Create filter for kind 0 events (user metadata)
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.metadata],
            limit: 1
        )
        
        // Fetch the event
        guard let event = try await ndk.fetchEvent(filter) else {
            return nil
        }
        
        // Parse the profile from event content
        guard let profileData = event.content.data(using: .utf8),
              let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) else {
            return nil
        }
        
        // Update cache
        updateCache(pubkey: pubkey, profile: profile)
        
        // Also save to persistent cache
        try? await ndk.cache.saveProfile(profile, pubkey: pubkey)
        
        return profile
    }
}