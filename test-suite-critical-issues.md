# Critical Issues Found in NDKSwift Test Suite

## Overview
This document details critical issues discovered during test suite analysis that require major refactoring.

## 1. E2E Tests Connecting to Real Relays

### Issue
Many E2E tests attempt to connect to real Nostr relays (wss://relay.damus.io, wss://nos.lol, etc.), causing:
- Tests hanging indefinitely when relays are unavailable
- Flaky test results dependent on network conditions
- CI pipeline failures
- Resource consumption from real relay connections

### Files Affected
All files in `Tests/NDKSwiftTests/DisabledTests/`:
- BasicEventFlowE2ETests.swift
- BlossomE2ETests.swift
- EncryptedDME2ETests.swift
- EventDeletionE2ETests.swift
- NIP17PrivateMessagesE2ETests.swift
- RelayPoolE2ETests.swift
- SubscriptionPatternsE2ETests.swift
- UserProfileE2ETests.swift
- ZapFlowE2ETests.swift

### Root Cause
Tests were written to validate real network behavior but lack proper mocking infrastructure.

### Recommended Fix
1. Create a comprehensive `MockRelayServer` that simulates relay behavior
2. Refactor E2E tests to use mock relays instead of real ones
3. Create a separate `NetworkIntegrationTests` target for tests that genuinely need real relays
4. Add proper timeout mechanisms at the transport layer

## 2. Test Isolation Issues

### Issue
Tests pass individually but fail when run as part of the full suite, indicating:
- Shared state between tests
- Database contamination
- Improper tearDown cleanup

### Example
`CacheObservationIntegrationTests` tests pass individually but were reported to fail in full test runs.

### Root Cause
- SQLite cache instances may not be properly isolated between tests
- GRDB observations might persist across test runs
- Async tasks not properly cancelled in tearDown

### Recommended Fix
1. Ensure each test uses a unique database file
2. Implement proper async task cancellation in tearDown
3. Add explicit cache clearing between tests
4. Consider using in-memory databases for tests

## 3. Timeout Mechanism Limitations

### Issue
The `runWithTimeout` helper doesn't reliably cancel network operations:
```swift
func runWithTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T
```

### Root Cause
- Task cancellation doesn't interrupt low-level URLSession operations
- WebSocket connections may ignore cancellation
- No timeout configuration at the transport layer

### Recommended Fix
1. Configure URLSession timeouts properly:
   ```swift
   let config = URLSessionConfiguration.default
   config.timeoutIntervalForRequest = 30
   config.timeoutIntervalForResource = 60
   ```
2. Implement connection-level timeouts in NDKRelayConnection
3. Add explicit connection state monitoring with timeouts

## 4. Missing Test Infrastructure

### Issue
Lack of proper test utilities and mocking infrastructure makes it difficult to write reliable tests.

### Missing Components
- Comprehensive MockRelay implementation
- Test data factories for common scenarios
- Async test utilities
- Performance testing infrastructure

### Recommended Fix
1. Create a `TestUtilities` module with:
   - MockRelay with configurable behaviors
   - EventFactory for generating test events
   - AsyncTestCase base class with timeout support
   - Performance measurement utilities

## 5. Disabled Tests Organization

### Issue
20+ test files in DisabledTests directory with no clear plan for re-enabling them.

### Recommended Approach
1. Audit each disabled test to determine if it's still relevant
2. Group tests by their issues (network dependency, timing, etc.)
3. Create a roadmap for fixing and re-enabling tests
4. Document why each test is disabled

## Next Steps

1. **Immediate**: Keep E2E tests disabled via Package.swift exclude
2. **Short-term**: Fix test isolation issues in unit/integration tests
3. **Medium-term**: Implement proper mocking infrastructure
4. **Long-term**: Refactor and re-enable E2E tests with mocks

## Testing Best Practices Going Forward

1. Never connect to real services in unit tests
2. Use dependency injection for testability
3. Each test should be completely isolated
4. Use explicit timeouts for all async operations
5. Mock external dependencies at the boundary
6. Keep tests fast and deterministic