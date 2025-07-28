import Foundation

/// Thread-safe LRU (Least Recently Used) cache with TTL support
///
/// This cache implementation provides:
/// - Automatic eviction of least recently used items when capacity is reached
/// - Time-to-live (TTL) support for automatic expiration
/// - Thread-safe access using Swift actors
/// - Performance statistics tracking (hits/misses)
///
/// Example usage:
/// ```swift
/// let cache = LRUCache<String, Data>(capacity: 100, defaultTTL: 3600)
/// await cache.set("key", value: data)
/// if let cached = await cache.get("key") {
///     // Use cached data
/// }
/// ```
actor LRUCache<Key: Hashable, Value> {
    /// Internal structure to store cached values with metadata
    private struct CacheEntry {
        let value: Value
        let expiresAt: Date
        var lastAccessTime: Date
    }

    /// Main storage dictionary mapping keys to cache entries
    private var cache: [Key: CacheEntry] = [:]
    
    /// Ordered list of keys by access time (most recent at end)
    private var accessOrder: [Key] = []
    
    /// Maximum number of items the cache can hold
    private let capacity: Int
    
    /// Default time-to-live for cache entries in seconds
    private let defaultTTL: TimeInterval

    // MARK: - Statistics
    
    /// Number of successful cache hits
    private var hits: Int = 0
    
    /// Number of cache misses
    private var misses: Int = 0

    /// Initialize a new LRU cache
    /// - Parameters:
    ///   - capacity: Maximum number of items to store (default: 100)
    ///   - defaultTTL: Default time-to-live for entries in seconds (default: 1 hour)
    init(capacity: Int = 100, defaultTTL: TimeInterval = TimeConstants.hour) {
        self.capacity = capacity
        self.defaultTTL = defaultTTL
    }

    /// Retrieve a value from the cache
    /// - Parameter key: The key to look up
    /// - Returns: The cached value if it exists and hasn't expired, nil otherwise
    /// - Note: This method updates the access order, making the item the most recently used
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
    /// - Note: This operation is O(n) in the worst case. For better performance with very large caches,
    ///         consider using a doubly linked list with a hash map of nodes.
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