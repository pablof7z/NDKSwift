# Subscription API Guide

## Overview

The enhanced subscription API in NDKSwift provides a simplified, intuitive interface for subscribing to Nostr events. Key improvements include auto-starting subscriptions, builder patterns, convenience methods, and better lifecycle management.

## Quick Start

### Auto-Starting Subscriptions

Subscriptions now start automatically when created with event handlers:

```swift
// Before (required manual start)
let subscription = ndk.subscribe(filters: [filter])
subscription.onEvent { event in
    print("Received: \(event.content)")
}
subscription.start() // Easy to forget!

// After (auto-starts)
let subscription = ndk.subscribe(filter: filter) { event in
    print("Received: \(event.content)")
}
```

### Fetching Events

For one-time event fetching with automatic cleanup:

```swift
// Fetch all matching events (auto-closes on EOSE)
let events = try await ndk.fetch(filter, timeout: 5.0)

// Fetch from multiple filters
let filters = [
    NDKFilter(kinds: [1], authors: ["pubkey1"]),
    NDKFilter(kinds: [7], limit: 10)
]
let events = try await ndk.fetch(filters)
```

### Streaming Events

For continuous event streams using async/await:

```swift
// Stream events as they arrive
for await event in ndk.stream(filter) {
    print("New event: \(event.content)")
}

// Or create a stream and iterate later
let stream = ndk.stream(filter)
Task {
    for await event in stream {
        updateUI(with: event)
    }
}
```

## Builder Pattern

Create complex subscriptions fluently:

```swift
let subscription = ndk.subscription()
    .kinds([1, 7])                    // Text notes and reactions
    .authors(["pubkey1", "pubkey2"])  // From specific users
    .since(.now - 3600)               // Last hour
    .limit(100)                       // Max 100 events
    .hashtags(["nostr", "bitcoin"])   // With specific hashtags
    .cacheStrategy(.cacheFirst)       // Check cache first
    .closeOnEose()                    // Close after initial batch
    .onEvent { event in
        print("Event: \(event.content)")
    }
    .onEose {
        print("Initial batch complete")
    }
    .onError { error in
        print("Error: \(error)")
    }
    .start()
```

### Builder Options

- **Filters**: `kinds()`, `authors()`, `since()`, `until()`, `limit()`, `hashtags()`
- **Options**: `cacheStrategy()`, `closeOnEose()`, `relays()`, `manualStart()`
- **Handlers**: `onEvent()`, `onEose()`, `onError()`

## Common Patterns

### Fetch Single Event

```swift
// Subscribe and close after one event
ndk.subscribeOnce(filter) { events in
    if let event = events.first {
        print("Got event: \(event.content)")
    }
}

// Or with custom limit
ndk.subscribeOnce(filter, limit: 5) { events in
    print("Got \(events.count) events")
}
```

### Profile Management

Convenient methods for profile operations:

```swift
// Fetch a single profile
if let profile = try await ndk.fetchProfile(pubkey) {
    print("Name: \(profile.name ?? "Unknown")")
}

// Fetch multiple profiles
let profiles = try await ndk.fetchProfiles(pubkeys)
for (pubkey, profile) in profiles {
    print("\(pubkey): \(profile.name ?? "Unknown")")
}

// Subscribe to profile updates
ndk.subscribeToProfile(pubkey) { profile in
    updateUserInterface(with: profile)
}
```

### Subscription Groups

Manage multiple subscriptions together:

```swift
let group = ndk.subscriptionGroup()

// Add subscriptions to the group
group.subscribe(filter1) { event in
    handleTextNote(event)
}

group.subscribe(filter2) { event in
    handleReaction(event)
}

// Close all at once
group.closeAll()
```

## Lifecycle Management

### Scoped Subscriptions

Subscriptions that automatically close when leaving scope:

```swift
// Subscription closes automatically after block
try await ndk.withSubscription(filter) { subscription in
    // Use subscription here
    let events = await collectEvents(from: subscription)
    return processEvents(events)
}
// Subscription is closed here

// Multiple subscriptions with auto-cleanup
try await ndk.withSubscriptions([filter1, filter2]) { subscriptions in
    // All subscriptions close when block exits
}
```

### Auto-Closing Subscriptions

Subscriptions that close when released:

