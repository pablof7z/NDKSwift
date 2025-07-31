# NDKSwift Naming Alignment with ndk-core

## Overview

This document outlines a comprehensive plan to align NDKSwift's naming conventions with ndk-core (the reference TypeScript implementation of NDK). The goal is to make NDKSwift more intuitive for developers familiar with other Nostr Development Kits while maintaining Swift best practices.

## Background and Context

### Current Architecture Comparison

#### NDKSwift Architecture (Current)
NDKSwift has a three-layer subscription architecture:

1. **Public API Layer**
   - `NDKSubscription<T>`: The public-facing reactive data source that users interact with
   - Method: `ndk.subscribe()` creates subscriptions
   - Features: SwiftUI integration via `@Published`, `AsyncStream` for modern Swift concurrency

2. **Internal Coordination Layer**
   - `NDKSubscriptionCoordinator`: Manages subscription lifecycle and coordinates between layers
   - `NDKSubscriptionRequirement`: Handles deduplication and relay selection strategies
   - `NDKSubscriptionManager`: Manages all active data requirements

3. **Relay Communication Layer**
   - `NDKRelaySubscription`: Groups subscriptions with same fingerprint at relay level
   - `NDKRelaySubscriptionManager`: Manages subscriptions per relay

#### ndk-core Architecture
ndk-core has a simpler two-layer architecture:

1. **Public API Layer**
   - `NDKSubscription`: The public subscription object with EventEmitter pattern
   - Method: `ndk.subscribe()` creates subscriptions
   - Features: Traditional JavaScript callbacks via `.on()` methods

2. **Relay Communication Layer**
   - `NDKRelaySubscription`: Groups and manages subscriptions at relay level
   - `NDKRelaySubscriptionManager`: Manages subscriptions per relay

### The Problem

The current NDKSwift naming creates confusion for developers:

1. **Method Naming**: `observe()` vs standard Nostr convention `subscribe()`
2. **Type Naming**: `NDKSubscription` doesn't immediately convey it's a subscription
3. **Internal Naming**: `NDKSubscriptionCoordinator` is vague about its coordination role
4. **Conceptual Mismatch**: Developers expect `subscribe()` to return a `Subscription`

## Proposed Changes

### 1. Public API Changes

#### Method Rename: `observe()` → `subscribe()`

**Current:**
```swift
let dataSource = ndk.subscribe(filter: myFilter)
```

**Proposed:**
```swift
let subscription = ndk.subscribe(filter: myFilter)
```

**Rationale:**
- `subscribe()` is the standard Nostr terminology used across all clients
- Matches ndk-core, nostr-tools, and other implementations
- Makes code more portable between different Nostr SDKs

#### Class Rename: `NDKSubscription<T>` → `NDKSubscription<T>`

**Current:**
```swift
public final class NDKSubscription<T>: ObservableObject {
    @Published public private(set) var data: [T] = []
    public let events: AsyncStream<T>
    public let relayUpdates: AsyncStream<RelayUpdate>
}
```

**Proposed:**
```swift
public final class NDKSubscription<T>: ObservableObject {
    @Published public private(set) var data: [T] = []
    public let events: AsyncStream<T>
    public let relayUpdates: AsyncStream<RelayUpdate>
}
```

**Rationale:**
- Clear that this represents a Nostr subscription
- Maintains all reactive features (no functionality changes)
- Generic type `<T>` allows type-safe transforms (Swift advantage over TypeScript)

### 2. Internal Architecture Renames

#### Coordination Layer

| Current Name | Proposed Name | Rationale |
|-------------|---------------|-----------|
| `NDKSubscriptionCoordinator` | `NDKSubscriptionCoordinator` | Clarifies its role in coordinating between public API and relay layer |
| `NDKSubscriptionRequirement` | `NDKSubscriptionRequirement` | Shows clear relationship to subscriptions |
| `NDKSubscriptionManager` | `NDKSubscriptionManager` | Aligns with ndk-core's naming pattern |

#### Relay Layer

| Current Name | Proposed Name | Rationale |
|-------------|---------------|-----------|
| `NDKRelaySubscription` | `NDKRelaySubscription` | Direct equivalent to ndk-core's `NDKRelaySubscription` |

### 3. File Renames

```
Sources/NDKSwift/DataSource/
├── NDKSubscription.swift → NDKSubscription.swift
├── NDKSubscriptionOptions.swift → NDKSubscriptionOptions.swift
├── NDKSubscriptionRequirement.swift → NDKSubscriptionRequirement.swift
├── NDKSubscriptionManager.swift → NDKSubscriptionManager.swift
└── NDKSubscriptionCoordinator.swift → NDKSubscriptionCoordinator.swift

Sources/NDKSwift/Relay/
└── NDKRelaySubscription.swift → NDKRelaySubscription.swift
```

## Implementation Details

### What Changes Functionally?

**Nothing!** This is purely a naming refactor. All functionality remains identical:

- Still provides reactive `@Published` properties for SwiftUI
- Still offers `AsyncStream` for modern Swift concurrency
- Still handles automatic lifecycle management
- Still provides type-safe transforms via generics

### Swift-Specific Features We Keep

Despite aligning names with ndk-core, we maintain Swift best practices:

