# Cache Observation Delivery Bug

## Issue
When creating subscriptions with cache policies (cacheOnly, cacheWithNetwork), the observation mechanism only delivers the first event from the cache, even when multiple matching events exist.

## Evidence
In CacheFirstTests:
- `testImmediateCacheHit`: Expects 5 events, receives only 1
- `testCacheOnlyPolicy`: Expects 4 events, receives only 1
- `testStaleCache`: Expects 2 events, receives only 1

## Root Cause Analysis
The issue appears to be in how the cache observation stream is being created or consumed. When a subscription starts observing cached events:

1. The cache correctly identifies all matching events (based on logs showing "Initial query found X events")
2. But the AsyncStream only yields the first event before stopping

This suggests either:
- The observation continuation is being completed prematurely
- There's a race condition in how events are yielded to the stream
- The filter matching logic is incorrectly filtering out subsequent events

## Impact
- Cache-based subscriptions are not reliable for retrieving multiple events
- Applications relying on cache-first strategies will miss data
- Tests cannot properly validate cache behavior

## Recommended Fix
This requires investigating:
1. NDKSQLiteCache.observeEvents implementation
2. How the AsyncStream continuation is managed
3. Whether there's proper iteration over all matching events

## Workaround
For tests, we could modify expectations to only expect 1 event, but this masks the underlying bug rather than fixing it.