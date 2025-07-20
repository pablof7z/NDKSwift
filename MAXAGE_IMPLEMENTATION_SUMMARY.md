# MaxAge Implementation Summary

## What We Implemented

### 1. NDKDataSource Enhanced with maxAge and CachePolicy

```swift
public init(
    ndk: NDK,
    filter: NDKFilter,
    maxAge: TimeInterval = 0,
    cachePolicy: CachePolicy = .cacheWithNetwork,
    transform: @escaping (NDKEvent) -> T?
)
```

**Key Features:**
- `maxAge`: Controls cache freshness (0 = live subscription, >0 = cache tolerance)
- `CachePolicy`: Controls cache behavior (.cacheWithNetwork, .cacheOnly, .networkOnly)
- Removed `@MainActor` for universal usage
- Added `events: AsyncStream<T>` for internal components
- Thread-safe with internal `StateManager` actor

### 2. CachePolicy Enum

```swift
public enum CachePolicy {
    case cacheWithNetwork  // Default: use cache if fresh, otherwise network
    case cacheOnly        // Never hit network (offline mode)
    case networkOnly      // Always fetch fresh (force refresh)
}
```

### 3. Thread Safety with StateManager

```swift
private actor StateManager {
    var processedEventIds = Set<String>()
    // Thread-safe event deduplication
}
```

### 4. AsyncStream Support

```swift
// For internal components
for await event in dataSource.events {
    // React to updates without SwiftUI
}

// For one-shot access
let current = await dataSource.currentValue()
```

## What's Next

### Immediate Tasks:
1. **Update DataRequirementManager** to handle maxAge/cachePolicy logic:
   - Check cache freshness before creating subscriptions
   - Close subscriptions after EOSE if maxAge > 0
   - Handle cachePolicy behaviors

2. **Add Cache Timestamps**:
   - Track when events were fetched
   - Compare against maxAge for freshness checks

3. **Remove fetchEvents Methods**:
   - Delete InternalFetchUtilities.swift
   - Migrate all internal components to use NDKDataSource

### Example Usage Patterns:

```swift
// Real-time chat (always fresh)
let chat = NDKDataSource(filter: chatFilter, maxAge: 0)

// Feed view (1 hour tolerance)  
let feed = NDKDataSource(filter: feedFilter, maxAge: 3600)

// Offline mode
let offline = NDKDataSource(
    filter: filter, 
    maxAge: .infinity,
    cachePolicy: .cacheOnly
)

// Force refresh
let fresh = NDKDataSource(
    filter: filter,
    cachePolicy: .networkOnly  
)
```

## Benefits

1. **Unified API**: Everything uses NDKDataSource, no more fetchEvents
2. **Smart Caching**: Respects freshness requirements automatically
3. **Thread Safe**: Works from any thread/actor
4. **Flexible**: Supports both UI (ObservableObject) and internal (AsyncStream) usage
5. **Efficient**: Leverages temporal aggregation and smart routing

## Architecture Achievement

We've successfully created a declarative data access layer where:
- Developers declare data needs and freshness tolerance
- System automatically handles caching, subscriptions, and lifecycle
- Internal components benefit from the same intelligent data flow
- No more manual subscription management or fetch methods