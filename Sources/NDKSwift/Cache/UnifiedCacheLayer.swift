import Foundation

/// Protocol defining a cache layer with consistent API
public protocol CacheLayer: Actor {
    /// Get a value from the cache
    func get<T: Codable>(_ key: String, type: T.Type) async -> T?
    
    /// Set a value in the cache with optional TTL
    func set<T: Codable>(_ key: String, value: T, ttl: TimeInterval?) async throws
    
    /// Remove a value from the cache
    func remove(_ key: String) async
    
    /// Clear all values from the cache
    func clear() async
    
    /// Check if a key exists in the cache
    func contains(_ key: String) async -> Bool
    
    /// Get cache statistics
    func statistics() async -> CacheStatistics
}

/// Cache statistics for monitoring and debugging
public struct CacheStatistics {
    public let hits: Int
    public let misses: Int
    public let evictions: Int
    public let currentSize: Int
    public let maxSize: Int?
    
    public var hitRate: Double {
        let total = hits + misses
        return total > 0 ? Double(hits) / Double(total) : 0
    }
}

/// Configuration for cache layers
public struct CacheLayerConfig {
    public let maxSize: Int?
    public let defaultTTL: TimeInterval?
    public let evictionPolicy: EvictionPolicy
    
    public enum EvictionPolicy {
        case lru
        case lfu
        case fifo
    }
    
    public init(
        maxSize: Int? = nil,
        defaultTTL: TimeInterval? = nil,
        evictionPolicy: EvictionPolicy = .lru
    ) {
        self.maxSize = maxSize
        self.defaultTTL = defaultTTL
        self.evictionPolicy = evictionPolicy
    }
}

/// Memory cache layer using LRUCache
public actor MemoryCacheLayer: CacheLayer {
    private let cache: LRUCache<String, Data>
    private let config: CacheLayerConfig
    private var stats = MutableCacheStatistics()
    
    private struct MutableCacheStatistics {
        var hits: Int = 0
        var misses: Int = 0
        var evictions: Int = 0
    }
    
    public init(config: CacheLayerConfig = CacheLayerConfig()) {
        self.config = config
        self.cache = LRUCache<String, Data>(
            capacity: config.maxSize ?? 1000,
            defaultTTL: config.defaultTTL
        )
    }
    
    public func get<T: Codable>(_ key: String, type: T.Type) async -> T? {
        if let data = await cache.get(key) {
            stats.hits += 1
            return try? JSONCoding.decoder.decode(T.self, from: data)
        } else {
            stats.misses += 1
            return nil
        }
    }
    
    public func set<T: Codable>(_ key: String, value: T, ttl: TimeInterval?) async throws {
        let data = try JSONCoding.encoder.encode(value)
        let effectiveTTL = ttl ?? config.defaultTTL
        
        // Check if we need to evict
        if config.maxSize != nil {
            let currentSize = await cache.allItems().count
            if currentSize >= config.maxSize! {
                stats.evictions += 1
            }
        }
        
        await cache.set(key, value: data, ttl: effectiveTTL)
    }
    
    public func remove(_ key: String) async {
        await cache.remove(key)
    }
    
    public func clear() async {
        await cache.clear()
        stats = MutableCacheStatistics()
    }
    
    public func contains(_ key: String) async -> Bool {
        return await cache.get(key) != nil
    }
    
    public func statistics() async -> CacheStatistics {
        let items = await cache.allItems()
        return CacheStatistics(
            hits: stats.hits,
            misses: stats.misses,
            evictions: stats.evictions,
            currentSize: items.count,
            maxSize: config.maxSize
        )
    }
}

