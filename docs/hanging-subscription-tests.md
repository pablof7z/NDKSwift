# Hanging Subscription Tests Report

## Issue Summary
The `NDKDataSourceTests.swift` file contains multiple tests that hang indefinitely due to async iterations that never complete. These tests use `for await` loops on AsyncSequences that never receive termination signals.

## Root Cause
The tests create async iterations like:
```swift
for await event in dataSource.events {
    // Process event
}
```

Without proper termination conditions, these loops run forever waiting for events that may never arrive.

## Affected Tests
- Most tests in `NDKDataSourceTests.swift` that use async iteration
- Tests simulate events through cache but the async sequences may not be properly connected
- No timeout protection on the iterations themselves

## Common Patterns Causing Hangs
1. **Infinite async loops without break conditions**
2. **Missing task cancellation**
3. **Race conditions between setup and event delivery**
4. **No timeout on async iterations**

## Temporary Fixes Applied
The tests already have some mitigation strategies:
- Using `break` after receiving expected number of events
- Task cancellation after assertions
- `Task.sleep()` to allow setup time

However, these are not consistently applied and some tests still hang.

## Recommended Solutions

### Short-term
1. Add timeout wrappers around all async iterations
2. Ensure all tasks are cancelled in test cleanup
3. Use XCTestExpectation with proper timeouts
4. Add diagnostic logging to understand where tests hang

### Long-term
1. Refactor AsyncSequence implementation to support proper termination
2. Create test utilities for safely consuming async sequences with timeouts
3. Consider using Combine or other frameworks with better timeout support
4. Implement proper test lifecycle management

## Impact
These hanging tests prevent the test suite from completing, making CI/CD pipelines fail and local development frustrating.

## Priority
HIGH - Blocking test suite execution