# Thread Safety Migration Guide

## Overview

NDKSwift is migrating from NSLock-based synchronization to Swift actors for improved thread safety and performance. This guide explains the changes and how to migrate your code.

## Why Actors?

The original `NDKSubscription` implementation used 7 different NSLocks to protect various pieces of state:
- `eoseReceivedLock` - EOSE tracking
- `receivedEventIdsLock` - Event deduplication  
- `eventCallbacksLock` - Event callbacks
- `eoseCallbacksLock` - EOSE callbacks
- `errorCallbacksLock` - Error callbacks
- `eventsLock` - Event array
- `stateLock` - Active/closed state

This approach had several issues:
1. **Complexity** - Manual lock/unlock management is error-prone
2. **Performance** - Lock contention under high load
3. **Deadlock Risk** - Multiple locks increase deadlock potential
4. **Maintenance** - Hard to reason about thread safety

## Actor-Based Solution

The refactored implementation consolidates all synchronization into 2 actors:

### SubscriptionStateManager Actor
Manages all mutable state:
- Relay tracking
- Active/closed/EOSE flags
- Event storage and deduplication
- EOSE tracking per relay

### CallbackManager Actor  
Manages all callbacks:
- Event, EOSE, and error callbacks
- Safe registration and execution
- Cleanup operations

## Migration Steps

### 1. Update Property Access

Old synchronous properties are now async:

```swift
// Before
if subscription.isActive {
    print("Events: \(subscription.events.count)")
}

// After  
if await subscription.isActive {
    let events = await subscription.events
    print("Events: \(events.count)")
}
```

### 2. Update Event Processing

Event processing methods are now async:

```swift
// Before
subscription.processEvent(event, from: relay)

// After
await subscription.processEvent(event, from: relay)
```

### 3. Update Callbacks

Callback registration remains synchronous for compatibility:

```swift
// Still works
subscription.onEvent { event in
    print("Received: \(event.content)")
}

// But internally uses Tasks
```

### 4. Update Close/Stop Methods

```swift
// Before
subscription.close()

// After
await subscription.close()

// Or for compatibility
subscription.stop() // Uses Task internally
```

## Performance Improvements

The actor-based implementation provides:
- **Better Concurrency** - No lock contention
- **Improved Throughput** - Actors can process multiple operations
- **Reduced Memory** - Consolidated state management
- **Type Safety** - Compiler-enforced thread safety

## Testing

The refactored implementation includes comprehensive tests demonstrating:
- Thread safety under high concurrent load
- Proper state management
- Memory cleanup
- Backward compatibility

## Gradual Migration

You can migrate gradually:
1. Start with new subscriptions using `NDKSubscriptionRefactored`
2. Update existing code incrementally
3. Eventually deprecate the old implementation

## Example Migration

### Before
```swift
class MySubscriptionHandler {
    func handleSubscription() {
        let sub = ndk.subscribe(filters: [filter])
        
        sub.onEvent { event in
            if sub.isActive {
                self.processEvent(event)
            }
        }
        
        sub.start()
        
        // Later...
        sub.close()
    }
}
```

### After
```swift  
class MySubscriptionHandler {
    func handleSubscription() async {
        let sub = NDKSubscriptionRefactored(filters: [filter], ndk: ndk)
        
        sub.onEvent { event in
            Task {
                if await sub.isActive {
                    self.processEvent(event)
                }
            }
        }
        
        sub.start()
        
        // Later...
        await sub.close()
    }
}
```

## Next Steps

1. Test `NDKSubscriptionRefactored` in your application
2. Report any issues or incompatibilities
3. Gradually migrate existing code
4. Benefit from improved thread safety and performance