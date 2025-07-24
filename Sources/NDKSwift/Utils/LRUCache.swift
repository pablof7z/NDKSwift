import Foundation

/// Thread-safe LRU (Least Recently Used) cache with TTL support
actor LRUCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let value: Value
        let expiresAt: Date
        var lastAccessTime: Date
    }
    
    private var cache: [Key: CacheEntry] = [:]
    private var accessOrder: [Key] = []
    private let capacity: Int
    private let defaultTTL: TimeInterval
    
    // Statistics
    private var hits: Int = 0
    private var misses: Int = 0
    
    init(capacity: Int = 100, defaultTTL: TimeInterval = TimeConstants.hour) {
        self.capacity = capacity
        self.defaultTTL = defaultTTL
    }
    
    /// Get a value from the cache
    func get(_ key: Key) -> Value? {
        guard var entry = cache[key] else {
            misses += 1
            return nil
        }
        
        // Check if expired
        if Date() > entry.expiresAt {
            cache.removeValue(forKey: key)
            removeFromAccessOrder(key)
            misses += 1
            return nil
        }
        
        // Update access time and order
        entry.lastAccessTime = Date()
        cache[key] = entry
        
        // Move to end of access order
        removeFromAccessOrder(key)
        accessOrder.append(key)
        
        hits += 1
        return entry.value
    }
    
    /// Set a value in the cache
    func set(_ key: Key, value: Value, ttl: TimeInterval? = nil) {
        let expiresAt = Date().addingTimeInterval(ttl ?? defaultTTL)
        let entry = CacheEntry(
            value: value,
            expiresAt: expiresAt,
            lastAccessTime: Date()
        )
        
        // If key exists, update it
        if cache[key] != nil {
            cache[key] = entry
            // Move to end of access order
            removeFromAccessOrder(key)
            accessOrder.append(key)
        } else {
            // New entry
            cache[key] = entry
            accessOrder.append(key)
            
            // Evict if over capacity
            while cache.count > capacity {
                evictOldest()
            }
        }
    }
    
    /// Delete a value from the cache
    func delete(_ key: Key) {
        cache.removeValue(forKey: key)
        removeFromAccessOrder(key)
    }
    
    /// Clear all values from the cache
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
        hits = 0
        misses = 0
    }
    
    /// Get all items in the cache (for inspection/debugging)
    func allItems() -> [Key: Value] {
        cleanupExpired()
        return cache.mapValues { $0.value }
    }
    
    /// Get cache hit rate
    func getHitRate() -> Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }
    
    /// Clean up expired entries
    func cleanupExpired() {
        let now = Date()
        let expiredKeys = cache.compactMap { key, entry in
            entry.expiresAt < now ? key : nil
        }
        
        for key in expiredKeys {
            cache.removeValue(forKey: key)
            removeFromAccessOrder(key)
        }
    }
    
    /// Get all keys in the cache
    func getAllKeys() -> [Key] {
        return Array(cache.keys)
    }
    
    // MARK: - Private
    
    /// Remove a key from the access order list
    private func removeFromAccessOrder(_ key: Key) {
        accessOrder.removeAll(value: key)
    }
    
    private func evictOldest() {
        guard !accessOrder.isEmpty else { return }
        
        // Find the oldest entry that isn't expired
        var indexToRemove: Int?
        let now = Date()
        
        for (index, key) in accessOrder.enumerated() {
            if let entry = cache[key], entry.expiresAt > now {
                indexToRemove = index
                break
            } else {
                // Remove expired entry
                cache.removeValue(forKey: key)
            }
        }
        
        if let index = indexToRemove {
            let key = accessOrder.remove(at: index)
            cache.removeValue(forKey: key)
        } else {
            // All entries were expired, clear access order
            accessOrder.removeAll()
        }
    }
}