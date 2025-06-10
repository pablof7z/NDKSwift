# Subscription API Guide

## Overview

NDKSwift provides a modern, Swift-first API for working with Nostr subscriptions. The API uses Swift's async/await and AsyncSequence patterns for a clean, intuitive interface that aligns with Swift best practices.

## Core Concepts

### One-Shot Fetches vs Continuous Subscriptions

NDKSwift distinguishes between two primary use cases:

1. **One-shot fetches**: When you need data once (e.g., loading a user's profile)
2. **Continuous subscriptions**: When you want ongoing updates (e.g., watching a feed)

### API Design Philosophy

- **Fetch = Async Function**: Returns data once and completes
- **Subscribe = AsyncSequence**: Continuously yields events as they arrive

## One-Shot Fetch Methods

### Fetch Events

```swift
// Fetch events matching a filter
let events = try await ndk.fetchEvents(
    NDKFilter(kinds: [1], limit: 20)
)

// Fetch with specific relays
let events = try await ndk.fetchEvents(
    filter,
    relays: specificRelays,
    cacheStrategy: .cacheFirst
)
```

### Fetch Single Event

```swift
// Fetch by event ID (hex or bech32)
let event = try await ndk.fetchEvent("eventId...")

// Fetch first event matching filter
let event = try await ndk.fetchEvent(
    NDKFilter(authors: ["pubkey"], kinds: [0])
)
```

### Fetch Profile

```swift
// Fetch a user's profile metadata
if let profile = try await ndk.fetchProfile("pubkey...") {
    print("Name: \(profile.name ?? "Unknown")")
    print("About: \(profile.about ?? "")")
}
```

```swift
## Continuous Subscriptions

### Basic Subscription

```swift
// Create a subscription
let subscription = ndk.subscribe(
    filters: [NDKFilter(kinds: [1])],
    options: NDKSubscriptionOptions()
)

// Iterate over events as they arrive
for await event in subscription {
    print("New event: \(event.content)")
}
```

### Handling All Updates

For cases where you need to handle events, EOSE, and errors:

```swift
let subscription = ndk.subscribe(filters: [filter])

for await update in subscription.updates {
    switch update {
    case .event(let event):
        // Handle new event
        handleEvent(event)
    case .eose:
        // End of stored events reached
        print("All historical events loaded")
    case .error(let error):
        // Handle error
        print("Error: \(error)")
    }
}
```

### Auto-Starting Subscriptions

Subscriptions automatically start when you begin iterating:

```swift
// No need to call start() - iteration triggers it
for await event in ndk.subscribe(filters: [filter]) {
    // Process events
}
```
```

## Subscription Options

```swift
var options = NDKSubscriptionOptions()
options.closeOnEose = true        // Close after historical events
options.cacheStrategy = .cacheFirst // Check cache before relays
options.limit = 100               // Maximum events to receive
options.timeout = 30.0            // Timeout in seconds
options.relays = specificRelays   // Use specific relays

let subscription = ndk.subscribe(filters: [filter], options: options)
```

## Cache Strategies

- `.cacheFirst`: Check cache first, then query relays (default)
- `.cacheOnly`: Only check cache, don't query relays
- `.relayOnly`: Skip cache, only query relays
- `.parallel`: Check cache and relays simultaneously

## Real-World Examples

### Loading a Feed

```swift
// Initial load with fetch
let recentPosts = try await ndk.fetchEvents(
    NDKFilter(kinds: [1], limit: 50),
    cacheStrategy: .cacheFirst
)
displayPosts(recentPosts)

// Then subscribe for new posts
let subscription = ndk.subscribe(
    filters: [NDKFilter(kinds: [1], since: .now)]
)

for await newPost in subscription {
    prependToFeed(newPost)
}
```

### User Profile with Updates

```swift
// Load current profile
if let profile = try await ndk.fetchProfile(pubkey) {
    updateUI(with: profile)
}

// Watch for profile updates
let subscription = ndk.subscribe(
    filters: [NDKFilter(authors: [pubkey], kinds: [0])]
)

for await update in subscription.updates {
    if case .event(let event) = update {
        if let profileData = event.content.data(using: .utf8),
           let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) {
            updateUI(with: profile)
        }
    }
}
```

### Direct Messages

```swift
let dmFilter = NDKFilter(kinds: [4], "#p": [myPubkey])
let subscription = ndk.subscribe(filters: [dmFilter])

for await dm in subscription {
    // Decrypt and display message
    if let decrypted = try? decryptDM(dm) {
        showMessage(decrypted)
    }
}
```

## Migration from Callbacks

### Old Callback Pattern (Deprecated)

```swift
// ⚠️ Deprecated - avoid this pattern
subscription.onEvent { event in
    handleEvent(event)
}
subscription.onEOSE {
    print("EOSE")
}
```

### New AsyncSequence Pattern

```swift
// ✅ Recommended approach
for await event in subscription {
    handleEvent(event)
}

// Or with all updates:
for await update in subscription.updates {
    switch update {
    case .event(let event): handleEvent(event)
    case .eose: print("EOSE")
    case .error(let error): handleError(error)
    }
}
```

## Task Management

### Cancellation

```swift
// Store the task
let subscriptionTask = Task {
    for await event in subscription {
        processEvent(event)
    }
}

// Cancel when done
subscriptionTask.cancel()
```

### Subscription Groups

```swift
await ndk.withSubscriptionGroup { group in
    let sub1 = group.subscribe(filter1)
    let sub2 = group.subscribe(filter2)
    
    // Process subscriptions
    // All automatically close when block exits
}
```

## Best Practices

1. **Use fetch for one-time data needs**
   - User profiles
   - Specific events by ID
   - Historical data queries

2. **Use subscribe for ongoing updates**
   - Live feeds
   - Real-time notifications
   - Chat messages

3. **Always handle errors**
   ```swift
   do {
       let events = try await ndk.fetchEvents(filter)
   } catch {
       // Handle network errors, timeouts, etc.
   }
   ```

4. **Consider cache strategies**
   - Use `.cacheFirst` for better performance
   - Use `.relayOnly` for absolute freshness
   - Use `.cacheOnly` for offline support

5. **Manage subscription lifecycle**
   - Subscriptions auto-close on deinit
   - Explicitly cancel long-running subscriptions
   - Use subscription groups for coordinated cleanup

## Performance Tips

1. **Limit concurrent subscriptions**
   - Merge compatible filters when possible
   - Close subscriptions when not needed

2. **Use appropriate limits**
   ```swift
   options.limit = 50 // Don't fetch more than needed
   ```

3. **Filter efficiently**
   - Be specific with filters to reduce data transfer
   - Use time ranges (`since`/`until`) when appropriate

4. **Leverage caching**
   - Cache-first strategy reduces network usage
   - Parallel strategy provides best of both worlds

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