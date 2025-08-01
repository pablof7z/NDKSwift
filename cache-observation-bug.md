# Cache Observation Bug

## Issue
The `observeEvents` method with `includeExisting: false` is incorrectly returning existing events from the database.

## Expected Behavior
When `includeExisting: false`, the observer should only emit events that are saved AFTER the observation starts.

## Actual Behavior
The observer is emitting existing events that were already in the database before the observation started.

## Root Cause Analysis
Looking at the implementation in NDKSQLiteCache.swift, the issue appears to be with how GRDB ValueObservation works. When `includeExisting: false`, the code doesn't emit the initial query results, but GRDB's observation might still trigger with existing events on the first database change.

## Potential Fix
The observer needs to track which events were already in the database when it started and filter them out from subsequent emissions. This could be done by:

1. Recording the event IDs present at observation start
2. Filtering out these IDs from all future batches
3. Or using timestamps to only emit events created after observation start

## Test Failure Details
- Test: `testAsyncThrowingStream_IncludeExistingFlag`
- Expected: Only the newly saved "New event"
- Received: The 3 existing events ("Existing 1", "Existing 2", "Existing 3")

This is a critical bug that breaks the expected behavior of cache observation.