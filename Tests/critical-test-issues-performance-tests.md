# Critical Test Issues: LargeSubscriptionPerformanceTests

## Problem Description

The `LargeSubscriptionPerformanceTests` file contains several performance tests that hang indefinitely because they wait for events that never arrive. The tests attempt to use a `queueEvents` method on `MockRelay` that doesn't exist in the current implementation.

## Root Cause

1. **Missing MockRelay Functionality**: The tests were written expecting `MockRelay` to have a `queueEvents` method that would simulate incoming events, but this method doesn't exist in the current implementation.

2. **Infinite Waiting**: The tests create subscriptions and then wait for events using `for await` loops. Since no events are ever delivered (because MockRelay can't queue them), the tests hang forever.

3. **No Timeout Protection**: While some tests have timeout tasks in TaskGroups, they don't properly cancel the main event collection task when the timeout expires.

## Affected Tests

- `testLargeEventStreamPerformance()` - Expects to process 10,000 events
- `testMultipleSubscriptionsPerformance()` - Creates 100 concurrent subscriptions
- `testMemoryEfficiencyWithLargeStream()` - Processes events in batches

## Current Solution

I've added `XCTSkip` to these tests with an explanation that they require MockRelay refactoring. This prevents them from hanging the test suite while clearly documenting why they're disabled.

## Recommended Refactor

To properly fix these tests, one of the following approaches should be taken:

### Option 1: Enhance MockRelay
Add the missing functionality to MockRelay:
```swift
extension MockRelay {
    func queueEvents(_ events: [NDKEvent]) async {
        // Implementation to deliver events to subscriptions
    }
}
```

### Option 2: Use Cache-Based Testing
Refactor the tests to use the cache to deliver events instead of relying on MockRelay:
```swift
// Instead of:
// await mockRelay.queueEvents(events)

// Use:
for event in events {
    await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
}
```

### Option 3: Create a Proper Test Harness
Build a proper test infrastructure that can simulate relay behavior without needing actual network connections.

## Impact

- These performance tests are important for ensuring NDKSwift can handle large-scale event processing
- Without them, performance regressions could go unnoticed
- The tests should be re-enabled once the underlying infrastructure is fixed

## Related Issues

- The `testFilterMatchingPerformance()` and `testCacheLookupPerformance()` tests work correctly because they don't depend on MockRelay event delivery
- Similar patterns might exist in other test files that haven't been discovered yet