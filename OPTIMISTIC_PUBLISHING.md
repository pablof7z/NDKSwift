# Optimistic Publishing Implementation

## Overview

NDKSwift now supports optimistic publishing, allowing events to be immediately dispatched to active subscriptions when published locally, providing instant UI feedback while the event is being sent to relays in the background.

## Key Features

### 1. Event Source Tracking
- **EventSource enum** tracks where events originated:
  - `.optimistic` - Locally published events
  - `.relay(RelayProtocol)` - Events from relays
  - `.cache` - Events loaded from cache

### 2. Event Confirmation States
- **EventConfirmationState enum** tracks confirmation status:
  - `.optimistic` - Event published locally but not yet confirmed
  - `.confirmed(fromRelay: String)` - Event confirmed by a relay

### 3. Optimistic Publishing Configuration
- **NDKOptimisticPublishingConfig** provides granular control:
  - `enabled: Bool` - Enable/disable optimistic publishing
  - `cacheUnpublishedEvents: Bool` - Cache events optimistically
  - `dispatchToSubscriptions: Bool` - Dispatch to subscriptions immediately

### 4. Subscription Options
- **NDKSubscriptionOptions.skipOptimisticEvents** allows subscriptions to opt-out of optimistic events

## Implementation Details

### Publishing Flow

When `NDK.publish()` is called with optimistic publishing enabled:

1. **Optimistic Cache Addition**: Event is cached with `.optimistic` state
2. **Optimistic Dispatch**: Event is immediately dispatched to matching subscriptions
3. **Regular Cache Save**: Event is saved normally to cache
4. **Relay Publishing**: Event is sent to relays (existing logic)
5. **Confirmation**: When relay responds with OK, event state is updated to `.confirmed`

### Subscription Processing

The `NDKSubscriptionManager` now handles events from different sources:

```swift
// Unified event processing
private func processEvent(_ event: NDKEvent, from source: EventSource) async {
    switch source {
    case .optimistic:
        // Always considered unique for immediate dispatch
        isUnique = true
    case .relay, .cache:
        // Normal deduplication logic
        isUnique = eventDeduplication[eventId] == nil
    }
    // ... dispatch to matching subscriptions
}
```

### Deduplication Strategy

The `SubscriptionStateActor` implements sophisticated deduplication:

```swift
func addEventIfNotSeen(_ event: NDKEvent, from source: EventSource) async -> Bool {
    switch source {
    case .optimistic:
        // Add if not already seen
        if eventStates[eventId] == nil {
            eventStates[eventId] = .optimistic
            events.append(event)
            return true
        }
        
    case .relay(let relay):
        // Check if upgrading from optimistic to confirmed
        if let existingState = eventStates[eventId] {
            if case .optimistic = existingState {
                eventStates[eventId] = .confirmed(fromRelay: relay.url)
                return false // Don't add to events again
            }
        }
    }
}
```

## Usage Examples

### Basic Usage

```swift
// Create NDK with optimistic publishing enabled (default)
let ndk = NDK(relayUrls: ["wss://relay.damus.io"])

// Create a subscription
let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])])

// Events will appear immediately in the subscription
for await event in subscription {
    print("Received event: \(event.content)")
    // UI can show "sending..." initially, then "sent" after confirmation
}

// Publish an event - appears in subscription immediately
let event = NDKEvent(content: "Hello Nostr!", kind: 1)
try await ndk.publish(event)
```

### Skip Optimistic Events

```swift
// Create subscription that only receives confirmed events
var options = NDKSubscriptionOptions()
options.skipOptimisticEvents = true

let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])], options: options)
```

### Disable Optimistic Publishing

```swift
// Disable optimistic publishing globally
ndk.optimisticPublishingConfig = .disabled

// Or configure granularly
ndk.optimisticPublishingConfig = NDKOptimisticPublishingConfig(
    enabled: true,
    cacheUnpublishedEvents: false,  // Don't cache optimistically
    dispatchToSubscriptions: true   // But still dispatch to subscriptions
)
```

### Check Event Confirmation State

```swift
// In cache implementations
let state = await cache.getEventConfirmationState(eventId: eventId)
switch state {
case .optimistic:
    // Show "sending..." indicator
case .confirmed(let relay):
    // Show "sent via \(relay)" indicator
case nil:
    // Event not found or no confirmation tracking
}
```

## Files Modified

### Core Types
- `Sources/NDKSwift/Core/Types.swift` - Added EventSource, EventConfirmationState, NDKOptimisticPublishingConfig

### NDK Core
- `Sources/NDKSwift/Core/NDK.swift` - Added optimistic publishing logic to publish() method and processOKMessage()

### Cache System
- `Sources/NDKSwift/Cache/NDKCache.swift` - Added optimistic publishing methods to protocol
- `Sources/NDKSwift/Cache/MemoryCache.swift` - Implemented optimistic publishing support

### Subscription System
- `Sources/NDKSwift/Subscription/NDKSubscriptionManager.swift` - Added processOptimisticEvent() method
- `Sources/NDKSwift/Subscription/NDKSubscription.swift` - Added unified event handling with EventSource

## Testing

- `Tests/NDKSwiftTests/OptimisticPublishingTests.swift` - Comprehensive tests for optimistic publishing
- `Examples/OptimisticPublishingDemo.swift` - Demo showing the feature in action

## Benefits

1. **Instant UI Feedback** - Events appear immediately in subscriptions
2. **Better UX** - No waiting for network round-trips
3. **Reliable** - Automatic deduplication prevents duplicate events
4. **Configurable** - Can be disabled or fine-tuned per use case
5. **Rich UI States** - Cache tracks confirmation states for status indicators

## Backwards Compatibility

The implementation maintains full backwards compatibility:
- Existing code works without changes
- Optimistic publishing is enabled by default but can be disabled
- Subscriptions receive events the same way (just potentially faster)
- Cache interface remains the same with optional optimistic methods

## Performance Impact

- Minimal overhead - only affects the publish path
- Events are processed once optimistically, then deduplicated when arriving from relays
- Memory usage slightly increased due to confirmation state tracking
- Network usage unchanged - same events sent to same relays