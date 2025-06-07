# Profile Fetching in NDKSwift

NDKSwift provides an ergonomic and efficient system for fetching Nostr user profiles with built-in caching and automatic batching capabilities.

## Overview

The profile fetching system consists of three main components:

1. **NDKUser.fetchProfile()** - Fetches a single user's profile
2. **NDKProfileManager** - Manages profile caching and batching
3. **Smart Caching** - In-memory LRU cache to prevent redundant fetches

## Basic Usage

### Fetching a Single Profile

```swift
let ndk = NDK(relayUrls: ["wss://relay.damus.io"])
await ndk.connect()

// Get a user
let user = ndk.getUser("pubkey_hex_here")

// Fetch their profile
if let profile = try await user.fetchProfile() {
    print("Name: \(profile.name ?? "Unknown")")
    print("About: \(profile.about ?? "")")
    print("Picture: \(profile.picture ?? "")")
}
```

### Fetching Multiple Profiles

```swift
// Fetch multiple profiles efficiently
let pubkeys = ["pubkey1", "pubkey2", "pubkey3"]
let profiles = try await ndk.profileManager.fetchProfiles(for: pubkeys)

for (pubkey, profile) in profiles {
    print("\(pubkey): \(profile.name ?? "Unknown")")
}
```

## Caching

### Default Behavior

By default, NDKSwift caches up to 1000 user profiles in memory. Cached profiles are considered fresh for 1 hour.

```swift
// This will use the cache if available
let profile = try await user.fetchProfile()

// Force a fresh fetch from relays
let freshProfile = try await user.fetchProfile(forceRefresh: true)
```

### Custom Cache Configuration

```swift
let profileConfig = NDKProfileConfig(
    cacheSize: 5000,        // Cache up to 5000 profiles
    staleAfter: 1800,       // Consider stale after 30 minutes
    batchRequests: true,    // Enable request batching
    batchDelay: 0.2,        // Wait 200ms to batch requests
    maxBatchSize: 50        // Batch up to 50 profiles per request
)

let ndk = NDK(
    relayUrls: ["wss://relay.damus.io"],
    profileConfig: profileConfig
)
```

## Automatic Batching

When multiple profile requests are made in quick succession, NDKSwift automatically batches them into a single subscription to reduce network overhead.

```swift
// These requests will be automatically batched
let tasks = pubkeys.map { pubkey in
    Task {
        try await ndk.profileManager.fetchProfile(for: pubkey)
    }
}

// All profiles fetched in a single subscription
let profiles = try await withTaskGroup(of: NDKUserProfile?.self) { group in
    for task in tasks {
        group.addTask { try await task.value }
    }
    
    var results: [NDKUserProfile?] = []
    for try await profile in group {
        results.append(profile)
    }
    return results
}
```

## Advanced Usage

### Direct Profile Manager Access

```swift
// Access the profile manager directly
let profileManager = ndk.profileManager

// Fetch with custom options
let profile = try await profileManager.fetchProfile(
    for: pubkey,
    forceRefresh: false
)

// Clear the cache
await profileManager.clearCache()

// Get cache statistics
let stats = await profileManager.getCacheStats()
print("Cache size: \(stats.size)")
```

### Integration with NDKUser

The `NDKUser` class provides convenient access to profile data:

```swift
let user = ndk.getUser("pubkey_hex")

// Properties are populated after fetching
_ = try await user.fetchProfile()

print(user.displayName ?? user.name ?? "Unknown")
print(user.nip05 ?? "No NIP-05")
```

### Handling Errors

```swift
do {
    let profile = try await user.fetchProfile()
    // Use profile
} catch NDKError.timeout {
    print("Request timed out")
} catch {
    print("Failed to fetch profile: \(error)")
}
```

## Best Practices

1. **Use Batching for Multiple Profiles**: When fetching multiple profiles, use `fetchProfiles()` or let the automatic batching handle it.

2. **Configure Cache Size Appropriately**: Set cache size based on your app's memory constraints and usage patterns.

3. **Handle Nil Profiles**: Not all users have profiles. Always handle the nil case gracefully.

4. **Respect Cache**: Don't force refresh unless necessary. The cache significantly reduces network load.

5. **Profile Updates**: Profiles change infrequently. The default 1-hour cache duration is usually appropriate.

## Example: Social Feed with Profiles

```swift
struct SocialFeedView {
    let ndk: NDK
    
    func loadFeedWithProfiles() async throws {
        // Fetch recent notes
        let filter = NDKFilter(
            kinds: [EventKind.textNote],
            limit: 20
        )
        
        let events = try await ndk.fetchEvents(filters: [filter])
        
        // Extract unique authors
        let authors = Set(events.map { $0.pubkey })
        
        // Fetch all profiles in one batch
        let profiles = try await ndk.profileManager.fetchProfiles(
            for: Array(authors)
        )
        
        // Display feed with profile information
        for event in events {
            let profile = profiles[event.pubkey]
            print("\(profile?.displayName ?? "Unknown"): \(event.content)")
        }
    }
}
```

## Performance Considerations

- **Memory Usage**: Each cached profile uses approximately 1-2KB of memory
- **Network Efficiency**: Batching can reduce subscriptions by 10-100x
- **Response Time**: Cached profiles return instantly; network fetches take 100-500ms

## Troubleshooting

### Profiles Not Updating

If profiles seem stale:
1. Check the `staleAfter` configuration
2. Use `forceRefresh: true` for critical updates
3. Clear the cache with `clearProfileCache()`

### High Memory Usage

If memory usage is high:
1. Reduce `cacheSize` in configuration
2. Clear cache periodically
3. Monitor cache statistics

### Slow Profile Loading

If profiles load slowly:
1. Ensure batching is enabled
2. Check relay connectivity
3. Consider pre-fetching profiles