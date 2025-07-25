# Profile Manager Caching Strategy

## Overview

The profile manager in NDKSwift provides an in-memory LRU cache for user profiles that is always synchronized with the database. When profile updates arrive from relays, both the memory cache and database are updated together, ensuring consistency.

## Architecture

The caching system consists of:
1. **In-memory LRU cache** in `NDKProfileManager` for fast access
2. **Persistent storage** in the database (SQLite or other cache adapter)
3. **Automatic synchronization** between memory and persistent storage

## Key Design Principles

### Always Synchronized

The memory cache and database are updated atomically when new profile events arrive:
- Profile updates from relays update both caches simultaneously
- There's no scenario where the database has newer data than memory cache
- The cache is never "stale" relative to the database

### LRU Memory Cache

The in-memory cache uses LRU (Least Recently Used) eviction:

```swift
// Simple cache entry - no staleness tracking needed
private struct ProfileCacheEntry {
    let profile: NDKUserProfile
}

// In-memory LRU cache
private var profileCache: [PublicKey: ProfileCacheEntry] = [:]
private var cacheOrder: [PublicKey] = [] // For LRU tracking
```

The cache stores parsed `NDKUserProfile` objects to avoid repeated JSON decoding.

## How It Works

### Profile Loading Flow

1. **Cache Hit (Fastest Path)**:
   - Check memory cache
   - If found → return immediately
   - No database access, no JSON decoding
   - Just a dictionary lookup: O(1)

2. **Cache Miss**:
   - Memory cache miss → fetch from database
   - Database loads and decodes the profile
   - Result stored in memory cache
   - Future requests hit memory cache

3. **Profile Updates**:
   - New profile event arrives from relay
   - Update memory cache
   - Update database
   - Notify all active observers

### The `maxAge` Parameter

The `observe` method accepts a `maxAge` parameter that controls relay subscription behavior (consistent with `ndk.observe`):

```swift
// Use cached data, keep subscription open for updates
for await profile in profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
    // Returns cached profile immediately, subscription closes after 1 hour
}

// Always get real-time updates
for await profile in profileManager.observe(for: pubkey, maxAge: 0) {
    // Returns cached profile immediately, keeps subscription open
}
```

The `maxAge` parameter is passed directly to the underlying `NDKDataSource`:
- `maxAge: 0` - Keep subscription open for real-time updates
- `maxAge: >0` - Use cache if available, close subscription after EOSE if data is fresh enough

## Implementation Details

### Memory Cache Management

```swift
private func updateCache(pubkey: PublicKey, profile: NDKUserProfile) {
    // Remove old entry if exists
    if profileCache[pubkey] != nil {
        cacheOrder.removeAll(value: pubkey)
    }
    
    // Add new entry
    profileCache[pubkey] = ProfileCacheEntry(profile: profile)
    cacheOrder.append(pubkey)
    
    // Enforce cache size limit
    while cacheOrder.count > config.cacheSize {
        if let oldestKey = cacheOrder.first {
            profileCache.removeValue(forKey: oldestKey)
            cacheOrder.removeFirst()
        }
    }
}
```

### LRU Ordering

When a profile is accessed, it's moved to the end of the LRU list:

```swift
private func updateCacheOrder(for pubkey: PublicKey) {
    // Move to end (most recently used)
    cacheOrder.removeAll(value: pubkey)
    cacheOrder.append(pubkey)
}
```

## Key Benefits

1. **No Database Round-trips**: Previously loaded profiles are served from memory
2. **No JSON Decoding**: Parsed profiles are kept in memory
3. **Automatic Synchronization**: Memory and database always in sync
4. **LRU Eviction**: Frequently accessed profiles stay in memory
5. **Configurable Cache Size**: Default from `NetworkConstants.profileCacheSize`

## Performance Characteristics

- **Cache Hit**: O(1) dictionary lookup, no I/O
- **Cache Miss**: Database query + JSON decode + memory cache update
- **Updates**: Both caches updated atomically
- **Memory Usage**: Bounded by cache size configuration

## Usage Examples

### Feed View (Many Profiles)

```swift
// Use cached data, close subscription after 1 hour
for await profile in profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
    // Display profile
    break // If you only need one value
}
```

### Profile Page (Real-time Updates)

```swift
// Keep subscription open for real-time updates
for await profile in profileManager.observe(for: pubkey, maxAge: 0) {
    // Display and react to updates
}
```

### Batch Loading

```swift
// Load multiple profiles efficiently
for pubkey in pubkeys {
    Task {
        for await profile in profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
            // Cache prevents redundant fetches
            updateUI(pubkey: pubkey, profile: profile)
            break
        }
    }
}
```

## Configuration

```swift
let config = NDKProfileConfig(
    cacheSize: 1000  // Keep 1000 profiles in memory
)

let profileManager = NDKProfileManager(ndk: ndk, config: config)
```