1. **Generic Types**: `NDKSubscription<T>` for type-safe transforms
2. **Property Wrappers**: `@Published` for SwiftUI integration
3. **Actor Isolation**: Thread-safe by design using Swift actors
4. **AsyncSequence**: Modern alternative to callbacks

### Example Code Comparison

#### Before (Current NDKSwift)
```swift
// Create subscription
let dataSource = ndk.subscribe(
    filter: NDKFilter(kinds: [1], limit: 20),
    maxAge: 300
)

// SwiftUI usage
struct ContentView: View {
    @ObservedObject var dataSource: NDKSubscription<NDKEvent>
    
    var body: some View {
        List(dataSource.data) { event in
            Text(event.content)
        }
    }
}

// Async iteration
for await event in dataSource.events {
    handleEvent(event)
}
```

#### After (Proposed)
```swift
// Create subscription
let subscription = ndk.subscribe(
    filter: NDKFilter(kinds: [1], limit: 20),
    maxAge: 300
)

// SwiftUI usage
struct ContentView: View {
    @ObservedObject var subscription: NDKSubscription<NDKEvent>
    
    var body: some View {
        List(subscription.data) { event in
            Text(event.content)
        }
    }
}

// Async iteration
for await event in subscription.events {
    handleEvent(event)
}
```

## Architectural Context for Implementation

### Key Classes and Their Roles

1. **NDKSubscription<T>** (formerly NDKSubscription)
   - Location: `Sources/NDKSwift/DataSource/NDKSubscription.swift`
   - Public-facing subscription object
   - Provides reactive data binding for SwiftUI
   - Manages event deduplication at the user level
   - Creates and manages its `NDKSubscriptionRequirementHandle`

2. **NDKSubscriptionCoordinator** (formerly NDKSubscriptionCoordinator)
   - Location: `Sources/NDKSwift/DataSource/NDKSubscriptionCoordinator.swift`
   - Coordinates between NDKSubscription and relay layer
   - Manages REQ/CLOSE message creation
   - Tracks which relays have active subscriptions
   - Handles fingerprint-based routing

3. **NDKSubscriptionRequirement** (formerly NDKSubscriptionRequirement)
   - Location: `Sources/NDKSwift/DataSource/NDKSubscriptionRequirement.swift`
   - Manages filter splitting for outbox model
   - Handles relay selection strategies
   - Performs event deduplication across observers
   - Manages EOSE tracking

4. **NDKSubscriptionManager** (formerly NDKSubscriptionManager)
   - Location: `Sources/NDKSwift/DataSource/NDKSubscriptionManager.swift`
   - Singleton manager for all active subscriptions
   - Handles temporal grouping of subscriptions
   - Manages subscription lifecycle

5. **NDKRelaySubscription** (formerly NDKRelaySubscription)
   - Location: `Sources/NDKSwift/Relay/NDKRelaySubscription.swift`
   - Groups subscriptions with same fingerprint per relay
   - Manages execution timing and delays
   - Handles filter merging for efficiency

### Subscription Flow

1. User calls `ndk.subscribe()` → creates `NDKSubscription<T>`
2. NDKSubscription registers with `NDKSubscriptionManager`
3. Manager creates/reuses `NDKSubscriptionRequirement` based on filters
4. Requirement creates `NDKSubscriptionCoordinator` for relay communication
5. Coordinator is added to appropriate `NDKRelaySubscription` groups
6. Events flow back: Relay → Coordinator → Requirement → Subscription → User

### Important Implementation Notes

1. **Search and Replace Carefully**: Many internal references need updating
2. **Test File Names**: Update test files to match new class names
3. **Documentation**: Update all code comments and documentation
4. **Examples**: Every example in the codebase needs updating
5. **Type Aliases**: Consider temporary type aliases if gradual migration needed

## Testing Strategy

1. **Before Starting**: Ensure all tests pass
2. **Incremental Renames**: Rename one component at a time
3. **Continuous Testing**: Run tests after each rename
4. **Integration Tests**: Pay special attention to integration tests
5. **Example Validation**: Ensure all examples compile and run

## Version Strategy

This is a breaking change requiring a major version bump:
- Current: 2.x.x
- After rename: 3.0.0

## Benefits of This Change

1. **Consistency**: Aligns with Nostr ecosystem conventions
2. **Discoverability**: Developers expect `subscribe()` method
3. **Clarity**: `NDKSubscription` clearly indicates its purpose
4. **Portability**: Code patterns transfer between different Nostr SDKs
5. **Learning Curve**: Reduced for developers coming from other Nostr libraries

## Risks and Mitigation

1. **Risk**: Breaking existing code
   - **Mitigation**: Major version bump clearly signals breaking changes

2. **Risk**: Missing internal references
   - **Mitigation**: Comprehensive search across codebase, strong test suite

3. **Risk**: Documentation inconsistency
   - **Mitigation**: Systematic review of all docs and examples

## Conclusion

This renaming brings NDKSwift in line with Nostr conventions while preserving all the Swift-specific advantages. The changes are purely cosmetic - no functionality is altered. The result is a more intuitive API that feels familiar to Nostr developers while remaining idiomatic Swift code.