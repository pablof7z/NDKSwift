# NDKDataSourceTests Fix Summary

## Issue Fixed
The NDKDataSourceTests were using `cache.processEvent()` which is not part of the NDKCache protocol. While MemoryCache and SQLiteCache do implement this method, it only saves events to cache and doesn't deliver them to active subscriptions.

## Solution Applied
Replaced all `cache.processEvent()` calls with `dataSource.handleRelayUpdate()` which properly simulates events arriving from relays and delivers them to the subscription.

## Pattern Changes
```swift
// OLD (hanging):
try await cache.processEvent(event, from: "wss://test.relay", subscriptionId: "test")

// NEW (working):
await dataSource.handleRelayUpdate(.event(event, relay: "wss://test.relay"))
```

## Tests Fixed
- testDataSourceCreation - Fixed isLoading assertion
- testDataSourceReceivesEvents
- testAsyncSequenceIteration
- testDataSourceFiltering
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
- testRelayEventUpdate
- testEmptyFilter
- testLargeEventBatch
- testDataSourceCleanup
- testConcurrentEventProcessing

## Note for Other Tests
Other test files (ReactiveSubscriptionTests, etc.) use processEvent but with SQLiteCache which does implement it. These tests may work correctly if they're testing cache functionality directly rather than subscription delivery.