# Outbox Model and Enhanced Requirements Test Suite

This directory contains comprehensive tests for the Outbox Model implementation and the Enhanced Requirements feature added during the cache refactoring.

## Test Files

### 1. OutboxModelTests.swift
Comprehensive tests covering all aspects of the Outbox Model as documented in `Documentation/Internals/Outbox.md`:

- **Core Principles**:
  - User control first (explicit relays override outbox)
  - Per-author scaling (2 relays per author)
  - Connection efficiency (prioritizes already-connected relays)
  - Non-blocking operations

- **Subscription Handling**:
  - Initial setup with known vs unknown authors
  - Background discovery (non-blocking)
  - Dynamic updates creating enhanced requirements
  - Subscription lifecycle management

- **Publishing**:
  - Immediate action with fallback relays
  - P-tag handling (<10 includes, >=10 skips)
  - Background discovery with 5-second timeout
  - Progressive enhancement

- **Relay Selection**:
  - Unified vs per-relay filters
  - Intelligent grouping when authors share relays
  - Mixed scenarios optimization

- **Edge Cases**:
  - Relay list conflicts (uses most recent)
  - Circular dependencies handling
  - Missing relay lists (fallback behavior)

- **Performance**:
  - Large-scale subscriptions (100 authors)
  - Reconnection efficiency (O(1) lookup)

### 2. EnhancedRequirementsTests.swift
Focused tests for the AsyncStream-based Enhanced Requirements implementation:

- **Creation and Management**:
  - Enhanced requirements created for discovered relays
  - Proper subscription ID patterns
  - Network-only policy enforcement
  - Event forwarding to original observers

- **Cleanup**:
  - Proper cleanup when main requirement cancelled
  - No memory leaks
  - Resource management

- **Cache Integration**:
  - GRDB reactive observation
  - Multiple concurrent observers
  - Cross-fingerprint event delivery

- **Performance**:
  - Scalability with 100 authors
  - Efficient relay discovery handling

### 3. CacheObservationIntegrationTests.swift
Integration tests for the new AsyncThrowingStream-based cache observation:

- **AsyncThrowingStream**:
  - Basic observation functionality
  - includeExisting flag behavior
  - Stream lifecycle management

- **GRDB Reactive**:
  - Multiple concurrent observers
  - Batched updates
  - Efficient change notifications

- **Cross-Fingerprint Delivery**:
  - Broad filters receive events from specific filters
  - Complex scenarios with multiple subscriptions
  - Proper event routing

- **Performance**:
  - High-volume event handling (1000 events)
  - Concurrent modifications
  - Scalability testing

- **Edge Cases**:
  - Stream cancellation
  - Concurrent database modifications
  - Error handling

## Key Test Scenarios

### 1. Outbox Model Flow
```swift
// User without relay information
1. Subscribe with unknown author
2. Use fallback relays immediately (non-blocking)
3. Discover relays in background
4. Create enhanced requirements for discovered relays
5. Events flow from both fallback and discovered relays
```

### 2. Enhanced Requirements
```swift
// When relays are discovered
1. Original requirement continues unchanged
2. New enhanced requirements created per discovered relay
3. Enhanced requirements use exclusive relay targeting
4. Events forwarded to original observers
5. Cleanup cascades when original cancelled
```

### 3. Cache Observation
```swift
// Cross-fingerprint delivery
1. Network subscription with specific filter saves events
2. Cache-only subscription with broad filter receives them
3. GRDB triggers efficient notifications
4. Multiple observers handled independently
```

## Running the Tests

```bash
# Run all outbox tests
swift test --filter OutboxModelTests

# Run enhanced requirements tests
swift test --filter EnhancedRequirementsTests

# Run cache observation tests
swift test --filter CacheObservationIntegrationTests

# Run all integration tests
swift test --filter Integration
```

## Test Coverage

These tests cover:
- ✅ All scenarios documented in Outbox.md
- ✅ Enhanced requirements implementation
- ✅ AsyncThrowingStream cache observation
- ✅ GRDB reactive integration
- ✅ Cross-fingerprint event delivery
- ✅ Performance and scalability
- ✅ Edge cases and error conditions
- ✅ Resource management and cleanup

## Notes

- Mock components are included for isolated testing
- Some tests require extensions to production code for observability
- Performance tests use realistic data volumes
- Edge case tests ensure robustness