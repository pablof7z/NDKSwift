# NDKSwift Test Implementation Plan

## Overview
This document outlines a comprehensive testing strategy for NDKSwift, prioritized by criticality and following Swift testing best practices.

## Testing Philosophy
- **Unit tests first**: Test individual components in isolation
- **Integration tests**: Test component interactions
- **Mock external dependencies**: WebSockets, network calls, file system
- **Async/await testing**: Proper testing of concurrent code
- **Test-driven fixes**: Write failing tests before fixing bugs

## Priority Order Implementation

### 1. Core Event System Tests (CRITICAL)
**Files to test**: `NDKEvent.swift`, `NDKEventBuilder.swift`
**Why critical**: Events are the fundamental data structure in Nostr

#### Test Cases:
- Event creation with all required fields
- Event ID calculation correctness
- Signature generation and verification
- Event serialization/deserialization
- Content tagging and parsing
- Reply/repost/reaction event creation
- Edge cases (empty content, special characters, Unicode)

### 2. NDK Core Functionality Tests (CRITICAL)
**File to test**: `NDK.swift`
**Why critical**: Main entry point for all SDK operations

#### Test Cases:
- NDK initialization with different configurations
- Event publishing flow (sign → publish → confirm)
- Event fetching (single event, multiple events)
- Profile fetching and caching
- Relay pool management
- Error handling for network failures
- Concurrent operations safety

### 3. Filter System Tests (CRITICAL)
**File to test**: `NDKFilter.swift`
**Why critical**: Determines what events are received from relays

#### Test Cases:
- Filter creation with various parameters
- Filter matching logic for events
- Complex filter combinations (AND/OR logic)
- Time-based filtering (since/until)
- Author and kind filtering
- Tag filtering (#e, #p, #t, etc.)
- Filter serialization for relay messages

### 4. Subscription System Tests (HIGH)
**Files to test**: `NDKSubscription.swift`, `NDKSubscriptionIterator.swift`
**Why critical**: Core mechanism for receiving real-time events

#### Test Cases:
- AsyncSequence implementation correctness
- Subscription lifecycle (start, receive events, close)
- Multiple concurrent subscriptions
- Auto-reconnection on connection loss
- Memory leak prevention
- EOSE (end of stored events) handling
- Duplicate event filtering

### 5. Relay Connection Tests (HIGH)
**Files to test**: `NDKRelayConnection.swift`, `NDKRelayPool.swift`
**Why critical**: Network layer reliability

#### Test Cases:
- WebSocket connection establishment
- Message parsing (EVENT, OK, EOSE, NOTICE)
- Automatic reconnection with backoff
- Connection state management
- Multi-relay coordination
- Relay selection strategies
- Error message handling

### 6. Cache System Tests (MEDIUM)
**Files to test**: `NDKSQLiteCache.swift`, `NDKInMemoryCache.swift`
**Why critical**: Data persistence and performance

#### Test Cases:
- Event storage and retrieval
- Profile caching
- Cache expiration
- Query performance
- Concurrent access safety
- Migration handling (SQLite)
- Cache size limits

### 7. Signer Tests (MEDIUM)
**Files to test**: `NDKPrivateKeySigner.swift`, signature verification
**Why critical**: Security and authentication

#### Test Cases:
- Key generation
- Event signing
- Signature verification
- Invalid signature detection
- Different key formats (hex, nsec)
- Error handling for invalid keys

### 8. Profile Management Tests (MEDIUM)
**File to test**: `NDKUserProfile.swift`
**Why critical**: User data integrity

#### Test Cases:
- Profile metadata parsing
- Profile event creation
- Profile caching integration
- Invalid metadata handling
- Profile update merging

## Test Infrastructure Requirements

### Mock Objects Needed:
```swift
// MockWebSocket - for relay testing
class MockWebSocket: WebSocketProtocol {
    var sentMessages: [String] = []
    var mockResponses: [String] = []
    // Implementation...
}

// MockNDKCacheAdapter - for cache testing
class MockNDKCacheAdapter: NDKCacheAdapter {
    var storedEvents: [String: NDKEvent] = [:]
    // Implementation...
}

// Enhanced MockRelay - for integration tests
class MockRelay {
    var connectedClients: [MockWebSocket] = []
    var storedEvents: [NDKEvent] = []
    // Implementation...
}
```

### Test Fixtures:
```swift
// TestEvents.swift
struct TestEvents {
    static let validTextNote = NDKEvent(...)
    static let validProfile = NDKEvent(...)
    static let invalidSignature = NDKEvent(...)
    // More test events...
}

// TestKeys.swift
struct TestKeys {
    static let alicePrivateKey = "..."
    static let alicePublicKey = "..."
    static let bobPrivateKey = "..."
    static let bobPublicKey = "..."
}
```

### Test Utilities:
```swift
// XCTestCase+Async.swift
extension XCTestCase {
    func waitForAsync(timeout: TimeInterval = 5.0, _ block: () async throws -> Void) async throws {
        // Helper for async testing
    }
}

// AssertionHelpers.swift
func assertEventsEqual(_ event1: NDKEvent, _ event2: NDKEvent) {
    // Custom assertion for event comparison
}
```

## Implementation Timeline

### Week 1: Foundation
- Set up test infrastructure (mocks, fixtures, helpers)
- Implement NDKEvent tests
- Implement NDKFilter tests

### Week 2: Core Functionality
- Implement NDK core tests
- Implement subscription system tests
- Begin relay connection tests

### Week 3: Network & Storage
- Complete relay connection tests
- Implement cache adapter tests
- Implement signer tests

### Week 4: Polish & Coverage
- Profile management tests
- Integration test suite
- Performance benchmarks
- Documentation updates

## Success Metrics
- Minimum 80% code coverage for critical components
- All tests pass consistently
- Tests run in under 30 seconds
- Clear test documentation
- No flaky tests

## Best Practices to Follow
1. **Arrange-Act-Assert pattern**: Clear test structure
2. **One assertion per test**: Focused testing
3. **Descriptive test names**: `test_eventCreation_withValidContent_succeeds()`
4. **Isolated tests**: No dependencies between tests
5. **Fast tests**: Mock external dependencies
6. **Continuous Integration**: All tests must pass before merge