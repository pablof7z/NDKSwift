import Foundation

/// A thread-safe LRU (Least Recently Used) cache implementation
actor LRUCache<Key: Hashable, Value> {
    private class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        var expiresAt: Date?

        init(key: Key, value: Value, ttl: TimeInterval?) {
            self.key = key
            self.value = value
            if let ttl = ttl {
                self.expiresAt = Date().addingTimeInterval(ttl)
            }
        }

        var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return Date() > expiresAt
        }
    }

    private let capacity: Int
    private let defaultTTL: TimeInterval?
    private var cache: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?

    init(capacity: Int, defaultTTL: TimeInterval? = nil) {
        self.capacity = capacity
        self.defaultTTL = defaultTTL
    }

    /// Get a value from the cache
    func get(_ key: Key) -> Value? {
        guard let node = cache[key] else { return nil }

        // Check if expired
        if node.isExpired {
            remove(key)
            return nil
        }

        // Move to front (most recently used)
        moveToFront(node)
        return node.value
    }

    /// Set a value in the cache
    func set(_ key: Key, value: Value, ttl: TimeInterval? = nil) {
        // Remove existing node if present
        if let existingNode = cache[key] {
            removeNode(existingNode)
        }

        // Create new node
        let node = Node(key: key, value: value, ttl: ttl ?? defaultTTL)
        cache[key] = node

        // Add to front
        addToFront(node)

        // Evict if over capacity
        if cache.count > capacity {
            evictLRU()
        }
    }

    /// Remove a value from the cache
    func remove(_ key: Key) {
        guard let node = cache[key] else { return }
        removeNode(node)
    }

    /// Clear all items from the cache
    func clear() {
        cache.removeAll()
        head = nil
        tail = nil
    }

    /// Get all non-expired values
    func allValues() -> [Value] {
        let now = Date()
        return cache.values.compactMap { node in
            if let expiresAt = node.expiresAt, now > expiresAt {
                return nil
            }
            return node.value
        }
    }

    /// Get all non-expired key-value pairs
    func allItems() -> [(Key, Value)] {
        let now = Date()
        return cache.compactMap { key, node in
            if let expiresAt = node.expiresAt, now > expiresAt {
                return nil
            }
            return (key, node.value)
        }
    }

    // MARK: - Private Methods

    private func addToFront(_ node: Node) {
        node.next = head
        node.prev = nil

        if let head = head {
            head.prev = node
        }

        head = node

        if tail == nil {
            tail = node
        }
    }

    private func removeNode(_ node: Node) {
        cache.removeValue(forKey: node.key)

        if node.prev != nil {
            node.prev?.next = node.next
        } else {
            head = node.next
        }

        if node.next != nil {
            node.next?.prev = node.prev
        } else {
            tail = node.prev
        }
    }

    private func moveToFront(_ node: Node) {
        if node === head { return }

        removeNode(node)
        cache[node.key] = node // Re-add to cache
        addToFront(node)
    }

    private func evictLRU() {
        guard let tail = tail else { return }
        removeNode(tail)
    }

    /// Clean up expired entries
    func cleanupExpired() {
        let now = Date()
        let expiredKeys = cache.compactMap { key, node -> Key? in
            if let expiresAt = node.expiresAt, now > expiresAt {
                return key
            }
            return nil
        }

        for key in expiredKeys {
            remove(key)
        }
    }
}
