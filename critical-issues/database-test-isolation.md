# Database Test Isolation Issue

## Problem Description

The SQLite cache reactive tests have a critical issue where database state is not properly isolated between tests. Even though each test:
1. Creates a new database with a unique UUID in setUp
2. Calls `cache.clear()` in tearDown

Events from one test are visible in subsequent tests when using reactive observation.

## Symptoms

- `testObserveEventsStreamUpdates` receives 3 events instead of the expected 2
- The extra event is from a previous test in the suite
- This only affects reactive observation tests, not regular query tests

## Root Cause Analysis

The issue appears to be related to how GRDB's reactive observation works:
1. GRDB might be caching observation state across database instances
2. The observation mechanism might not be properly cleaned up when a database is destroyed
3. There could be a race condition between test teardown and observation cleanup

## Attempted Solutions

1. **Clearing cache in tearDown** - Already implemented but insufficient
2. **Clearing cache at start of test** - Tried but still receives events from other tests
3. **Using unique database paths** - Already implemented with UUID

## Impact

- Makes it impossible to write reliable reactive observation tests
- Tests can fail intermittently depending on execution order
- Prevents testing of critical reactive features

## Proposed Solutions

### Short-term (Current approach)
- Disable problematic tests with DISABLED_ prefix
- Document the issue for future reference
- Focus on non-reactive cache tests

### Long-term Solutions

1. **Investigate GRDB observation cleanup**
   - Check if there's a way to force cleanup of all observations
   - Look for any global state in GRDB that persists between database instances

2. **Test isolation improvements**
   - Run reactive tests in separate test targets
   - Use separate processes for each test
   - Implement a delay between tests to allow cleanup

3. **Alternative testing approach**
   - Mock the database layer for reactive tests
   - Test reactive logic separately from database integration

## Code References

- Problematic test: Tests/NDKSwiftTests/Unit/Cache/NDKSQLiteCacheReactiveTests.swift:114
- Database creation: Tests/NDKSwiftTests/Unit/Cache/NDKSQLiteCacheReactiveTests.swift:14
- Observation implementation: Sources/NDKSwift/Cache/NDKSQLiteCache.swift (observeEvents methods)

## Next Steps

1. File an issue with GRDB about test isolation
2. Research best practices for testing reactive database code
3. Consider implementing a test-specific cache that better supports isolation