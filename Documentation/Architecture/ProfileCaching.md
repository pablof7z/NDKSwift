# Profile Manager Caching Strategy

## Overview

The profile manager in NDKSwift fetches and parses user metadata (kind:0 events). Instead of caching whether we found or didn't find a profile event, we cache the **parsed profile data** itself, including the absence of a profile.

## The Problem

Without proper caching, the profile manager would:
1. Query for kind:0 for every profile display
2. Parse the JSON metadata
3. Validate and transform the data
4. Repeat this even when showing the same profile multiple times

This is especially wasteful in feed views where the same authors appear repeatedly.

## The Solution: Semantic Profile Caching

Cache the **parsed profile object**, not the raw event:

```swift
enum CachedProfile {
    case profile(NDKUserProfile, fetchedAt: Date)
    case noProfile(checkedAt: Date)  // User has no profile
    case error(Error, occurredAt: Date)  // Parse/fetch error
}

struct NDKUserProfile {
    let pubkey: Pubkey
    let name: String?
    let displayName: String?
    let about: String?
    let picture: URL?
    let banner: URL?
    let nip05: String?
    let lud16: String?
    let website: URL?
    // Computed properties
    var hasLightningAddress: Bool { lud16 != nil }
}
```

## Cache Implementation

```swift
actor ProfileCache {
    private var cache: [Pubkey: CachedProfile] = [:]
    private var observers: [Pubkey: Set<ProfileObserver>] = [:]
    private let defaultMaxAge: TimeInterval = 3600  // 1 hour default
    
    func getProfile(
        for pubkey: Pubkey,
        maxAge: TimeInterval? = nil
    ) async -> NDKUserProfile? {
        guard let cached = cache[pubkey] else { return nil }
        
        let effectiveMaxAge = maxAge ?? defaultMaxAge
        
        switch cached {
        case .profile(let profile, let fetchedAt):
            if Date().timeIntervalSince(fetchedAt) <= effectiveMaxAge {
                return profile
            }
        case .noProfile(let checkedAt):
            if Date().timeIntervalSince(checkedAt) <= effectiveMaxAge {
                return nil  // Still fresh "no profile" result
            }
        case .error(_, let occurredAt):
            if Date().timeIntervalSince(occurredAt) <= effectiveMaxAge {
                return nil  // Don't retry errors too quickly
            }
        }
        
        return nil  // Cache miss or stale
    }
    
    func setProfile(for pubkey: Pubkey, profile: NDKUserProfile) async {
        cache[pubkey] = .profile(profile, fetchedAt: Date())
        await notifyObservers(pubkey: pubkey, profile: profile)
    }
    
    func setNoProfile(for pubkey: Pubkey) async {
        cache[pubkey] = .noProfile(checkedAt: Date())
        await notifyObservers(pubkey: pubkey, profile: nil)
    }
}
```

## Integration with Profile Manager

```swift
extension NDKProfileManager {
    func fetchProfile(
        for pubkey: Pubkey,
        maxAge: TimeInterval = 3600
    ) async -> NDKUserProfile? {
        // 1. Check cache first
        if let cached = await cache.getProfile(for: pubkey, maxAge: maxAge) {
            return cached
        }
        
        // 2. Not in cache or stale - fetch kind:0
        let dataSource = CoreDataSource(
            filter: NDKFilter(authors: [pubkey], kinds: [0], limit: 1),
            maxAge: 0  // Keep subscription open for profile updates
        )
        
        // 3. Get the most recent profile event
        guard let event = await dataSource.first() else {
            // No profile found
            await cache.setNoProfile(for: pubkey)
            return nil
        }
        
        // 4. Parse the profile
        do {
            let profile = try parseProfile(from: event)
            await cache.setProfile(for: pubkey, profile: profile)
            return profile
        } catch {
            await cache.setError(for: pubkey, error: error)
            return nil
        }
    }
    
    func observeProfile(
        for pubkey: Pubkey,
        maxAge: TimeInterval = 3600
    ) -> AsyncStream<NDKUserProfile?> {
        AsyncStream { continuation in
            Task {
                // 1. Add observer
                let observer = ProfileObserver(continuation: continuation)
                await cache.addObserver(observer, for: pubkey)
                
                // 2. Send current value if fresh
                if let profile = await cache.getProfile(for: pubkey, maxAge: maxAge) {
                    continuation.yield(profile)
                }
                
                // 3. Create reactive data source
                let dataSource = CoreDataSource(
                    filter: NDKFilter(authors: [pubkey], kinds: [0]),
                    maxAge: 0  // Keep open for updates
                )
                
                // 4. React to updates
                for await event in dataSource.events {
                    if let profile = try? parseProfile(from: event) {
                        await cache.setProfile(for: pubkey, profile: profile)
                        // Observers notified automatically
                    }
                }
            }
        }
    }
}
```

## Key Benefits

1. **Parsed Data Caching**: Cache the expensive JSON parsing, not just raw events
2. **Negative Result Caching**: Remember when users have no profile
3. **Error Caching**: Don't hammer relays after parse errors
4. **Reactive Updates**: Support both one-shot and continuous observation

## Special Considerations

### Memory Management

Profiles can contain image URLs and large text fields. Implement intelligent eviction:

```swift
extension ProfileCache {
    private let maxCacheSize = 5_000  // Limit total profiles
    private let maxLRUSize = 1_000   // Keep 1k most recent in fast cache
    
    func evictLeastRecentlyUsed() async {
        // Remove oldest entries when over limit
    }
}
```

### Freshness by Context

Different UI contexts need different freshness:

```swift
// Feed view - many profiles, older data acceptable
let profile = await profileManager.fetchProfile(
    for: authorPubkey,
    maxAge: 3600  // 1 hour
)

// Profile page - focused view, want fresh data
let profile = await profileManager.observeProfile(
    for: profilePubkey,
    maxAge: 60  // 1 minute
)

// Settings/edit - need real-time updates
let profileStream = await profileManager.observeProfile(
    for: ownPubkey,
    maxAge: 0  // Always fresh
)
```

### Placeholder Handling

When profile is missing or loading:

```swift
extension NDKUserProfile {
    static func placeholder(pubkey: Pubkey) -> NDKUserProfile {
        NDKUserProfile(
            pubkey: pubkey,
            name: nil,
            displayName: String(pubkey.prefix(8)) + "...",
            about: nil,
            picture: nil,
            // ... other fields nil
        )
    }
}
```

## Migration Path

The existing profile manager can be gradually migrated:
1. Add caching layer alongside existing code
2. Update UI components to use cached profiles
3. Remove old fetching logic once stable