```swift
class ViewModel {
    private var subscription: AutoClosingSubscription?
    
    func startListening() {
        subscription = ndk.autoSubscribe(filter: filter)
        subscription?.onEvent = { [weak self] event in
            self?.handleEvent(event)
        }
    }
    
    deinit {
        // Subscription automatically closes
    }
}
```

## Async/Await Support

### Event Sequences

Iterate over subscription events using async sequences:

```swift
let subscription = ndk.subscribe(filters: [filter])

for await event in subscription.events {
    // Process each event
    if shouldStop(event) {
        break // Stops iteration
    }
}
```

### Concurrent Operations

Fetch from multiple sources concurrently:

```swift
async let profiles = ndk.fetchProfiles(pubkeys)
async let events = ndk.fetch(filter)
async let metadata = ndk.fetch(metadataFilter)

let (profileData, eventData, metadataData) = await (profiles, events, metadata)
```

## Error Handling

The simplified API uses the unified error system:

```swift
do {
    let events = try await ndk.fetch(filter, timeout: 5.0)
    processEvents(events)
} catch NDKUnifiedError.network(.timeout) {
    print("Request timed out")
} catch NDKUnifiedError.network(.connectionFailed) {
    print("Connection failed")
} catch {
    print("Unexpected error: \(error)")
}
```

## Migration Guide

### From Manual Start

```swift
// Old way
let sub = ndk.subscribe(filters: [filter])
sub.onEvent { event in ... }
sub.start()

// New way
let sub = ndk.subscribe(filter: filter) { event in ... }
```

### From Callback to Async

```swift
// Old way
let sub = ndk.subscribe(filters: [filter])
sub.onEvent { event in
    events.append(event)
}
sub.onEOSE {
    processEvents(events)
}
sub.start()

// New way
let events = try await ndk.fetch(filter)
processEvents(events)
```

### From Manual Lifecycle

```swift
// Old way
class ViewModel {
    var subscription: NDKSubscription?
    
    func start() {
        subscription = ndk.subscribe(filters: [filter])
        subscription?.start()
    }
    
    func stop() {
        subscription?.close()
    }
}

// New way
class ViewModel {
    var subscription: AutoClosingSubscription?
    
    func start() {
        subscription = ndk.autoSubscribe(filter: filter)
    }
    // Auto-closes on deinit
}
```

## Best Practices

1. **Use fetch() for one-time queries**: Don't create persistent subscriptions for single queries
2. **Prefer async/await**: Use streams and fetch methods over callbacks when possible
3. **Group related subscriptions**: Use subscription groups for related functionality
4. **Set appropriate timeouts**: Always set timeouts for fetch operations
5. **Handle errors gracefully**: Use the unified error system for consistent error handling
6. **Clean up subscriptions**: Use scoped or auto-closing subscriptions to prevent leaks
7. **Use builder for complex queries**: The builder pattern is clearer for multi-parameter subscriptions

## Performance Tips

1. **Use limit**: Always set reasonable limits on subscriptions
2. **Filter at source**: Use specific filters rather than filtering in code
3. **Cache first**: Use `.cacheFirst` strategy for better performance
4. **Batch operations**: Fetch multiple profiles/events in single requests
5. **Close unused subscriptions**: Don't keep subscriptions open unnecessarily

## Examples

### Real-time Chat

```swift
// Subscribe to chat messages
let chatSub = ndk.subscription()
    .kinds([4]) // Encrypted DMs
    .since(.now)
    .onEvent { event in
        if let decrypted = decrypt(event) {
            displayMessage(decrypted)
        }
    }
    .start()
```

### Social Feed

```swift
// Fetch recent posts from follows
let follows = getFollowList()
let posts = try await ndk.fetch(
    NDKFilter(
        kinds: [1],
        authors: follows,
        since: .now - 86400, // Last 24 hours
        limit: 50
    )
)
displayFeed(posts.sorted { $0.createdAt > $1.createdAt })
```

### Notification Stream

```swift
// Stream notifications
Task {
    for await event in ndk.stream(notificationFilter) {
        if shouldNotify(event) {
            showNotification(for: event)
        }
    }
}
```

The simplified subscription API makes Nostr development more intuitive while maintaining the flexibility needed for advanced use cases.