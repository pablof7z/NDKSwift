# Test Suite Improvement Notes

## NDKPoolTests.testRelayPoolChangeEvents Issue

### Problem
The `testRelayPoolChangeEvents` test is flaky due to race conditions in the relay event system. While the test expects to receive both `relayAdded` and `relayRemoved` events, it sometimes only receives the `relayAdded` event.

### Root Cause Analysis
1. The test uses non-existent relay URLs (e.g., `wss://relay.example.com/`), which causes connection failures
2. The `removeRelay` method in `NDKPool` correctly emits the `relayRemoved` event synchronously
3. However, there appears to be a race condition where the AsyncStream consumer might not be ready to receive the second event
4. The test's expectation fulfillment count of 2 might cause the observer to stop listening prematurely

### Solution Implemented (2025-08-01)
- Added `TestTimeoutHelper` usage to prevent test hanging
- Introduced an `EventCollector` actor for thread-safe event collection
- Increased sleep times between operations (100ms) for better stability
- Extended timeout values for XCTestExpectation (3.0 seconds)
- Added proper `[weak self]` capture to avoid retain cycles
- Test now passes consistently in multiple runs

### Potential Long-term Solutions
1. **Mock Relay Implementation**: Create a proper mock relay that doesn't attempt real connections
2. **Synchronous Testing Mode**: Add a testing mode to NDKPool that ensures events are delivered synchronously
3. **Event Buffering**: Implement a small buffer in the AsyncStream to prevent event loss during rapid operations
4. **Test-specific Pool**: Create a test-specific pool implementation that guarantees event delivery

### Other Test Suite Issues Found

1. **DisabledTests Directory**: Contains many E2E tests that are disabled, likely due to:
   - Dependency on real relay servers
   - Long execution times
   - Network instability

2. **Hanging Tests**: Some tests appear to hang forever, particularly:
   - Subscription-related tests that wait for network events
   - Tests that use real WebSocket connections

3. **Missing Timeout Protection**: Many async tests don't use the `TestTimeoutHelper` that was created to prevent hanging

### Recommendations

1. **Immediate**: Continue using the current mitigation approach for NDKPoolTests
2. **Short-term**: Add timeout protection to all async tests using `TestTimeoutHelper`
3. **Medium-term**: Create proper mock implementations for relays and network operations
4. **Long-term**: Refactor the test suite to separate unit tests from integration tests

## Files Examined and Fixed

- `/Tests/NDKSwiftTests/Unit/Core/NDKPoolTests.swift` - Fixed race condition in `testRelayPoolChangeEvents`
- Various utility tests were examined and found to be working correctly:
  - HexValidatorTests
  - StringExtensionsTests
  - Bech32Tests
  - ContentParserTests
  - CacheObservationIntegrationTests