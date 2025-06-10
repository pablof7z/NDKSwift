# NDKSwift Testing Guide

This guide explains the testing architecture, patterns, and best practices for NDKSwift.

## Table of Contents
- [Test Architecture Overview](#test-architecture-overview)
- [WebSocket Mocking](#websocket-mocking)
- [Writing Tests](#writing-tests)
- [Test Utilities](#test-utilities)
- [Best Practices](#best-practices)
- [Common Patterns](#common-patterns)

## Test Architecture Overview

NDKSwift uses a layered testing approach:

```
┌─────────────────────────────────────┐
│        Integration Tests            │  (Real-world scenarios)
├─────────────────────────────────────┤
│         Unit Tests                  │  (Individual components)
├─────────────────────────────────────┤
│      Mock Infrastructure            │  (WebSocket, Relay, Cache)
└─────────────────────────────────────┘
```

### Test Categories

1. **Unit Tests**: Test individual components in isolation
   - Located in: `Tests/NDKSwiftTests/{Component}/`
   - Examples: `CryptoTests`, `NDKEventTests`, `Bech32Tests`

2. **Integration Tests**: Test component interactions
   - Located in: `Tests/NDKSwiftTests/Core/`, `Tests/NDKSwiftTests/Relay/`
   - Examples: `NDKIntegrationTests`, `WebSocketRelayTests`

3. **Mock Tests**: Test with controlled environments
   - Use: `MockWebSocket`, `TestableNDKRelay`, `MockRelay`

## Mock Relay System

### Overview

The mock relay system allows testing Nostr relay functionality without real network connections.

### Components

1. **MockRelay**: Full relay implementation for testing
   - Implements `RelayProtocol` interface
   - Simulates connection states and message flow
   - Configurable delays, failures, and auto-responses
   - Tracks sent messages and active subscriptions

2. **MockWebSocketConnection**: WebSocket-level mock (optional)
   - Lower-level mock for testing connection behavior
   - Simulates WebSocket-specific functionality

3. **Test Helpers**: Extensions and utilities
   - State checking methods
   - Message verification helpers
   - Event simulation methods

### Basic Usage

```swift
// 1. Create mock relay
let mockRelay = MockRelay(url: "wss://test.relay.com")
mockRelay.autoConnect = true
mockRelay.connectionDelay = 0.1 // 100ms delay

// 2. Connect and test
try await mockRelay.connect()
XCTAssertEqual(mockRelay.connectionState, .connected)

// 3. Send messages
try await mockRelay.send("[\"REQ\",\"sub1\",{\"kinds\":[1]}]")
XCTAssertEqual(mockRelay.sentMessages.count, 1)

// 4. Simulate events and responses
let mockEvent = NDKEvent(id: "test", pubkey: "pubkey", ...)
mockRelay.simulateEvent(mockEvent, forSubscription: "sub1")
mockRelay.simulateEOSE(forSubscription: "sub1")
```

### Advanced Configuration

```swift
// Configure failure scenarios
mockRelay.shouldFailConnection = true
mockRelay.connectionError = URLError(.cannotConnectToHost)

// Configure send failures
mockRelay.shouldFailSend = true

// Add mock responses
let events = [mockEvent1, mockEvent2]
mockRelay.addMockResponse(for: "sub1", events: events)
mockRelay.autoRespond = true

// Observe connection state changes
mockRelay.observeConnectionState { state in
    print("State changed to: \(state)")
}

// Reset state for clean tests
mockRelay.reset()
```

## Writing Tests

### Unit Test Template

```swift
import XCTest
@testable import NDKSwift

final class MyComponentTests: XCTestCase {
    // Setup/teardown
    override func setUp() async throws {
        try await super.setUp()
        // Initialize test objects
    }
    
    override func tearDown() async throws {
        // Clean up
        try await super.tearDown()
    }
    
    // Test methods
    func testBasicFunctionality() async throws {
        // Arrange
        let component = MyComponent()
        
        // Act
        let result = try await component.doSomething()
        
        // Assert
        XCTAssertEqual(result, expectedValue)
    }
}
```

### Integration Test Template

```swift
final class RelayIntegrationTests: XCTestCase {
    var ndk: NDK!
    var mockRelay: MockRelay!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create NDK instance
        ndk = NDK()
        
        // Create mock relay
        mockRelay = MockRelay(url: "wss://test.relay.com")
        mockRelay.ndk = ndk
        
        // Configure NDK
        ndk.signer = try NDKPrivateKeySigner.generate()
    }
    
    func testEventPublishing() async throws {
        // Connect relay
        try await mockRelay.connect()
        
        // Create event
        let event = NDKEvent(...)
        
        // Send and verify
        let message = NostrMessage.event(subscriptionId: nil, event: event)
        try await mockRelay.send(message.serialize())
        XCTAssertTrue(mockRelay.wasSent(messageType: "EVENT"))
    }
}
```

## Test Utilities

### MockRelay

Simple relay mock for basic testing:

```swift
let mockRelay = MockRelay(url: "wss://mock.relay.com")
mockRelay.shouldFailConnection = false
mockRelay.addMockEvent(testEvent)

// Use in subscriptions
mockRelay.simulateEvent(event, forSubscription: "sub1")
mockRelay.simulateEOSE(forSubscription: "sub1")
```

### MockRelay Features

The MockRelay provides comprehensive testing capabilities:

```swift
// Access sent messages
let messages = mockRelay.sentMessages
let hasReq = mockRelay.wasSent(messageType: "REQ")

// Check connection state
let isConnected = mockRelay.connectionState == .connected

// Access active subscriptions
let subs = mockRelay.activeSubscriptions
```

### Test Helpers

```swift
// Create test events
let event = NDKEvent(
    pubkey: "test_pubkey",
    createdAt: Timestamp(Date().timeIntervalSince1970),
    kind: 1,
    tags: [],
    content: "Test message"
)
event.id = "test_id"
event.sig = "test_sig"

// Create test filters
let filter = NDKFilter(
    authors: ["pubkey1", "pubkey2"],
    kinds: [1, 7],
    limit: 100
)

// Create test signer
let signer = try NDKPrivateKeySigner.generate()
```

## Best Practices

### 1. Use Appropriate Mock Level

- **Unit tests**: Mock at the component boundary
- **Integration tests**: Mock external dependencies (network, file system)
- **End-to-end tests**: Minimize mocking

### 2. Test Async Code Properly

```swift
// Use async/await
func testAsyncOperation() async throws {
    let result = try await asyncFunction()
    XCTAssertEqual(result, expected)
}

// Use expectations for callbacks
func testCallbackOperation() async throws {
    let expectation = XCTestExpectation(description: "Callback fired")
    
    component.doSomething { result in
        XCTAssertEqual(result, expected)
        expectation.fulfill()
    }
    
    await fulfillment(of: [expectation], timeout: 5.0)
}
```

### 3. Test Error Cases

```swift
func testConnectionFailure() async throws {
    mockWebSocket.shouldFailConnection = true
    
    do {
        try await relay.connect()
        XCTFail("Should have thrown error")
    } catch {
        XCTAssertTrue(error is NDKError)
    }
}
```

### 4. Clean Up Resources

```swift
override func tearDown() async throws {
    // Disconnect relays
    await relay?.disconnect()
    
    // Clear mocks
    mockWebSocket = nil
    
    // Call super
    try await super.tearDown()
}
```

### 5. Use Descriptive Test Names

```swift
// Good
func testEventPublishingFailsWhenNotConnected() async throws { }
func testSubscriptionReceivesEventsMatchingFilter() async throws { }

// Bad
func testEvent() async throws { }
func testSub() async throws { }
```

## Common Patterns

### Testing Subscriptions

```swift
func testSubscription() async throws {
    // Setup
    let mockRelay = MockRelay(url: "wss://test.com")
    let ndk = NDK()
    mockRelay.ndk = ndk
    try await mockRelay.connect()
    
    // Create subscription
    let filter = NDKFilter(kinds: [1])
    let subscription = NDKSubscription(
        id: "test_sub",
        filters: [filter],
        ndk: ndk
    )
    mockRelay.addSubscription(subscription)
    
    // Prepare mock events
    let mockEvents = [
        NDKEvent(id: "1", pubkey: "pub1", ...),
        NDKEvent(id: "2", pubkey: "pub2", ...),
        NDKEvent(id: "3", pubkey: "pub3", ...)
    ]
    mockRelay.addMockResponse(for: "test_sub", events: mockEvents)
    
    // Send subscription request
    try await mockRelay.send("[\"REQ\",\"test_sub\",{...}]")
    
    // Verify events are delivered
    var receivedCount = 0
    Task {
        for await event in subscription {
            receivedCount += 1
            if receivedCount == 3 { break }
        }
    }
    
    await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertEqual(receivedCount, 3)
}
```

### Testing Event Publishing

```swift
func testPublishing() async throws {
    // Setup
    let ndk = NDK()
    ndk.signer = try NDKPrivateKeySigner.generate()
    
    let relay = TestableNDKRelay(url: "wss://test.com", mockWebSocket: mockWS)
    try await relay.connect()
    
    // Create and publish event
    let event = NDKEvent(...)
    try await ndk.publish(event)
    
    // Verify
    XCTAssertTrue(relay.wasSent(messageType: "EVENT"))
    let sentMessage = relay.sentMessages.last!
    XCTAssertTrue(sentMessage.contains(event.id!))
}
```

### Testing Cache Integration

```swift
func testCacheIntegration() async throws {
    // Setup cache
    let cache = NDKInMemoryCache()
    ndk.cache = cache
    
    // Store event in cache
    let event = createTestEvent()
    await cache.setEvent(event, filters: [filter], relay: nil)
    
    // Fetch from cache
    let events = try await ndk.fetchEvents(filter)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.id, event.id)
}
```

### Testing Error Scenarios

```swift
func testNetworkErrors() async throws {
    // Connection failure
    mockWebSocket.shouldFailConnection = true
    await XCTAssertThrowsError(try await relay.connect())
    
    // Send failure
    mockWebSocket.shouldFailConnection = false
    try await relay.connect()
    
    mockWebSocket.shouldFailSend = true
    await XCTAssertThrowsError(try await relay.send("test"))
    
    // Receive error
    mockWebSocket.simulateError(URLError(.networkConnectionLost))
}
```

## Running Tests

### Command Line

```bash
# Run all tests
swift test

# Run specific test file
swift test --filter NDKEventTests

# Run specific test method
swift test --filter NDKEventTests/testEventCreation

# Run with verbose output
swift test --verbose

# Run in parallel
swift test --parallel
```

### Xcode

1. Open Package.swift in Xcode
2. Press ⌘U to run all tests
3. Use Test Navigator to run specific tests
4. Use ⌘⇧U to build tests without running

## Debugging Tests

### Enable Debug Output

```swift
// In test setup
ndk.debugMode = true

// Or use print statements
print("Mock WebSocket state: \(mockWebSocket.isConnected)")
print("Sent messages: \(mockWebSocket.sentMessages)")
```

### Check Mock State

```swift
// After test actions
XCTAssertEqual(mockWebSocket.sentMessages.count, expectedCount)
XCTAssertTrue(mockWebSocket.isConnected)
XCTAssertEqual(relay.connectionState, .connected)

// Print for debugging
dump(mockWebSocket.sentMessages)
```

### Use Breakpoints

- Set breakpoints in test code
- Set breakpoints in mock implementations
- Use LLDB commands: `po variable`, `p expression`

## Contributing Tests

When adding new features:

1. Write unit tests for new components
2. Add integration tests for feature workflows
3. Update existing tests if APIs change
4. Document any new test patterns
5. Ensure all tests pass before submitting PR

### Test Coverage Goals

- Unit tests: >80% coverage for core components
- Integration tests: Cover main user workflows
- Edge cases: Test error conditions and boundaries
- Performance: Add benchmarks for critical paths