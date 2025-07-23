# Session Data Management Proposals for NDKSwift

## Problem Statement

Apps need to:
1. Know when essential data (follow list, web-of-trust) is ready
2. Observe when this data changes
3. Have filters automatically update when dependencies change
4. Minimize re-downloading events when follows change

## Proposal 1: Session Data Provider Pattern

```swift
enum SessionDataRequirement {
    case followList
    case webOfTrust(depth: Int = 2)
    case muteList
    case relayList
    case custom(filter: NDKFilter)
}

@Observable
class NDKSessionDataManager {
    var followListState: DataState<Set<String>> = .loading
    var webOfTrustState: DataState<WebOfTrust> = .loading
    
    enum DataState<T> {
        case loading
        case ready(T, fromCache: Bool)
        case updating(current: T, changes: T)
        case error(Error)
    }
}
```

## Proposal 2: Reactive Filter Builder

```swift
struct ReactiveFilter {
    enum Dependency {
        case followList
        case webOfTrust(depth: Int)
        case dynamic(keyPath: KeyPath<NDKSession, any Collection>)
    }
    
    let dependencies: [Dependency]
    let builder: (NDKSession) -> NDKFilter
}

// Usage
let feedFilter = ReactiveFilter(
    dependencies: [.followList],
    builder: { session in
        NDKFilter(kinds: [.textNote], authors: Array(session.followList))
    }
)
```

## Proposal 3: Session Lifecycle with Data Preloading

```swift
struct NDKSessionConfiguration {
    let dataRequirements: Set<SessionData>
    let preloadStrategy: PreloadStrategy
    
    enum PreloadStrategy {
        case blocking  // Wait for all data
        case progressive  // Use cache, update in background
        case lazy  // Load on demand
    }
}
```

## Recommended: Hybrid Approach

Combine Session Data Provider with Reactive Filters for:
- Clear data requirements declaration
- Observable states for UI
- Automatic subscription management
- Efficient bandwidth usage

## Key Innovation: Smart Subscription Swapping

When follow list changes:
1. Fetch new follow's recent posts in background
2. Wait for EOSE
3. Close old subscription
4. Open new subscription with small limit (e.g., 5)
5. Minimal gap prevents missing events

This makes filter updates transparent to the app developer.