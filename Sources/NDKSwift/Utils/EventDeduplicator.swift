import Foundation

/// Configuration for event deduplication
public struct EventDeduplicationConfig {
    /// Maximum number of event IDs to track
    public let cacheSize: Int
    
    /// Time-to-live for cached event IDs (nil for no expiration)
    public let ttl: TimeInterval?
    
    /// Whether to track events per relay
    public let perRelayTracking: Bool
    
    /// Default configuration for general use
    public static let `default` = EventDeduplicationConfig(
        cacheSize: 10000,
        ttl: 3600, // 1 hour
        perRelayTracking: false
    )
    
    /// Configuration for high-volume scenarios
    public static let highVolume = EventDeduplicationConfig(
        cacheSize: 50000,
        ttl: 1800, // 30 minutes
        perRelayTracking: true
    )
    
    /// Configuration for memory-constrained environments
    public static let lowMemory = EventDeduplicationConfig(
        cacheSize: 1000,
        ttl: 600, // 10 minutes
        perRelayTracking: false
    )
    
    public init(
        cacheSize: Int = 10000,
        ttl: TimeInterval? = 3600,
        perRelayTracking: Bool = false
    ) {
        self.cacheSize = cacheSize
        self.ttl = ttl
        self.perRelayTracking = perRelayTracking
    }
}

/// Centralized event deduplicator using LRU cache
public actor EventDeduplicator {
    /// Statistics for monitoring
    public struct Statistics {
        public var totalChecks: Int = 0
        public var duplicates: Int = 0
        public var uniqueEvents: Int = 0
        public var cacheHits: Int = 0
        public var cacheMisses: Int = 0
        public var evictions: Int = 0
        
        public var duplicateRate: Double {
            guard totalChecks > 0 else { return 0 }
            return Double(duplicates) / Double(totalChecks)
        }
        
        public var cacheHitRate: Double {
            guard totalChecks > 0 else { return 0 }
            return Double(cacheHits) / Double(totalChecks)
        }
    }
    
    private let config: EventDeduplicationConfig
    private let globalCache: LRUCache<EventID, Date>
    private var perRelayCache: [String: LRUCache<EventID, Date>] = [:]
    private var statistics = Statistics()
    
    public init(config: EventDeduplicationConfig = .default) {
        self.config = config
        self.globalCache = LRUCache(capacity: config.cacheSize, defaultTTL: config.ttl)
    }
    
    /// Check if an event is a duplicate
    /// - Parameters:
    ///   - eventId: The event ID to check
    ///   - relayUrl: Optional relay URL for per-relay tracking
    /// - Returns: true if the event is a duplicate, false if it's new
    public func isDuplicate(_ eventId: EventID, from relayUrl: String? = nil) async -> Bool {
        statistics.totalChecks += 1
        
        // Check global cache
        if await globalCache.get(eventId) != nil {
            statistics.duplicates += 1
            statistics.cacheHits += 1
            return true
        }
        
        // Check per-relay cache if enabled
        if config.perRelayTracking, let relayUrl = relayUrl {
            let relayCache = await getOrCreateRelayCache(for: relayUrl)
            if await relayCache.get(eventId) != nil {
                statistics.duplicates += 1
                statistics.cacheHits += 1
                return true
            }
        }
        
        statistics.cacheMisses += 1
        return false
    }
    
    /// Mark an event as seen
    /// - Parameters:
    ///   - eventId: The event ID to mark
    ///   - relayUrl: Optional relay URL for per-relay tracking
    public func markSeen(_ eventId: EventID, from relayUrl: String? = nil) async {
        let now = Date()
        
        // Add to global cache
        await globalCache.set(eventId, value: now)
        statistics.uniqueEvents += 1
        
        // Add to per-relay cache if enabled
        if config.perRelayTracking, let relayUrl = relayUrl {
            let relayCache = await getOrCreateRelayCache(for: relayUrl)
            await relayCache.set(eventId, value: now)
        }
    }
    
    /// Process an event, checking for duplicates and marking as seen if new
    /// - Parameters:
    ///   - event: The event to process
    ///   - relayUrl: Optional relay URL for per-relay tracking
    /// - Returns: true if the event is new (not a duplicate), false if duplicate
    public func processEvent(_ event: NDKEvent, from relayUrl: String? = nil) async -> Bool {
        guard let eventId = event.id else { return false }
        
        // Check if duplicate
        if await isDuplicate(eventId, from: relayUrl) {
            return false
        }
        
        // Mark as seen
        await markSeen(eventId, from: relayUrl)
        return true
    }
    
    /// Clear all cached data
    public func clear() async {
        await globalCache.clear()
        for (_, cache) in perRelayCache {
            await cache.clear()
        }
        perRelayCache.removeAll()
        
        // Reset statistics but keep eviction count
        let evictions = statistics.evictions
        statistics = Statistics()
        statistics.evictions = evictions
    }
    
    /// Clear cache for a specific relay
    public func clearRelay(_ relayUrl: String) async {
        if let cache = perRelayCache[relayUrl] {
            await cache.clear()
            perRelayCache.removeValue(forKey: relayUrl)
        }
    }
    
    /// Get current statistics
    public func getStatistics() -> Statistics {
        statistics
    }
    
    /// Reset statistics
    public func resetStatistics() {
        statistics = Statistics()
    }
    
    /// Get cache sizes
    public func getCacheSizes() async -> (global: Int, perRelay: [String: Int]) {
        let globalSize = await globalCache.allItems().count
        var perRelaySize: [String: Int] = [:]
        
        for (url, cache) in perRelayCache {
            perRelaySize[url] = await cache.allItems().count
        }
        
        return (globalSize, perRelaySize)
    }
    
    // MARK: - Private Methods
    
    private func getOrCreateRelayCache(for relayUrl: String) -> LRUCache<EventID, Date> {
        if let cache = perRelayCache[relayUrl] {
            return cache
        }
        
        let cache = LRUCache<EventID, Date>(
            capacity: config.cacheSize / 10, // Use 10% of global size per relay
            defaultTTL: config.ttl
        )
        perRelayCache[relayUrl] = cache
        return cache
    }
}

/// Extension to integrate with NDK
extension NDK {
    /// Global event deduplicator
    public var eventDeduplicator: EventDeduplicator {
        // This would be initialized in NDK.init() with appropriate config
        // For now, return a default instance
        EventDeduplicator(config: .default)
    }
}

/// Extension to simplify event processing
extension NDKEvent {
    /// Check if this event is a duplicate using the global deduplicator
    public func isDuplicate(in ndk: NDK, from relayUrl: String? = nil) async -> Bool {
        guard let id = self.id else { return false }
        return await ndk.eventDeduplicator.isDuplicate(id, from: relayUrl)
    }
    
    /// Mark this event as seen using the global deduplicator
    public func markSeen(in ndk: NDK, from relayUrl: String? = nil) async {
        guard let id = self.id else { return }
        await ndk.eventDeduplicator.markSeen(id, from: relayUrl)
    }
}