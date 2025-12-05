import Foundation

/// Available cache implementations for NDK
public enum NDKCacheType: Sendable {
    /// SQLite-based cache (default) - full-featured with migrations
    case sqlite

    /// NostrDB-based cache - high-performance LMDB with text search
    case nostrdb

    /// In-memory cache - no persistence, for testing
    case memory

    /// Custom cache implementation
    case custom(any NDKCache)
}

/// Factory function to create cache instances based on type
/// - Parameters:
///   - type: The type of cache to create
///   - path: Optional path for persistent caches (SQLite and NostrDB)
/// - Returns: A cache instance conforming to NDKCache
/// - Throws: Cache initialization errors
internal func createCache(type: NDKCacheType, path: String?) async throws -> any NDKCache {
    switch type {
    case .sqlite:
        return try await NDKSQLiteCache(path: path)
    case .nostrdb:
        return try await NDKNostrDBCache(path: path)
    case .memory:
        return MemoryCache()
    case .custom(let cache):
        return cache
    }
}
