# Optimistic Publishing & Offline Support

NDKSwift provides a sophisticated optimistic publishing system that ensures your Nostr applications remain responsive even when offline or experiencing connectivity issues. This guide explains how it works and how to use it effectively.

## Overview

Optimistic publishing allows events to:
- Appear immediately in local subscriptions (instant UI feedback)
- Be automatically retried when connectivity is restored
- Track confirmation states across multiple relays
- Maintain consistency between UI and actual relay state

## How It Works

### 1. Event Publishing Flow

When you publish an event:

```swift
let event = NDKEvent(content: "Hello, Nostr!")
try await ndk.publish(event)
```

The following happens:

1. **Immediate Cache Storage**: Event is saved to cache with "unpublished" status
2. **Local Dispatch**: Event appears instantly in active subscriptions via `OptimisticEventSource`
3. **Relay Publishing**: Attempts to publish to relays in parallel (non-blocking)
4. **State Tracking**: Cache tracks which relays have confirmed the event

### 2. Offline Behavior

When offline or relays are unreachable:

- Events are cached with target relays marked as "unpublished"
- Local subscriptions still see the event immediately
- When relays reconnect, `publishQueuedEvents()` automatically retries
- Exponential backoff prevents overwhelming relays

### 3. Event Confirmation States

Events progress through three states:

```swift
// Check event confirmation state
let state = await cache.getEventConfirmationState(eventId: event.id)

switch state {
case .optimistic:
    // Event published locally but not confirmed by any relay
    print("Sending...")
    
case .partial(let confirmedRelays, let pendingRelays):
    // Event confirmed by some relays, pending on others
    print("Sent to \(confirmedRelays.count) relays, pending on \(pendingRelays.count)")
    
case .confirmed:
    // Event confirmed by all target relays
    print("Sent ✓")
}
```

## Configuration

### Enable/Disable Optimistic Publishing

```swift
// Configure optimistic publishing (enabled by default)
ndk.optimisticPublishingConfig = NDKOptimisticPublishingConfig(
    enabled: true,                    // Enable optimistic publishing
    cacheUnpublishedEvents: true,     // Store unpublished events for retry
    dispatchToSubscriptions: true     // Show in local subscriptions immediately
)

// Disable optimistic publishing entirely
ndk.optimisticPublishingConfig.enabled = false
```

### Subscription Options

Control whether subscriptions receive optimistic events:

```swift
// Default behavior - receives optimistic events
let subscription = ndk.subscribe(filters: [filter])

// Skip optimistic events (only show relay-confirmed events)
var options = NDKSubscriptionOptions()
options.skipOptimisticEvents = true
let strictSubscription = ndk.subscribe(filters: [filter], options: options)
```

### Event Source Tracking

Events include their source for UI differentiation:

```swift
for await event in subscription {
    switch event.source {
    case .optimistic:
        // Show with "sending" indicator
        showEvent(event, status: .sending)
        
    case .relay(let relay):
        // Show as confirmed from specific relay
        showEvent(event, status: .confirmed(relay))
        
    case .cache:
        // Retrieved from cache
        showEvent(event, status: .cached)
    }
}
```

## Retry Mechanisms

### Automatic Retry

When relays reconnect, unpublished events are automatically retried:

1. Relay connection established
2. `publishQueuedEvents()` called automatically
3. Unpublished events sent to newly connected relay
4. Cache updated with confirmation status

### Manual Retry

Manually retry unpublished events:

```swift
// Retry all unpublished events
try await ndk.retryUnpublishedEvents()

// Retry with age limit (only events from last hour)
try await ndk.retryUnpublishedEvents(
    maxAgeSeconds: 3600,  // 1 hour
    limit: 100            // Max 100 events
)

// Retry for specific relays
try await ndk.retryUnpublishedEvents(
    relayUrls: ["wss://relay.example.com"]
)
```

## Best Practices

### 1. UI Feedback

Show event state to users:

