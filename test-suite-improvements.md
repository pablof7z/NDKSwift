# Test Suite Improvements and Issues

## Current State Analysis (Updated 2025-08-01)

After comprehensive analysis of the NDKSwift test suite:

### Working Tests
- `Bech32Tests` - All 11 tests passing ✅
- `NDKEventBuilderTests` - All 15 tests passing ✅
- `EventIDOptimizationIntegrationTest` - Passing ✅
- `SubscriptionGroupingIntegrationTests` - All 7 tests passing ✅
- `SQLiteCacheFilteringConsistencyTests` - All 3 tests passing ✅
- `CacheObservationTests` - Basic tests passing ✅
- `NDKPoolTests` - Basic connection tests passing ✅

### Known Issues

#### 1. CacheObservationIntegrationTests - Hanging Test
**File**: `Tests/NDKSwiftTests/Integration/CacheObservationIntegrationTests.swift`
**Test**: `testGRDBReactive_BatchedUpdates`
**Status**: Already documented in `critical-issue-cache-observation-test-hanging.md`
**Issue**: Test hangs indefinitely, properly skipped with `throw XCTSkip()`
**Update**: Already has proper skip in place at line 291

#### 2. RawLoggingIntegrationTest - Network Timeout
**File**: `Tests/NDKSwiftTests/Integration/RawLoggingIntegrationTests.swift`
**Test**: `testRawLoggingOutput`
**Status**: Already fixed with proper skip at line 10
**Issue**: Test hangs when it can't connect to relays, timeout mechanism doesn't work properly
**Solution**: Already has `throw XCTSkip("Temporarily disabled: Test hangs forever - needs proper timeout mechanism")`

#### 3. InternalSubscriptionManager warnings in tests
**Problem**: Tests create NDK instances that trigger the InternalSubscriptionManager initialization before the pool is ready, causing "Pool not available, skipping relay monitoring" warnings.
**Severity**: Low - Just warnings, tests still pass
**Root Cause**: The NDK initialization order creates InternalSubscriptionManager before the pool is created.

#### 4. Large Number of Disabled Tests
**Location**: `DisabledTests/` directory
**Count**: 40 test files disabled
**Notable disabled tests**:
- Authentication E2E tests
- Blossom E2E tests
- Encrypted DM E2E tests
- Event deletion E2E tests
- Memory cache tests
- NIP-17 private messages tests
- NIP-42 authentication tests
- NIP-60 wallet tests
- Outbox model tests
- Relay pool E2E tests
- User profile E2E tests

### Test Infrastructure Observations

#### Positive Aspects
1. **Timeout Helper**: Good implementation in `TestTimeoutHelper.swift` with `performAsyncTest` wrapper
2. **Test Organization**: Clear separation between Unit, Integration, and E2E tests
3. **Mock Support**: Good mock implementations for testing (MockURLSession, MockRelay)
4. **Test Factories**: `EventTestFactory` and `NDKTestFactory` for consistent test data

#### Areas for Improvement

1. **Database Contamination**: CacheObservationIntegrationTests show events from different tests interfering
   - Each test creates a unique DB file but GRDB observations may be cross-contaminating
   - Example: `testCacheObservation_ConcurrentModification` sees events from previous tests

2. **Network-Dependent Tests**: Many tests require real relay connections
   - Should use more mocks for unit tests
   - Integration tests should be clearly marked and skippable in CI

3. **Async Test Complexity**: Heavy use of expectations and task management
   - Complex synchronization with multiple `Task.sleep()` calls
   - Breaking from async iterations can leave streams in undefined state

## Recommendations

1. **Enable Progressive Test Recovery**:
   - Start with simple unit tests that don't require network
   - Move DisabledTests back one at a time after verifying they work
   - Add proper CI skip annotations for network-dependent tests

2. **Improve Test Isolation**:
   - Use completely unique database paths with timestamp + UUID (already done in some tests)
   - Add explicit database cleanup in tearDown
   - Consider using in-memory SQLite (`:memory:`) for faster tests

3. **Better Async Test Patterns**:
   - Replace `Task.sleep()` with proper synchronization primitives
   - Use AsyncStream's built-in completion handling
   - Avoid breaking from async iterations

4. **CI-Friendly Tests**:
   - Add environment variable checks for skipping network tests
   - Group tests by dependencies (pure unit, database, network)
   - Add test categories for selective running

## Critical Issues Summary

1. **testGRDBReactive_BatchedUpdates** - Hanging test (already documented and skipped)
2. **Database observation cross-contamination** - Multiple tests seeing each other's events
3. **Network timeout mechanisms** - Not working reliably for relay connection tests
4. **40 disabled test files** - Large technical debt of untested functionality

## Next Steps

1. Fix database isolation issues first (low risk, high impact)
2. Review and re-enable simple unit tests from DisabledTests
3. Add proper network mocking for integration tests
4. Create test running guide for different environments (local vs CI)
5. Consider running tests with timeout: `swift test --parallel --num-workers 1` to avoid hanging