# Critical Issue: NDKRelayAuthenticationFlowTests Hanging

## Problem
The NDKRelayAuthenticationFlowTests test suite hangs indefinitely when executed, causing the test runner to timeout after 30 seconds.

## Symptoms
- Running `swift test --filter NDKRelayAuthenticationFlowTests` results in a timeout
- The test builds successfully but hangs during execution
- No test output is produced before the timeout

## Analysis
The test file contains multiple async operations and state transitions that involve:
1. Mock relay connections
2. Authentication challenges and responses  
3. State stream observations
4. Multiple Task.sleep operations for timing

The hanging is likely caused by:
- Deadlocks in the authentication flow simulation
- Infinite loops in state observation streams
- Race conditions between mock operations
- Missing cancellation of observation tasks

## Affected Tests
All tests in NDKRelayAuthenticationFlowTests.swift:
- testAuthenticationWithDelegate
- testAuthenticationDeclined
- testConnectionStateStream
- testAuthChallengeDuringConnection
- testReconnectAfterAuthFailure

## Impact
- Cannot run relay authentication tests
- Cannot verify authentication flow functionality
- Blocks CI/CD pipelines if these tests are included
- May indicate deeper issues with the authentication implementation

## Recommended Fix
This requires a major refactor of the test architecture:

1. **Add timeout mechanisms** to all async operations in tests
2. **Properly cancel observation tasks** in tearDown methods
3. **Review MockRelay implementation** for potential deadlocks
4. **Add diagnostic logging** to identify where tests hang
5. **Consider breaking up complex tests** into smaller, more focused units
6. **Implement proper test isolation** to prevent state leakage

## Temporary Workaround
Until properly fixed, these tests should be:
1. Marked as disabled with a clear comment
2. Excluded from CI test runs
3. Documented as known issues

## Related Issues
- The tests were recently modified to fix "no async operations" warnings
- Similar hanging issues may exist in other async test suites
- Database isolation issues noted in NDKSQLiteCacheReactiveTests may be related