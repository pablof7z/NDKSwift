# Critical Issue: NDKSubscription.events AsyncSequence Hanging

## Problem Description

Many tests in `NDKDataSourceTests.swift` are hanging indefinitely when using `for await event in dataSource.events`. Even with timeout protection added via `performAsyncTest`, the tests still hang because the async iteration itself never yields control back.

## Root Cause Analysis

The issue appears to be that `dataSource.events` (an AsyncSequence) is not properly connected to the cache event stream. When events are sent through `cache.processEvent()`, they are not being delivered to the async sequence consumers.

### Evidence:
1. Tests using `dataSource.first(timeout:)` work correctly
2. Tests using `dataSource.collect(timeout:)` complete but receive 0 events
3. Tests using raw `for await` loops hang indefinitely
4. Adding timeout wrappers doesn't help because the Task.value await never returns

## Affected Tests

- `testDataSourceReceivesEvents` - hangs on `await consumeTask.value`
- `testAsyncSequenceIteration` - same issue
- `testDataSourceFiltering` - same issue
- `testDataSourceWithTransform` - same issue
- `testComplexTransform` - same issue
- `testUpdateFilter` - infinite loop without break
- `testNetworkOnlyPolicy` - same issue
- `testRelayEventUpdate` - dual infinite loops
- Many others with similar patterns

## Temporary Workarounds Applied

1. Added `performAsyncTest(timeout: 5)` wrappers to prevent entire test suite from hanging
2. Added explicit `break` conditions in some loops
3. Used `task.cancel()` after assertions

However, these don't fix the core issue - the events are not being delivered.

## Recommended Fix

The implementation of `NDKSubscription.events` AsyncSequence needs to be investigated. Possible issues:

1. **Missing connection**: The AsyncSequence might not be properly subscribed to cache events
2. **Subscription ID mismatch**: The `subscriptionId` passed to `cache.processEvent()` might not match what the subscription expects
3. **Filter mismatch**: Events might be filtered out before reaching the AsyncSequence
4. **Missing relay connection**: The test setup with empty relay URLs might prevent event delivery

## Impact

This is a **CRITICAL** issue because:
- It makes the subscription API unusable in its current form
- Tests cannot verify the core functionality
- Any application using this API would hang

## Next Steps

1. Debug the `NDKSubscription.events` implementation
2. Trace event flow from `cache.processEvent()` to AsyncSequence yield
3. Verify subscription manager is properly routing events
4. Consider if the test setup (no relays, memory cache) is valid

## Test Pattern to Avoid

```swift
// This pattern will hang:
for await event in dataSource.events {
    // Process event
}

// Use this instead for now:
let event = await dataSource.first(timeout: 1.0)
// or
let events = await dataSource.collect(timeout: 1.0)
```