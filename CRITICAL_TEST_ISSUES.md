# Critical Test Suite Issues

## NDKDataSourceTests.swift - Major API Mismatch

### Problem
The test file `Tests/NDKSwiftTests/Unit/Subscription/NDKDataSourceTests.swift` contains approximately 25 test methods that are using a non-existent `processEvent` method on the `NDKCache` protocol. This is causing all these tests to hang indefinitely when run.

### Root Cause
The tests were written expecting the cache to have a method signature like:
```swift
func processEvent(_ event: NDKEvent, from: String, subscriptionId: String) async throws
```

However, the actual `NDKCache` protocol only has:
- `saveEvent(_ event: NDKEvent) async throws`
- `getEvent(id: String) async -> NDKEvent?`
- `queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent]`
- `deleteEvent(id: String) async throws`

### Impact
- All tests in `NDKDataSourceTests.swift` are currently non-functional
- Running `swift test --filter "NDKSubscriptionTests"` hangs indefinitely
- This affects approximately 25 test methods covering critical subscription functionality

### Required Fix
All test methods need to be rewritten to:
1. Use `cache.saveEvent(event)` to store events in cache
2. Use `ndk.internalSubscriptionManager.processEvent(event, subscriptionId: dataSource.subscriptionId, from: MockRelay(url: "..."))` to simulate events arriving from relays
3. Or potentially refactor to use a different testing approach that doesn't require simulating internal event processing

### Affected Test Methods
- `testDataSourceReceivesEvents`
- `testAsyncSequenceIteration`
- `testDataSourceFiltering`
- `testEOSEHandling`
- `testMultipleDataSources`
- `testDataSourceWithDifferentCachePolicies`
- `testDataSourceCancellation`
- `testDataSourceMemoryManagement`
- `testDataSourceWithComplexFilter`
- `testDataSourceEventOrdering`
- `testDataSourceReconnection`
- `testDataSourceWithTransformations`
- `testCacheFirstPolicy`
- `testNetworkOnlyPolicy`
- `testDataSourceErrorHandling`
- `testDataCollectionArray`
- `testDataCollectionUpdate`
- `testDataSourceBehaviorStream`
- `testFetchWithTimeout`
- `testFetchWithLimitAndEose`
- `testDataSourceDeduplication`
- `testConcurrentDataSources`
- `testDataSourceWithManyEvents`
- `testDataSourcePerformance`
- `testLargeFilterPerformance`

### Recommendation
This is a critical issue that requires a major refactor of the test suite. The tests should be updated incrementally, fixing one or two at a time and ensuring they pass before moving on to the next batch. Consider also:
1. Creating a test helper that properly simulates event arrival
2. Documenting the correct testing patterns for NDKSwift
3. Adding integration tests that test against real relay connections instead of mocking internal behavior