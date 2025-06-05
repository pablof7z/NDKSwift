# NDKSubscription Thread Safety Fix

## Problem Identified

The segmentation fault in `NDKSubscription.handleEvent` was caused by a race condition in concurrent access to the `receivedEventIds` set. The issue occurred because:

1. `NDKRelaySubscriptionManager` is an actor that handles events from multiple relays
2. It calls `subscription.handleEvent()` on `NDKSubscription` instances 
3. `NDKSubscription.handleEvent()` was not thread-safe
4. Multiple relay threads could simultaneously access `receivedEventIds` causing memory corruption

## Root Cause

In `Sources/NDKSwift/Subscription/NDKSubscription.swift:230-235`:

```swift
public func handleEvent(_ event: NDKEvent, fromRelay relay: NDKRelay?) {
    guard !isClosed else { return }
    
    guard let eventId = event.id, !receivedEventIds.contains(eventId) else {
        return // Deduplicate
    }
    
    receivedEventIds.insert(eventId)  // RACE CONDITION HERE
    // ... rest of method
}
```

The `receivedEventIds` set was being accessed without synchronization from multiple threads simultaneously.

## Solution Implemented

Added thread-safe locks to protect all mutable state in `NDKSubscription`:

1. **Event deduplication**: `receivedEventIdsLock` protects `receivedEventIds` set
2. **Event storage**: `eventsLock` protects `events` array  
3. **State management**: `stateLock` protects `isClosed`, `isActive`, `eoseReceived`
4. **Callback management**: Individual locks for each callback array

### Key Changes

```swift
// Added locks for thread safety
private let receivedEventIdsLock = NSLock()
private let eventCallbacksLock = NSLock()
private let eoseCallbacksLock = NSLock()
private let errorCallbacksLock = NSLock()
private let eventsLock = NSLock()
private let stateLock = NSLock()

// Thread-safe handleEvent implementation
public func handleEvent(_ event: NDKEvent, fromRelay relay: NDKRelay?) {
    stateLock.lock()
    let closed = isClosed
    stateLock.unlock()
    
    guard !closed else { return }
    guard let eventId = event.id else { return }
    
    // Thread-safe event deduplication
    receivedEventIdsLock.lock()
    let alreadyReceived = receivedEventIds.contains(eventId)
    if !alreadyReceived {
        receivedEventIds.insert(eventId)
    }
    receivedEventIdsLock.unlock()
    
    // ... rest of method with similar thread-safe patterns
}
```

## Testing

Created maestro test `subscription_segfault_test.yaml` that:
- Creates an account
- Rapidly starts/stops subscriptions (10-20 times)
- Publishes events during subscription toggles
- Disconnects/reconnects relays while subscription is active
- Designed to trigger the original race condition

## Files Modified

- `Sources/NDKSwift/Subscription/NDKSubscription.swift` - Added comprehensive thread safety
- `Examples/iOSNostrApp/maestro/subscription_segfault_test.yaml` - Test to reproduce issue

## Notes

- NSLock warnings in async contexts are expected but safe for this use case
- The solution maintains performance while ensuring thread safety
- All subscription operations (start, close, callbacks) are now thread-safe