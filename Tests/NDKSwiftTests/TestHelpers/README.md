# NDKSwift Test Helpers

This directory contains a comprehensive test infrastructure to reduce duplication and improve test maintainability across the NDKSwift test suite.

## Overview

The test helpers provide:
- Base test case classes with common setup/teardown
- Factory methods for creating test data
- Fixtures with pre-defined test data
- Async test utilities
- Mock implementations

## Base Test Classes

### NDKTestCase
The foundational base class for all NDKSwift tests.

```swift
class MyTest: NDKTestCase {
    func testExample() async throws {
        // Automatic temp directory creation
        let tempFile = createTempFilePath(extension: "json")
        
        // Factory methods
        let ndk = createTestNDK()
        
        // Cleanup is automatic
    }
}
```

Features:
- Automatic temp directory management
- NDK instance tracking and cleanup
- Factory methods for common objects
- Performance measurement utilities

### NDKUnitTestCase
Enhanced base class for unit tests with pre-configured NDK setup.

```swift
class MyUnitTest: NDKUnitTestCase {
    func testExample() async throws {
        // Pre-configured properties available:
        // - ndk: NDK instance with memory cache
        // - signer: Test signer
        // - cache: Memory cache
        // - testUser: Test user created from signer
        
        let event = try await createSignedTestEvent(
            content: "Hello test"
        )
        
        await assertEventInCache(event)
    }
}
```

### NDKIntegrationTestCase
Base class for integration tests requiring real relay connections.

```swift
class MyIntegrationTest: NDKIntegrationTestCase {
    func testRelayInteraction() async throws {
        let ndk = try await createConnectedNDK()
        
        let event = try await createSignedTestEvent()
        try await publishAndWaitForConfirmation(
            event: event,
            ndk: ndk
        )
    }
}
```

### NDKPerformanceTestCase
Base class for performance tests with metrics.

```swift
class MyPerfTest: NDKPerformanceTestCase {
    func testPerformance() {
        let events = createLargeEventSet(count: 10000)
        
        measureAsyncPerformance {
            // Performance critical code
        }
    }
}
```

### NDKMockTestCase
Base class for tests using mock relays.

```swift
class MyMockTest: NDKMockTestCase {
    func testWithMocks() async throws {
        let mockRelay = addConfiguredMockRelay(
            shouldFailPublish: false
        )
        
        // Test with mock relay behavior
    }
}
```

### NDKCacheTestCase
Base class for cache-specific tests.

```swift
class MyCacheTest: NDKCacheTestCase {
    func testCaching() async throws {
        // Test with both memory and SQLite caches
        let results = try await testWithBothCaches { cache in
            try await cache.saveEvent(event)
            return await cache.getEvent(id: event.id)
        }
        
        XCTAssertNotNil(results.memory)
        XCTAssertNotNil(results.sqlite)
    }
}
```

## Test Factories

### NDKTestFactory
Creates NDK instances with various configurations.

```swift
// Basic NDK
let ndk = NDKTestFactory.createNDK()

// Authenticated NDK
let (ndk, signer) = try NDKTestFactory.createAuthenticatedNDK()

// Connected NDK
let ndk = try await NDKTestFactory.createConnectedNDK()
```

### EventTestFactory
Creates test events with sensible defaults.

```swift
// Basic event
let event = EventTestFactory.createEvent()

// Signed event
let event = try await EventTestFactory.createSignedEvent(ndk: ndk)

// Specific event types
let note = EventTestFactory.createTextNote()
let metadata = EventTestFactory.createMetadataEvent()
let deletion = EventTestFactory.createDeletionEvent(eventIds: ["id1", "id2"])
```

### FilterTestFactory
Creates test filters.

```swift
let filter = FilterTestFactory.createTextNoteFilter()
let metadataFilter = FilterTestFactory.createMetadataFilter(pubkeys: [pubkey])
let replyFilter = FilterTestFactory.createReplyFilter(to: eventId)
```

### UserTestFactory
Creates test users.

```swift
let user = try await UserTestFactory.createUser()
let users = try await UserTestFactory.createUsers(count: 5)
```

## Test Fixtures

### Pre-defined Test Data

```swift
// Well-known key pairs
let alice = TestFixtures.Keys.alice
let bob = TestFixtures.Keys.bob

// Pre-built events
let textNote = TestFixtures.Events.textNote
let metadata = TestFixtures.Events.metadata

// Common filters
let filter = TestFixtures.Filters.allTextNotes

// Test content
let content = TestFixtures.Content.validMetadata
```

### Extended Fixtures

```swift
// Encryption test data
let plaintext = TestFixtures.Encryption.plaintext
let conversation = TestFixtures.Encryption.conversation

// Wallet test data
let mintURL = TestFixtures.Wallet.testMintURL
let proofs = TestFixtures.Wallet.sampleProofs

// Large datasets for performance tests
let events = TestFixtures.LargeDatasets.generateRealisticEventSet(count: 1000)
let (users, socialEvents) = TestFixtures.LargeDatasets.generateSocialGraph()
```

## Async Test Utilities

### Enhanced Async Helpers

```swift
// Wait for condition
await assertEventually {
    await subscription.hasReceivedEose
}

// Collect from AsyncSequence
let events = try await collectFromAsyncSequence(subscription) { event in
    event.kind == 1
}

// Wait for specific number of events
let events = await waitForEvents(from: subscription, count: 5)

// Retry with backoff
let result = try await retry(maxAttempts: 3) {
    try await performNetworkOperation()
}

// Parallel execution
let results = try await runInParallel { index in
    try await fetchEvent(at: index)
} count: 10
```

## Mock Implementations

### MockRelay
Test relay implementation for unit tests.

```swift
let relay = MockRelay(url: "wss://test.relay")
relay.shouldFailPublish = true
relay.publishDelay = 0.5
```

### MockURLSession
Mock URL session for network tests.

```swift
let session = MockURLSession()
session.responseData = testData
session.responseError = TestError.network
```

## Best Practices

1. **Choose the Right Base Class**
   - Use `NDKUnitTestCase` for most unit tests
   - Use `NDKIntegrationTestCase` only when real relays are needed
   - Use `NDKPerformanceTestCase` for performance measurements

2. **Use Factories and Fixtures**
   - Prefer factory methods over manual object creation
   - Use fixtures for well-known test data
   - Generate large datasets with fixture generators

3. **Leverage Async Utilities**
   - Use `assertEventually` instead of manual polling
   - Use `waitForEvents` for subscription tests
   - Use `retry` for flaky network operations

4. **Keep Tests Focused**
   - Each test should verify one specific behavior
   - Use descriptive test names
   - Clean up resources (automatic with base classes)

## Migration Guide

To migrate existing tests to use the new infrastructure:

1. Change base class from `XCTestCase` to appropriate `NDK*TestCase`
2. Remove manual setup/teardown of NDK, cache, and signers
3. Replace manual event/filter creation with factory methods
4. Use `TestFixtures` for common test data
5. Replace custom async helpers with provided utilities

Example migration:

```swift
// Before
class MyTest: XCTestCase {
    var ndk: NDK!
    var cache: MemoryCache!
    
    override func setUp() async throws {
        cache = MemoryCache()
        ndk = NDK(cache: cache)
    }
    
    func testSomething() async throws {
        let event = NDKEvent(kind: 1, content: "Test")
        // ...
    }
}

// After
class MyTest: NDKUnitTestCase {
    func testSomething() async throws {
        let event = createTestEvent(content: "Test")
        // ndk and cache are already available
    }
}
```