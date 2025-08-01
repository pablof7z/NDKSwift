# Test Suite Improvements and Issues

## Issues Found

### 1. RawLoggingIntegrationTest hangs forever
**Problem**: The test attempts to connect to real relays and hangs when it can't connect or receives no data.
**Location**: `/Tests/NDKSwiftTests/Integration/RawLoggingIntegrationTests.swift`
**Severity**: High - Causes test suite to hang
**Solution**: The test has timeout logic but seems to still hang. Needs investigation on why the timeout mechanism isn't working properly.

### 2. InternalSubscriptionManager warnings in tests
**Problem**: Tests create NDK instances that trigger the InternalSubscriptionManager initialization before the pool is ready, causing "Pool not available, skipping relay monitoring" warnings.
**Severity**: Low - Just warnings, tests still pass
**Root Cause**: The NDK initialization order creates InternalSubscriptionManager before the pool is created.

## Areas Needing Major Refactoring

### 1. Test Setup Pattern
Many tests are setting up NDK instances incorrectly:
- Creating NDK without relay URLs leads to no pool
- Creating subscriptions without proper NDK initialization
- Not properly cleaning up resources in tearDown

### 2. Disabled Tests
There are many disabled tests in the DisabledTests directory that need to be reviewed:
- E2E tests that depend on real relay connections
- Tests that have race conditions
- Tests that don't have proper timeout handling

## Recommendations

1. **Implement a proper test timeout mechanism at the test runner level**
   - Swift test doesn't have built-in timeout support
   - Consider using XCTest's `executionTimeAllowance` property
   - Or implement a custom test runner wrapper

2. **Create standardized test helpers**
   - MockNDK that doesn't try to connect to real relays
   - Proper setup/teardown patterns
   - Test data builders

3. **Fix the initialization order issue**
   - The InternalSubscriptionManager should check if pool exists before trying to monitor
   - Or delay relay monitoring until first subscription is created

4. **Review and fix disabled tests**
   - Many E2E tests could be converted to integration tests with mocks
   - Add proper timeout handling to all async tests
   - Fix race conditions with proper synchronization