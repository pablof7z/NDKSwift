# Critical Issue: NDKRelayAuthenticationFlowTests

## Problem Description

The `NDKRelayAuthenticationFlowTests` file contains tests that hang indefinitely because they depend on components that don't exist in the current codebase.

## Root Cause

1. **Missing NDKEventManager**: The tests expect `ndk.eventManager` with methods like:
   - `getPendingAuthEvents(for:)`
   - `retryPendingAuthEvents(for:)`
   These don't exist in the current implementation.

2. **Missing Authentication Flow**: The tests assume an authentication retry mechanism that isn't implemented in the current NDK class.

3. **Incomplete Mock Implementation**: The MockAuthRelay tries to interact with an authentication flow that doesn't exist.

## Affected Tests

- `testPublishFailureWithAuthRequiredTriggersRetry()` - Expects event retry after auth
- `testMultipleEventsRetryAfterAuthentication()` - Expects bulk retry after auth
- `testAuthenticationDeclinedDoesNotRetry()` - Expects pending event tracking
- All tests that call `ndk.eventManager`

## Current Solution

The tests should be either:
1. Skipped with `XCTSkip` until the authentication retry feature is implemented
2. Rewritten to test only the existing authentication features

## Recommended Implementation

To properly implement these tests, the following components need to be added:

### Option 1: Implement NDKEventManager
```swift
class NDKEventManager {
    func getPendingAuthEvents(for relay: String) async -> [NDKEvent]
    func retryPendingAuthEvents(for relay: String) async
}
```

### Option 2: Simplify Tests
Remove the retry logic tests and focus only on testing the authentication state transitions that currently exist.

## Impact

- These tests are important for ensuring proper NIP-42 authentication handling
- Without them, authentication retry logic cannot be properly tested
- The hanging tests block the entire test suite from completing