import Foundation

/// Configuration for profile management
public struct NDKProfileConfig {
    /// Maximum number of profiles to keep in memory cache
    public var cacheSize: Int
    
    /// Time interval before cached profiles are considered stale (in seconds)
    public var staleAfter: TimeInterval
    
    /// Whether to automatically batch profile requests
    public var batchRequests: Bool
    
    /// Delay before executing batched requests (in seconds)
    public var batchDelay: TimeInterval
    
    /// Maximum number of profiles to request in a single subscription
    public var maxBatchSize: Int
    
    public init(
        cacheSize: Int = 1000,
        staleAfter: TimeInterval = 3600, // 1 hour
        batchRequests: Bool = true,
        batchDelay: TimeInterval = 0.1,
        maxBatchSize: Int = 100
    ) {
        self.cacheSize = cacheSize
        self.staleAfter = staleAfter
        self.batchRequests = batchRequests
        self.batchDelay = batchDelay
        self.maxBatchSize = maxBatchSize
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

/// Manager for efficient profile fetching with caching and batching
public actor NDKProfileManager {
    private weak var ndk: NDK?
    private let config: NDKProfileConfig
    
    /// In-memory LRU cache for profiles
    private var profileCache: [PublicKey: ProfileCacheEntry] = [:]
    private var cacheOrder: [PublicKey] = [] // For LRU tracking
    
    /// Pending profile requests waiting to be batched
    private var pendingRequests: [PublicKey: [CheckedContinuation<NDKUserProfile?, Error>]] = [:]
    
    /// Timer task for batching
    private var batchTask: Task<Void, Never>?
    
    public init(ndk: NDK, config: NDKProfileConfig = .default) {
        self.ndk = ndk
        self.config = config
    }
    
    /// Fetch a single profile with caching and optional force refresh
    public func fetchProfile(for pubkey: PublicKey, forceRefresh: Bool = false) async throws -> NDKUserProfile? {
        // Check cache first
        if !forceRefresh {
            if let cached = checkCache(for: pubkey) {
                return cached
            }
        }
        
        // If batching is disabled or force refresh, fetch immediately
        if !config.batchRequests || forceRefresh {
            return try await fetchProfileImmediately(for: pubkey)
        }
        
        // Add to pending requests for batching
        return try await withCheckedThrowingContinuation { continuation in
            if pendingRequests[pubkey] == nil {
                pendingRequests[pubkey] = []
            }
            pendingRequests[pubkey]?.append(continuation)
            
            // Schedule batch processing
            scheduleBatchProcessing()
        }
    }
    
    /// Fetch multiple profiles efficiently
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
        
        // Fetch remaining profiles
        if !toFetch.isEmpty {
            let fetched = try await fetchProfilesBatch(toFetch)
            results.merge(fetched) { _, new in new }
        }
        
        return results
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
    
    private func fetchProfileImmediately(for pubkey: PublicKey) async throws -> NDKUserProfile? {
        guard let ndk = ndk else {
            throw NDKError.custom("NDK instance not available")
        }
        
        let user = ndk.getUser(pubkey)
        let profile = try await user.fetchProfile(forceRefresh: true)
        
        if let profile = profile {
            updateCache(pubkey: pubkey, profile: profile)
        }
        
        return profile
    }
    
    private func fetchProfilesBatch(_ pubkeys: [PublicKey]) async throws -> [PublicKey: NDKUserProfile] {
        guard let ndk = ndk else {
            throw NDKError.custom("NDK instance not available")
        }
        
        var results: [PublicKey: NDKUserProfile] = [:]
        
        // Split into batches if needed
        let batches = pubkeys.chunked(into: config.maxBatchSize)
        
        for batch in batches {
            // Create filter for metadata events
            let filter = NDKFilter(
                authors: batch,
                kinds: [EventKind.metadata],
                limit: batch.count
            )
            
            // Fetch events
            let events = try await ndk.fetchEvents(filters: [filter])
            
            // Process events
            for event in events {
                guard let profileData = event.content.data(using: .utf8),
                      let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) else {
                    continue
                }
                
                results[event.pubkey] = profile
                updateCache(pubkey: event.pubkey, profile: profile)
                
                // Update the user object if available
                let user = ndk.getUser(event.pubkey)
                user.updateProfile(profile)
            }
        }
        
        return results
    }
    
    private func scheduleBatchProcessing() {
        // Cancel existing task if any
        batchTask?.cancel()
        
        // Schedule new batch processing
        batchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(config.batchDelay * 1_000_000_000))
            await self?.processPendingBatch()
        }
    }
    
    private func processPendingBatch() async {
        guard !pendingRequests.isEmpty else { return }
        
        // Get all pending pubkeys
        let pubkeys = Array(pendingRequests.keys)
        let continuations = pendingRequests
        pendingRequests.removeAll()
        
        do {
            // Fetch all profiles in batch
            let profiles = try await fetchProfilesBatch(pubkeys)
            
            // Resume all continuations
            for (pubkey, conts) in continuations {
                let profile = profiles[pubkey]
                for cont in conts {
                    cont.resume(returning: profile)
                }
            }
        } catch {
            // Resume all continuations with error
            for (_, conts) in continuations {
                for cont in conts {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}