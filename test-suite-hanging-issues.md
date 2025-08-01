# Test Suite Hanging Issues

## Overview
The NDKSwift test suite has several tests that hang forever, particularly those that involve network connections to real Nostr relays. This document outlines the critical issues found and recommendations for fixing them.

## Critical Issues

### 1. Real Relay Connection Tests
Many tests attempt to connect to real Nostr relays (e.g., wss://relay.damus.io, wss://relay.nostr.band), which can:
- Hang if the relay is unavailable
- Hang if network conditions are poor
- Be flaky and unpredictable
- Fail in CI environments

**Affected Tests:**
- `RawLoggingIntegrationTests` - Already marked with XCTSkip
- All tests in `DisabledTests/` directory (20+ test files)
- Any integration tests using real relay URLs

### 2. Timeout Mechanisms Not Working Reliably
The `runWithTimeout` helper exists but doesn't seem to work reliably for network operations:
- WebSocket connections may not respect Task cancellation
- Some async operations continue running even after timeout
- The timeout mechanism uses Task cancellation which may not interrupt low-level network operations

### 3. CacheObservationIntegrationTests Failures
These tests are failing with timing-related issues:
- `testAsyncThrowingStream_BasicObservation` - Expected 1 event, received 0
- `testAsyncThrowingStream_IncludeExistingFlag` - Receiving wrong events
- Race conditions between event saving and observation

## Recommendations

### 1. Replace Real Relay Tests with Mock Relays
- Use `MockRelay` for all unit and integration tests
- Move real relay tests to a separate test target that's not run by default
- Create a `NetworkIntegrationTests` target specifically for tests that require real network connections

### 2. Improve Timeout Handling
- Implement proper WebSocket connection timeouts at the transport layer
- Use URLSession configuration timeouts
- Add explicit connection state monitoring with timeouts

### 3. Fix Race Conditions in Cache Tests
- Add proper synchronization between save operations and observers
- Use explicit barriers or checkpoints to ensure operations complete in order
- Consider using XCTestExpectation with proper timing

### 4. Test Organization
- Enable tests one by one from `DisabledTests/` after fixing
- Add timeout annotations to all async tests
- Create clear separation between:
  - Unit tests (no network, fast)
  - Integration tests (mocked network)
  - E2E tests (real network, optional)

## Next Steps

1. Focus on fixing `CacheObservationIntegrationTests` race conditions
2. Create proper mock relay infrastructure
3. Gradually migrate disabled tests to use mocks
4. Set up separate test targets for different test types