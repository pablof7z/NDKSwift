# Unified Cache Architecture

## Overview

The unified cache architecture provides a consistent, layered caching system for NDKSwift with improved performance, flexibility, and maintainability.

## Architecture

### Layered Design

The cache system uses a multi-layer approach:

1. **Memory Layer** (L1): Fast in-memory cache using LRUCache
2. **Disk Layer** (L2): Persistent storage using file system
3. **Network Layer** (L3): Future support for distributed caching

```
┌─────────────────┐
│   Application   │
└────────┬────────┘
         │
┌────────▼────────┐
│ LayeredCache    │
├─────────────────┤
│ ┌─────────────┐ │
│ │Memory Layer │ │ ← Fast, limited size
│ └─────────────┘ │
│ ┌─────────────┐ │
│ │ Disk Layer  │ │ ← Persistent, larger
│ └─────────────┘ │
└─────────────────┘
```

### Key Components

#### CacheLayer Protocol

Defines the consistent interface for all cache implementations:

```swift
protocol CacheLayer: Actor {
    func get<T: Codable>(_ key: String, type: T.Type) async -> T?
    func set<T: Codable>(_ key: String, value: T, ttl: TimeInterval?) async throws
    func remove(_ key: String) async
    func clear() async
    func contains(_ key: String) async -> Bool
    func statistics() async -> CacheStatistics
}
```

#### LayeredCache

Manages multiple cache layers with configurable behavior:

```swift
let cache = LayeredCache(
    layers: [memoryLayer, diskLayer],
    writeThrough: true  // Write to all layers
)
```

#### UnifiedCacheAdapter

Bridges the new architecture to the existing NDKCacheAdapter protocol:

```swift
let adapter = try await UnifiedCacheAdapter.createStandard(
    memoryEventSize: 10000,
    memoryProfileSize: 1000
)
```

## Usage Examples

### Basic Usage

```swift
// Create a standard two-tier cache
let cache = try await CacheFactory.createStandardCache(
    diskURL: cacheDirectory,
    memorySize: 1000,
    diskSize: 10_000_000,  // 10MB
    defaultTTL: 3600       // 1 hour
)

// Store data
try await cache.set("user:123", value: userProfile)

// Retrieve data
if let profile: UserProfile = await cache.get("user:123", type: UserProfile.self) {
    // Use profile
}
```

### Custom Configuration

```swift
// Create memory-only cache with custom settings
let memoryCache = MemoryCacheLayer(
    config: CacheLayerConfig(
        maxSize: 5000,
        defaultTTL: 300,  // 5 minutes
        evictionPolicy: .lru
    )
)

// Create disk cache with size limits
let diskCache = try DiskCacheLayer(
    baseURL: diskCacheURL,
    config: CacheLayerConfig(
        maxSize: 100_000_000,  // 100MB
        evictionPolicy: .lru
    )
)

// Combine into layered cache
let cache = LayeredCache(
    layers: [memoryCache, diskCache],
    writeThrough: true
)
```

### Integration with NDK

```swift
// Create unified cache adapter
let cacheAdapter = try await UnifiedCacheAdapter.createStandard()

// Use with NDK
let ndk = NDK(
    relayPool: relayPool,
    signer: signer,
    cache: cacheAdapter
)
```

## Features

### Write-Through Caching

When enabled, writes go to all cache layers:

```swift
// Write-through enabled (default)
let cache = LayeredCache(layers: [memory, disk], writeThrough: true)
await cache.set("key", value: data)  // Writes to both memory and disk

// Write-through disabled
let cache = LayeredCache(layers: [memory, disk], writeThrough: false)
await cache.set("key", value: data)  // Writes only to memory
```

### Read-Through with Promotion

When reading, the cache checks layers in order and promotes found values:

```swift
// If value found in disk but not memory, it's promoted to memory
let value = await cache.get("key", type: MyType.self)
```

### TTL Support

Both memory and disk layers support time-to-live:

```swift
// Set with TTL
try await cache.set("session", value: sessionData, ttl: 1800)  // 30 minutes

// Set with default TTL from configuration
try await cache.set("profile", value: profileData, ttl: nil)
```

### Eviction Policies

Currently supports LRU (Least Recently Used) eviction:

```swift
let config = CacheLayerConfig(
    maxSize: 1000,
    evictionPolicy: .lru  // Future: .lfu, .fifo
)
```

### Statistics and Monitoring

Track cache performance:

```swift
let stats = await cache.statistics()
print("Hit rate: \(stats.first?.hitRate ?? 0)%")
print("Current size: \(stats.first?.currentSize ?? 0)")
print("Evictions: \(stats.first?.evictions ?? 0)")
```

## Migration Guide

### From NDKInMemoryCache

```swift
// Old
let cache = NDKInMemoryCache()

// New
let cache = await UnifiedCacheAdapter()
```

### From NDKFileCache

```swift
// Old
let cache = try NDKFileCache(directory: cacheDir)

// New
let cache = try await UnifiedCacheAdapter.createStandard(
    cacheDirectory: cacheDir
)
```

### Custom Cache Implementation

```swift
// Implement CacheLayer for custom storage
actor RedisCacheLayer: CacheLayer {
    func get<T: Codable>(_ key: String, type: T.Type) async -> T? {
        // Redis implementation
    }
    // ... other methods
}

// Use in layered cache
let cache = LayeredCache(
    layers: [memoryLayer, redisLayer, diskLayer]
)
```

## Performance Considerations

1. **Memory Layer**: O(1) access time, limited by available memory
2. **Disk Layer**: Slower access, but persistent and larger capacity
3. **Write-through**: Ensures consistency but increases write latency
4. **Batch Operations**: Use for bulk updates to minimize overhead

## Best Practices

1. **Size Configuration**: Set appropriate sizes based on your app's needs
2. **TTL Strategy**: Use shorter TTLs for frequently changing data
3. **Layer Selection**: Choose layers based on data characteristics
4. **Error Handling**: Always handle cache errors gracefully
5. **Monitoring**: Track cache statistics in production

## Future Enhancements

1. **Additional Eviction Policies**: LFU (Least Frequently Used), FIFO
2. **Compression**: Automatic compression for disk storage
3. **Encryption**: Built-in encryption for sensitive data
4. **Network Layer**: Distributed caching support
5. **Prefetching**: Intelligent data prefetching
6. **Cache Warming**: Preload frequently accessed data