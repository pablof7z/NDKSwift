# Outbox Model Caching Strategy

## Overview

The outbox model in NDKSwift determines which relays to query for a given author's events. Instead of caching low-level query results (like "did we find a 10002 event"), we cache the **computed relay preferences** for each pubkey.

## The Problem

Without caching, the outbox resolver would:
1. Query for kind:10002 (relay list) for every author
2. Parse the relay list
3. Compute read/write preferences
4. Repeat this for EVERY data request involving that author

This creates unnecessary network traffic and computation, especially when relay lists change infrequently.

## The Solution: Result-Level Caching

Cache the **computed relay preferences**, not the raw queries:

```swift
struct RelayPreferences {
    let writeRelays: [RelayURL]
    let readRelays: [RelayURL] 
    let computedAt: Date
    let source: RelayListSource  // Where we got this info
}

enum RelayListSource {
    case explicit(eventId: String)  // From kind:10002
    case implicit                   // Inferred from posting history
    case default                    // Fallback relays
}
```

## Cache Implementation

```swift
actor OutboxCache {
    private var cache: [Pubkey: RelayPreferences] = [:]
    private let defaultMaxAge: TimeInterval = 3600  // 1 hour default
    
    func getRelayPreferences(
        for pubkey: Pubkey,
        maxAge: TimeInterval? = nil
    ) async -> RelayPreferences? {
        guard let cached = cache[pubkey] else { return nil }
        
        let age = Date().timeIntervalSince(cached.computedAt)
        let effectiveMaxAge = maxAge ?? defaultMaxAge
        
        if age > effectiveMaxAge {
            return nil  // Too old, need refresh
        }
        
        return cached
    }
    
    func setRelayPreferences(
        for pubkey: Pubkey,
        preferences: RelayPreferences
    ) async {
        cache[pubkey] = preferences
    }
}
```

## Integration with Outbox Resolver

```swift
extension NDKOutboxResolver {
    func relaysFor(pubkey: Pubkey, maxAge: TimeInterval = 3600) async -> [RelayURL] {
        // 1. Check cache first
        if let cached = await cache.getRelayPreferences(for: pubkey, maxAge: maxAge) {
            return cached.writeRelays
        }
        
        // 2. Not in cache or too old - fetch kind:10002
        let dataSource = CoreDataSource(
            filter: NDKFilter(authors: [pubkey], kinds: [10002]),
            maxAge: maxAge  // Use same maxAge for consistency
        )
        
        let relayListEvent = await dataSource.first()
        
        // 3. Compute preferences
        let preferences: RelayPreferences
        if let event = relayListEvent {
            preferences = parseRelayList(from: event)
        } else {
            // No explicit relay list - use defaults or infer
            preferences = RelayPreferences(
                writeRelays: defaultRelays,
                readRelays: defaultRelays,
                computedAt: Date(),
                source: .default
            )
        }
        
        // 4. Cache the result
        await cache.setRelayPreferences(for: pubkey, preferences: preferences)
        
        return preferences.writeRelays
    }
}
```

## Key Benefits

1. **Semantic Caching**: We cache what matters (relay preferences), not raw data
2. **Efficient Memory**: One entry per pubkey, not per query combination
3. **Smart Expiration**: Can tune maxAge based on use case
4. **Fallback Handling**: Gracefully handles missing relay lists

## Special Considerations

### Negative Results
When a user has no relay list, we cache the **default relay assignment** with appropriate source tracking. This prevents repeated queries for users who haven't published relay preferences.

### Cache Invalidation
The cache respects maxAge, but could also support explicit invalidation:
- When user publishes new relay list
- When switching accounts
- On app foreground after extended background time

### Memory Management
The cache should implement LRU eviction or similar to prevent unbounded growth:
```swift
private let maxCacheSize = 10_000  // Limit to 10k pubkeys
```

## Usage Examples

```swift
// In a feed view - can tolerate older relay info
let relays = await outboxResolver.relaysFor(
    pubkey: authorPubkey,
    maxAge: 3600  // 1 hour old is fine
)

// When viewing a specific profile - want fresh info
let relays = await outboxResolver.relaysFor(
    pubkey: profilePubkey,
    maxAge: 300  // 5 minutes max
)

// For wallet operations - need very fresh info
let relays = await outboxResolver.relaysFor(
    pubkey: walletPubkey,
    maxAge: 60  // 1 minute max
)
```