```swift
struct EventView: View {
    let event: NDKEvent
    @State private var confirmationState: EventConfirmationState?
    
    var body: some View {
        HStack {
            Text(event.content)
            Spacer()
            
            // Show confirmation status
            switch confirmationState {
            case .optimistic:
                ProgressView()
                    .scaleEffect(0.8)
            case .partial(let confirmed, _):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.orange)
                    .help("Sent to \(confirmed.count) relays")
            case .confirmed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case nil:
                EmptyView()
            }
        }
        .task {
            // Monitor confirmation state
            confirmationState = await cache.getEventConfirmationState(eventId: event.id)
        }
    }
}
```

### 2. Handle Offline Scenarios

```swift
// Check relay connectivity before critical operations
let connectedRelays = await ndk.pool.connectedRelays()
if connectedRelays.isEmpty {
    // Warn user about offline state
    showOfflineWarning()
    
    // Event will still be published optimistically
    try await ndk.publish(event)
    
    // Inform user about retry behavior
    showMessage("Your post will be sent when connection is restored")
}
```

### 3. Clean Up Old Unpublished Events

```swift
// Remove unpublished events older than 1 day
try await cache.cleanupUnpublishedEvents(olderThan: 86400)

// Or configure automatic cleanup
ndk.optimisticPublishingConfig.unpublishedEventMaxAge = 3600 // 1 hour
```

### 4. Monitor Relay Health

```swift
// Monitor which relays have confirmed an event
let status = await cache.getEventPublishStatus(eventId: event.id)
for (relay, isPublished) in status {
    if !isPublished {
        print("Event pending on: \(relay.url)")
    }
}
```

## Advanced Usage

### Custom Retry Logic

Implement custom retry strategies:

```swift
// Retry with custom logic
func retryFailedEvents() async throws {
    let unpublished = try await cache.getUnpublishedEvents(limit: 100)
    
    for event in unpublished {
        // Check event age
        let age = Date().timeIntervalSince1970 - TimeInterval(event.createdAt)
        
        // Skip old events
        if age > 3600 { continue }
        
        // Retry with specific relays based on event type
        let targetRelays = selectRelaysForEvent(event)
        try await ndk.publish(event, to: targetRelays)
    }
}
```

### Optimistic Event Filtering

Filter optimistic events in queries:

```swift
// Fetch only confirmed events
let confirmedEvents = try await ndk.fetchEvents(
    filter,
    options: NDKSubscriptionOptions(skipOptimisticEvents: true)
)

// Include optimistic events in search
let allEvents = try await ndk.fetchEvents(
    filter,
    options: NDKSubscriptionOptions(skipOptimisticEvents: false)
)
```

## Technical Details

### OptimisticEventSource

A special relay implementation that:
- Always appears "connected"
- Immediately accepts all events
- Dispatches events to local subscriptions
- Never actually sends events to network

### Cache Integration

Both SQLite and in-memory caches support:
- Tracking unpublished events with target relays
- Recording confirmation timestamps
- Querying by publication status
- Automatic cleanup of old events

### Thread Safety

All optimistic publishing operations are thread-safe:
- Event dispatch uses actors for concurrency
- Cache operations are atomic
- State tracking prevents race conditions

## Troubleshooting

### Events Not Appearing in Subscriptions

1. Check optimistic publishing is enabled:
   ```swift
   print(ndk.optimisticPublishingConfig.enabled) // Should be true
   ```

2. Verify subscription allows optimistic events:
   ```swift
   print(subscription.options.skipOptimisticEvents) // Should be false
   ```

### Events Not Retrying

1. Check relay reconnection:
   ```swift
   // Monitor relay connections
   for await connectionState in relay.connectionState {
       print("Relay \(relay.url): \(connectionState)")
   }
   ```

2. Manually trigger retry:
   ```swift
   try await ndk.retryUnpublishedEvents()
   ```

### Performance Considerations

- Optimistic events add minimal overhead
- Cache queries are optimized with indexes
- Retry operations batch events efficiently
- Old events are automatically cleaned up

## Summary

NDKSwift's optimistic publishing ensures your Nostr applications remain responsive regardless of network conditions. Events appear instantly in the UI, are automatically retried when connectivity is restored, and provide detailed confirmation tracking for user feedback. This creates a seamless experience that users expect from modern applications.