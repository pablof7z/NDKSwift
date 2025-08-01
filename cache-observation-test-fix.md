# Cache Observation Test Fix

## Issue Found
The `CacheObservationTests` were failing because they misunderstood how GRDB database observations work.

## Root Cause
GRDB's `ValueObservation` emits the complete current state of matching records after each database change, not just the delta/new records. This is the expected and correct behavior for database observations.

## What Was Happening
When saving 3 events one by one, the observation was emitting:
1. First save: 1 event (total received: 1)
2. Second save: 2 events (total received: 3)
3. Third save: 3 events (total received: 6)

The test was expecting only 3 events total, but was receiving 6 due to the cumulative nature of observations.

## Fix Applied
Updated the tests to:
1. Track unique event IDs using a Set instead of counting total events received
2. Count the number of observation emissions separately
3. Adjust assertions to match the actual behavior of database observations

## Lessons Learned
- Database observations typically emit the current state, not deltas
- When testing reactive database queries, track unique entities rather than counting emissions
- The cache implementation is working correctly; the tests had incorrect expectations

## No Refactoring Needed
The `NDKSQLiteCache.observeEvents()` implementation is correct and follows standard database observation patterns. No changes to the production code were necessary.