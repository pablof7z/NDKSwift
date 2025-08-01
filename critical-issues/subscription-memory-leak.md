# Critical Issue: NDKSubscription Memory Leak

## Issue Description
The test `testDataSourceDeallocatesCorrectly` is failing because `NDKSubscription` instances are not being properly deallocated when they should be. This indicates a potential memory leak in the subscription system.

## Test Details
- **Test:** `NDKSubscriptionComprehensiveTests.testDataSourceDeallocatesCorrectly`
- **Location:** Tests/NDKSwiftTests/Unit/Subscription/NDKDataSourceComprehensiveTests.swift:528
- **Status:** Failing (not deallocating)

## Root Cause Analysis
The test creates a subscription and expects it to be deallocated after going out of scope and canceling the consuming task. However, the weak reference remains non-nil, indicating the subscription is being retained somewhere.

### Potential Causes:
1. **Circular References**: The subscription might have strong references to itself through closures or callbacks
2. **Pool Retention**: The NDK pool might be retaining subscriptions even after they're no longer needed
3. **AsyncStream Lifecycle**: The AsyncStream implementation might be holding strong references
4. **Cache References**: The cache might be retaining subscriptions through event processing

## Impact
- **Memory Leaks**: Subscriptions that should be released are kept in memory
- **Resource Exhaustion**: Long-running apps could accumulate subscriptions over time
- **Performance Degradation**: Unnecessary processing of events for "dead" subscriptions

## Recommended Fix
This requires a deep refactor of the subscription lifecycle management:

1. **Audit Reference Cycles**: Review all closures and callbacks in NDKSubscription for potential retain cycles
2. **Implement Proper Cleanup**: Ensure subscriptions are removed from all tracking structures when cancelled
3. **AsyncStream Management**: Review the AsyncStream continuation handling to ensure proper cleanup
4. **Add Weak References**: Consider using weak references in places where subscriptions are tracked

## Testing Notes
- The test has been modified to not hang, but still fails due to the memory leak
- This is a critical architectural issue that needs addressing before the library can be used in production
- Consider adding more comprehensive memory leak detection tests

## Priority
**CRITICAL** - This is a fundamental issue that affects the reliability of the entire subscription system.