/// Disk cache layer using file system
public actor DiskCacheLayer: CacheLayer {
    private let baseURL: URL
    private let config: CacheLayerConfig
    private var stats = MutableCacheStatistics()
    private var metadata: [String: CacheEntryMetadata] = [:]
    
    private struct MutableCacheStatistics {
        var hits: Int = 0
        var misses: Int = 0
        var evictions: Int = 0
    }
    
    private struct CacheEntryMetadata: Codable {
        let key: String
        let size: Int
        let createdAt: Date
        let expiresAt: Date?
        var lastAccessedAt: Date
    }
    
    public init(baseURL: URL, config: CacheLayerConfig = CacheLayerConfig()) throws {
        self.baseURL = baseURL
        self.config = config
        
        // Create cache directory if needed
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Load metadata
        Task {
            await loadMetadata()
        }
    }
    
    public func get<T: Codable>(_ key: String, type: T.Type) async -> T? {
        let fileURL = url(for: key)
        
        // Check metadata first
        if var meta = metadata[key] {
            // Check expiration
            if let expiresAt = meta.expiresAt, Date() > expiresAt {
                await remove(key)
                stats.misses += 1
                return nil
            }
            
            // Update access time
            meta.lastAccessedAt = Date()
            metadata[key] = meta
            
            // Read file
            if let data = try? Data(contentsOf: fileURL),
               let value = try? JSONCoding.decoder.decode(T.self, from: data) {
                stats.hits += 1
                return value
            }
        }
        
        stats.misses += 1
        return nil
    }
    
    public func set<T: Codable>(_ key: String, value: T, ttl: TimeInterval?) async throws {
        let data = try JSONCoding.encoder.encode(value)
        let fileURL = url(for: key)
        
        // Check size limits
        if config.maxSize != nil {
            await enforceMaxSize(reserving: data.count)
        }
        
        // Write data
        try data.write(to: fileURL)
        
        // Update metadata
        let effectiveTTL = ttl ?? config.defaultTTL
        let expiresAt = effectiveTTL.map { Date().addingTimeInterval($0) }
        
        metadata[key] = CacheEntryMetadata(
            key: key,
            size: data.count,
            createdAt: Date(),
            expiresAt: expiresAt,
            lastAccessedAt: Date()
        )
        
        saveMetadata()
    }
    
    public func remove(_ key: String) async {
        let fileURL = url(for: key)
        try? FileManager.default.removeItem(at: fileURL)
        metadata.removeValue(forKey: key)
        saveMetadata()
    }
    
    public func clear() async {
        // Remove all files
        if let files = try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
        
        metadata.removeAll()
        stats = MutableCacheStatistics()
        saveMetadata()
    }
    
    public func contains(_ key: String) async -> Bool {
        if let meta = metadata[key] {
            // Check expiration
            if let expiresAt = meta.expiresAt, Date() > expiresAt {
                await remove(key)
                return false
            }
            return true
        }
        return false
    }
    
    public func statistics() async -> CacheStatistics {
        let totalSize = metadata.values.reduce(0) { $0 + $1.size }
        return CacheStatistics(
            hits: stats.hits,
            misses: stats.misses,
            evictions: stats.evictions,
            currentSize: totalSize,
            maxSize: config.maxSize
        )
    }
    
    // MARK: - Private Methods
    
    private func url(for key: String) -> URL {
        let sanitizedKey = key.replacingOccurrences(of: "/", with: "_")
        return baseURL.appendingPathComponent(sanitizedKey)
    }
    
    private func loadMetadata() {
        let metadataURL = baseURL.appendingPathComponent(".cache_metadata")
        if let data = try? Data(contentsOf: metadataURL),
           let decoded = try? JSONCoding.decoder.decode([String: CacheEntryMetadata].self, from: data) {
            metadata = decoded
        }
    }
    
    private func saveMetadata() {
        let metadataURL = baseURL.appendingPathComponent(".cache_metadata")
        if let data = try? JSONCoding.encoder.encode(metadata) {
            try? data.write(to: metadataURL)
        }
    }
    
    private func enforceMaxSize(reserving: Int) async {
        guard let maxSize = config.maxSize else { return }
        
        var currentSize = metadata.values.reduce(0) { $0 + $1.size }
        
        // Need to free space?
        if currentSize + reserving > maxSize {
            // Sort by access time (LRU)
            let sorted = metadata.values.sorted { $0.lastAccessedAt < $1.lastAccessedAt }
            
            for entry in sorted {
                if currentSize + reserving <= maxSize {
                    break
                }
                
                await remove(entry.key)
                currentSize -= entry.size
                stats.evictions += 1
            }
        }
    }
}

/// Layered cache combining multiple cache layers
public actor LayeredCache {
    private let layers: [CacheLayer]
    private let writeThrough: Bool
    
    public init(layers: [CacheLayer], writeThrough: Bool = true) {
        self.layers = layers
        self.writeThrough = writeThrough
    }
    
    /// Get a value, checking each layer in order
    public func get<T: Codable>(_ key: String, type: T.Type) async -> T? {
        for (index, layer) in layers.enumerated() {
            if let value = await layer.get(key, type: type) {
                // Write-through to faster layers
                if writeThrough && index > 0 {
                    for i in 0..<index {
                        try? await layers[i].set(key, value: value, ttl: nil)
                    }
                }
                return value
            }
        }
        return nil
    }
    
    /// Set a value in all layers (write-through) or just the first layer
    public func set<T: Codable>(_ key: String, value: T, ttl: TimeInterval? = nil) async throws {
        if writeThrough {
            // Write to all layers
            for layer in layers {
                try await layer.set(key, value: value, ttl: ttl)
            }
        } else {
            // Write only to first layer
            if let firstLayer = layers.first {
                try await firstLayer.set(key, value: value, ttl: ttl)
            }
        }
    }
    
    /// Check if key exists in any layer
    public func contains(_ key: String) async -> Bool {
        for layer in layers {
            if await layer.contains(key) {
                return true
            }
        }
        return false
    }
    
    /// Remove from all layers
    public func remove(_ key: String) async {
        for layer in layers {
            await layer.remove(key)
        }
    }
    
    /// Clear all layers
    public func clear() async {
        for layer in layers {
            await layer.clear()
        }
    }
    
    /// Get combined statistics from all layers
    public func statistics() async -> [CacheStatistics] {
        var stats: [CacheStatistics] = []
        for layer in layers {
            stats.append(await layer.statistics())
        }
        return stats
    }
}

/// Factory for creating pre-configured cache setups
public enum CacheFactory {
    /// Create a standard two-tier cache (memory + disk)
    public static func createStandardCache(
        diskURL: URL,
        memorySize: Int = 1000,
        diskSize: Int = 10_000_000, // 10MB
        defaultTTL: TimeInterval? = 3600 // 1 hour
    ) async throws -> LayeredCache {
        let memoryLayer = MemoryCacheLayer(
            config: CacheLayerConfig(
                maxSize: memorySize,
                defaultTTL: defaultTTL,
                evictionPolicy: .lru
            )
        )
        
        let diskLayer = try DiskCacheLayer(
            baseURL: diskURL,
            config: CacheLayerConfig(
                maxSize: diskSize,
                defaultTTL: defaultTTL,
                evictionPolicy: .lru
            )
        )
        
        return LayeredCache(layers: [memoryLayer, diskLayer])
    }
    
    /// Create a memory-only cache
    public static func createMemoryCache(
        size: Int = 1000,
        defaultTTL: TimeInterval? = nil
    ) async -> LayeredCache {
        let memoryLayer = MemoryCacheLayer(
            config: CacheLayerConfig(
                maxSize: size,
                defaultTTL: defaultTTL,
                evictionPolicy: .lru
            )
        )
        
        return LayeredCache(layers: [memoryLayer])
    }
}