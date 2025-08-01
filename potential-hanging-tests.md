# Potential Hanging Test Analysis

## Issue: Many tests contain patterns that could cause hanging

After analyzing the test suite, here are the key issues found:

### 1. Unbounded `for await` loops
Many tests have patterns like:
```swift
for await event in dataSource.events {
    // Could hang forever if no events arrive
}
```

### 2. Task.sleep without proper timeouts
Tests use `Task.sleep(nanoseconds:)` for delays but don't have overall test timeouts.

### 3. Real network dependencies
Some tests connect to real relays which could be down or slow.

### 4. Infinite polling loops
Tests that poll for conditions without a maximum timeout.

## Recommendations

### Short-term fixes:
1. Add timeout wrappers to all async tests
2. Use XCTest's built-in timeout features
3. Replace real relay URLs with mocks

### Long-term improvements:
1. Create a test harness that enforces timeouts
2. Separate unit tests from integration tests
3. Use dependency injection for network components

## Critical Areas to Fix First:

1. **SubscriptionReplayTests.swift** - Already disabled but shows the pattern
2. Any test using `waitForRelayConnections` without checking the result
3. Tests with `for await` loops that don't have cancellation logic
4. Tests connecting to real relays (wss:// URLs)

## Proposed Solution

Create a test helper that wraps async operations with timeouts:

```swift
func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TestTimeoutError()
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

This would ensure no test can hang indefinitely.