import Foundation

/// Available cache implementations for NDK
///
/// To create a cache instance, import the appropriate module and construct directly:
/// - `MemoryCache()` - NDKSwiftCore (no persistence)
/// - `NDKSQLiteCache(path:)` - NDKSwiftSQLite (full-featured)
/// - `NDKNostrDBCache(path:)` - NDKSwiftNostrDB (high-performance)
public enum NDKCacheType: Sendable {
    /// SQLite-based cache (default) - full-featured with migrations
    /// Use `import NDKSwiftSQLite` and `NDKSQLiteCache(path:)`
    case sqlite

    /// NostrDB-based cache - high-performance LMDB with text search
    /// Use `import NDKSwiftNostrDB` and `NDKNostrDBCache(path:)`
    case nostrdb

    /// In-memory cache - no persistence, for testing
    /// Use `MemoryCache()` from NDKSwiftCore
    case memory

    /// Custom cache implementation
    case custom(any NDKCache)
}
