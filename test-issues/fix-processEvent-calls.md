# Fixing processEvent calls in NDKDataSourceTests

## Pattern to Replace

The tests are using:
```swift
try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")
```

This should be replaced with:
```swift
await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
```

## Tests Fixed So Far
1. ✅ testDataSourceCreation - Fixed isLoading assertion
2. ✅ testDataSourceReceivesEvents - Fixed to use handleRelayUpdate
3. ✅ testAsyncSequenceIteration - Fixed to use handleRelayUpdate

## Remaining Tests to Fix
- testDataSourceFiltering
- testEOSEHandling (already uses handleRelayUpdate for EOSE)
- testCloseOnEose (mixed approach)
- testCollectWithTimeout
- testFirstWithTimeout
- testMultipleDataSources
- testCacheOnlyPolicy
- testDataSourceWithTransform
- testTransformReturningNil
- testComplexTransform
- testUpdateFilter
- testUpdateFilterClearsData
- testRefresh
- testEventDeduplication
- testNetworkOnlyPolicy
- testRelayEventUpdate (already uses handleRelayUpdate)
- testEmptyFilter
- testLargeEventBatch
- testDataSourceCleanup
- testConcurrentEventProcessing

## Notes
- Some tests use handleRelayUpdate for EOSE but processEvent for events
- The handleRelayUpdate approach simulates events coming from relays more accurately
- This fixes the hanging issue documented in CRITICAL_TEST_ISSUES.md