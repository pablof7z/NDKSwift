# Optimistic Publishing in NDKSwift

## Overview

NDKSwift uses optimistic publishing by default for all events. This means that when you publish an event, it immediately appears in local subscriptions while being sent to relays in the background, providing instant UI feedback.

## How It Works

### Publishing Flow

When `NDK.publish()` is called:

1. **Cache Save**: Event is saved to the local cache
2. **Optimistic Dispatch**: Event is immediately dispatched to all matching local subscriptions
3. **Relay Publishing**: Event is sent to relays in the background
4. **Confirmation**: When relays accept the event, it's marked as confirmed in the cache

### Event Sources

Events can come from three sources:
- `.optimistic` - Locally published events (not yet confirmed by relays)
- `.relay(RelayProtocol)` - Events received from relays
- `.cache` - Events loaded from cache

### Subscription Options

While publishing is always optimistic, subscriptions can choose to filter out optimistic events:

```swift
// Default behavior - receives all events including optimistic ones
let subscription = ndk.subscribe(filters: [filter])

// Only receive relay-confirmed events
var options = NDKSubscriptionOptions()
options.skipOptimisticEvents = true
let strictSubscription = ndk.subscribe(filters: [filter], options: options)
```

## Benefits

1. **Instant Feedback**: Users see their posts immediately
2. **Better UX**: No waiting for network round trips
3. **Offline Support**: Events are queued when offline and sent when connection resumes
4. **Simplified Code**: No configuration needed - it just works

## Event Confirmation States

You can check if an event has been confirmed by relays:

```swift
let state = await cache.getEventConfirmationState(eventId: event.id)
switch state {
case .optimistic:
    // Event is pending relay confirmation
case .partial(let confirmed, let pending):
    // Event confirmed by some relays
case .confirmed:
    // Event fully confirmed
}
```

## Retry Logic

Failed publishes are automatically tracked and can be retried:

```swift
// Get unpublished events
let unpublished = try await cache.getUnpublishedEvents()

// Retry publishing
try await ndk.retryUnpublishedEvents()
```

## Notes

- Relay list events (kind 10002) are never published optimistically to avoid sync issues
- The system automatically deduplicates events when relay confirmations arrive
- Optimistic events have the same event ID as their confirmed counterparts