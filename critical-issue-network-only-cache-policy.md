# Critical Issue: NetworkOnly Cache Policy Not Working Correctly

## Issue Description

The `networkOnly` cache policy in `NDKSubscriptionRequirement` is not working as intended. When a subscription is created with `.networkOnly` cache policy, it still receives events from the cache observation, which violates the expected behavior.

## Root Cause

In `NDKSubscriptionRequirement.startProcessing()` (lines 75-96), the cache observation is always set up regardless of the cache policy:

```swift
func startProcessing() async {
    // Set up cache observation using the new AsyncThrowingStream
    Task { [weak self] in
        guard let self = self else { return }
        
        let eventStream = await self.cache.observeEvents(
            matching: self.filter,
            includeExisting: true
        )
        
        // ... process cache events ...
    }
    
    // Only set up network operations if we should fetch from network
    if shouldFetchFromNetwork {
        // ... network setup ...
    }
}
```

The cache observation should be conditional based on the cache policy.

## Impact

1. **Incorrect Behavior**: Applications using `.networkOnly` policy will still receive cached events, which may lead to:
   - Duplicate event processing
   - Stale data being displayed when fresh data is required
   - Incorrect application state

2. **Test Failures**: The `CacheFirstTests.testNetworkOnlyPolicy` test is failing because it expects no cached events for networkOnly policy.

3. **Performance**: Unnecessary cache observation for networkOnly subscriptions adds overhead.

## Proposed Fix

The `startProcessing()` method should check the cache policy before setting up cache observation:

```swift
func startProcessing() async {
    // Only set up cache observation if policy allows it
    if cachePolicy != .networkOnly {
        Task { [weak self] in
            guard let self = self else { return }
            
            let eventStream = await self.cache.observeEvents(
                matching: self.filter,
                includeExisting: true
            )
            
            // ... process cache events ...
        }
    }
    
    // Only set up network operations if we should fetch from network
    if shouldFetchFromNetwork {
        // ... network setup ...
    }
}
```

However, this requires passing the `cachePolicy` to `NDKSubscriptionRequirement`, which is not currently done.

## Alternative Solution

Another approach is to check the cache policy in `handleCacheEvent()` and ignore cache events for networkOnly policy:

```swift
private func handleCacheEvent(_ event: NDKEvent) async {
    // Skip cache events for networkOnly policy
    if cachePolicy == .networkOnly {
        return
    }
    
    // ... existing implementation ...
}
```

But this still has the overhead of observing the cache unnecessarily.

## Recommendation

This is a **HIGH PRIORITY** issue that affects core functionality. The proper fix requires:

1. Pass `cachePolicy` from `NDKSubscriptionManager` to `NDKSubscriptionRequirement`
2. Conditionally set up cache observation based on the policy
3. Update all related tests
4. Consider the interaction with reactive subscriptions where multiple requirements share the same filter

## Related Files

- `Sources/NDKSwift/DataSource/NDKSubscriptionRequirement.swift`
- `Sources/NDKSwift/DataSource/NDKSubscriptionManager.swift`
- `Tests/NDKSwiftTests/Unit/DataSource/CacheFirstTests.swift`