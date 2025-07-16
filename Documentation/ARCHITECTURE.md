# NDKSwift Architecture

This document describes the architecture and design patterns used in NDKSwift.

## Overview

NDKSwift is built with modern Swift patterns and a focus on:
- **Type Safety**: Strongly typed events, filters, and operations
- **Concurrency**: Actor-based architecture for thread safety
- **Async/Await**: Modern Swift concurrency throughout
- **Protocol-Oriented**: Flexible and testable design
- **Performance**: Efficient relay management and event deduplication

## Core Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Application Layer                     │
├─────────────────────────────────────────────────────────┤
│                         NDK Core                          │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │   Events    │  │ Subscriptions │  │    Users      │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
├─────────────────────────────────────────────────────────┤
│                    Infrastructure Layer                   │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Relay Pool  │  │   Signers    │  │    Cache      │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
├─────────────────────────────────────────────────────────┤
│                     Network Layer                         │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  WebSocket  │  │   Outbox     │  │   Blossom     │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Key Components

### NDK Core

The `NDK` class is the main entry point and orchestrator:

```swift
public class NDK {
    // Core components
    public let pool: NDKRelayPool                    // Manages relay connections
    public let subscriptionManager: NDKSubscriptionManager  // Handles subscriptions
    public let outbox: NDKOutboxManager              // Intelligent relay selection
    
    // Optional components
    public var signer: NDKSigner?                    // Event signing
    public var cache: NDKCache?                      // Event/profile caching
}
```

### Event Flow

1. **Publishing**:
   ```
   NDKEvent → Sign (NDKSigner) → Outbox Selection → Relay Pool → WebSocket
   ```

2. **Subscribing**:
   ```
   NDKFilter → Subscription Manager → Relay Pool → WebSocket → Event Stream
   ```

3. **Caching**:
   ```
   Incoming Event → Signature Verification → Cache Storage → Event Delivery
   ```

## Concurrency Model

### Actor-Based Architecture

Key components use Swift actors for thread safety:

```swift
// Relay connection state
actor NDKRelayConnectionActor {
    private var state: ConnectionState
    private var websocket: URLSessionWebSocketTask?
}

// Cache operations
public protocol NDKCache: Actor {
    func saveEvent(_ event: NDKEvent) async throws
    func getEvent(id: String) async -> NDKEvent?
}

// Subscription state
actor SubscriptionStateActor {
    private var events: [NDKEvent] = []
    private var seenEventIds: Set<String> = []
}
```

### AsyncSequence for Subscriptions

Subscriptions use AsyncSequence for modern event streaming:

```swift
public struct NDKSubscription: AsyncSequence {
    public typealias Element = NDKEvent
    
    // Auto-starts when iteration begins
    public func makeAsyncIterator() -> AsyncIterator {
        // Start subscription if not already active
        return AsyncIterator(stream: eventStream)
    }
}
```

## Relay Management

### Relay Pool

The relay pool manages multiple relay connections:

```swift
public actor NDKRelayPool {
    private var relays: [RelayURL: NDKRelay] = [:]
    private var subscriptions: [String: Set<NDKRelay>] = [:]
    
    // Automatic reconnection
    private func handleDisconnection(_ relay: NDKRelay) {
        Task {
            await reconnect(relay)
        }
    }
}
```

### Outbox Model

The outbox model (NIP-65) intelligently selects relays:

```swift
public struct NDKOutboxManager {
    // Select relays based on:
    // 1. Author's relay list (kind 10002)
    // 2. Recipients' relay lists
    // 3. Fallback to general relays
    
    func selectRelays(for event: NDKEvent) async -> Set<NDKRelay> {
        // Implementation follows NIP-65 specification
    }
}
```

## Event Processing

### Event Validation

Events are validated before processing:

```swift
extension NDKEvent {
    public func validate() throws {
        // Check required fields
        guard !pubkey.isEmpty else { throw NDKError.invalidEvent("Missing pubkey") }
        guard kind >= 0 else { throw NDKError.invalidEvent("Invalid kind") }
        
        // Verify ID if present
        if let id = id {
            let calculatedId = try generateID()
            guard id == calculatedId else {
                throw NDKError.invalidEvent("Invalid event ID")
            }
        }
    }
}
```

### Signature Verification

Configurable signature verification:

```swift
public struct NDKSignatureVerificationConfig {
    public var enabled: Bool = true
    public var samplingRate: Double = 1.0  // Verify all by default
    public var blacklistRelaysOnFailure: Bool = true
}

// Verification happens in relay connection
func verifySignature(_ event: NDKEvent) -> Bool {
    // Sample based on configuration
    if Double.random(in: 0...1) > config.samplingRate {
        return true  // Skip verification
    }
    
    return Crypto.verifySignature(of: event)
}
```

### Deletion Event Processing (NIP-09)

NDKSwift automatically processes kind:5 deletion events according to NIP-09:

```swift
// In NDKSubscriptionManager
private func processDeletionEvent(_ deletionEvent: NDKEvent) async {
    // Extract event IDs from "e" tags
    let eventIdsToDelete = deletionEvent.tags
        .filter { $0[0] == "e" }
        .map { $0[1] }
    
    // Verify authorship and delete
    for eventId in eventIdsToDelete {
        if let event = await cache.getEvent(id: eventId) {
            // NIP-09: Only original author can delete
            if event.pubkey == deletionEvent.pubkey {
                try await cache.deleteEvent(id: eventId)
            }
        }
    }
}
```

Key features:
- Automatic processing when kind:5 events are received
- Author validation ensures only original authors can delete their events
- Cache is automatically updated
- Works with all cache implementations
- Tombstone cache prevents deleted events from being added if deletion arrives first
- 10-minute TTL on tombstones to handle network timing issues

### Optimistic Publishing

NDKSwift implements optimistic publishing for instant UI feedback:

```swift
// Publishing flow with optimistic publishing
@discardableResult
public func publish(_ event: NDKEvent) async throws -> Set<NDKRelay> {
    // 1. Validate event
    try event.validate()
    
    // 2. Optimistic cache addition
    if optimisticPublishingConfig.enabled && optimisticPublishingConfig.cacheUnpublishedEvents {
        try? await cache?.addUnpublishedEvent(event, relays: targetRelays)
    }
    
    // 3. Optimistic subscription dispatch
    if optimisticPublishingConfig.enabled && optimisticPublishingConfig.dispatchToSubscriptions {
        await subscriptionManager.processOptimisticEvent(event)
    }
    
    // 4. Regular relay publishing
    return try await publishToRelays(event)
}
```

#### Event Source Tracking

Events are tagged with their source for proper handling:

```swift
public enum EventSource: Sendable {
    case optimistic                    // Locally published
    case relay(RelayProtocol)         // From relay
    case cache                        // From cache
}

// Unified event processing
private func processEvent(_ event: NDKEvent, from source: EventSource) async {
    switch source {
    case .optimistic:
        // Skip deduplication for immediate dispatch
        isUnique = true
    case .relay, .cache:
        // Normal deduplication logic
        isUnique = eventDeduplication[eventId] == nil
    }
    // ... dispatch to matching subscriptions
}
```

#### Confirmation State Management

The cache tracks event confirmation states:

```swift
public enum EventConfirmationState: Equatable, Sendable {
    case optimistic                   // Pending confirmation
    case confirmed(fromRelay: String) // Confirmed by relay
    
    public var isConfirmed: Bool {
        switch self {
        case .optimistic: return false
        case .confirmed: return true
        }
    }
}

// Cache integration
func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws
func confirmEvent(eventId: String, onRelay relay: String) async throws  
func getEventConfirmationState(eventId: String) async -> EventConfirmationState?
```

#### Deduplication Strategy

Sophisticated deduplication prevents duplicate events while allowing state transitions:

```swift
func addEventIfNotSeen(_ event: NDKEvent, from source: EventSource) async -> Bool {
    switch source {
    case .optimistic:
        // Add if not already seen
        if eventStates[eventId] == nil {
            eventStates[eventId] = .optimistic
            events.append(event)
            return true
        }
        
    case .relay(let relay):
        // Check if upgrading from optimistic to confirmed
        if let existingState = eventStates[eventId] {
            if case .optimistic = existingState {
                eventStates[eventId] = .confirmed(fromRelay: relay.url)
                return false // Don't add to events again
            }
        }
    }
}
```

## Caching Strategy

### Cache Protocol

The cache protocol is simple and flexible:

```swift
public protocol NDKCache: Actor {
    // Events
    func saveEvent(_ event: NDKEvent) async throws
    func getEvent(id: String) async -> NDKEvent?
    func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent]
    
    // Profiles
    func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws
    func getProfile(pubkey: String) async -> NDKUserProfile?
}
```

### Cache Usage Flow

```
1. Subscription created with useCache: true
2. Check cache for existing events
3. Query relays for new events
4. Store new events in cache
5. Deduplicate using event IDs
```

### Deletion Event Processing

NDKSwift automatically handles NIP-09 deletion events:

```swift
// Automatic deletion processing flow
Event (kind 5) → NDKSubscriptionManager → processDeletionEvent()
                                       ↓
                        Extract 'e' tags → Validate author
                                       ↓
                        Database transaction → Delete events
```

**Key Features**:
- **Author Validation**: Only event authors can delete their events
- **Timestamp Validation**: Deletion must be newer than deleted event
- **Atomic Operations**: Database transactions prevent partial deletions
- **Immediate Processing**: Deletions happen as soon as events are received

## Protocol Design

### NDKSigner Protocol

Flexible signing interface:

```swift
public protocol NDKSigner {
    var pubkey: PublicKey { get async throws }
    
    func sign(_ event: NDKEvent) async throws -> Signature
    func blockUntilReady() async throws
    
    // Encryption support
    func encryptionEnabled() async -> [NDKEncryptionScheme]
    func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String
    func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String
}
```

### Protocol Extensions

Default implementations via extensions:

```swift
extension NDKCache {
    // Batch operations
    public func saveEvents(_ events: [NDKEvent]) async throws {
        for event in events {
            try await saveEvent(event)
        }
    }
    
    // Convenience queries
    public func queryEvents(author: String, kinds: [Int]? = nil) async throws -> [NDKEvent] {
        let filter = NDKFilter(authors: [author], kinds: kinds)
        return try await queryEvents(filter)
    }
}
```

## Error Handling

### Unified Error System

Comprehensive error types:

```swift
public enum NDKError: LocalizedError {
    case signerRequired
    case invalidEvent(String)
    case invalidKey(String)
    case signingFailed(String)
    case relayError(String)
    case networkError(String)
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .signerRequired:
            return "A signer is required for this operation"
        case .invalidEvent(let detail):
            return "Invalid event: \(detail)"
        // ... etc
        }
    }
}
```

### Error Propagation

Errors propagate through async/await:

```swift
// At relay level
func handleRelayError(_ error: Error) {
    subscription.handleError(NDKError.relayError(error.localizedDescription))
}

// At subscription level
for try await event in subscription {
    // Errors thrown here are relay/network errors
}
```

## Performance Optimizations

### Event Deduplication

Events are deduplicated at multiple levels:

```swift
actor EventDeduplicator {
    private var seenIds = Set<String>()
    private let window: TimeInterval = 60  // 1 minute window
    
    func shouldProcess(_ eventId: String) -> Bool {
        defer { cleanOldEvents() }
        return seenIds.insert(eventId).inserted
    }
}
```

### Subscription Grouping

Similar subscriptions are grouped:

```swift
public struct SubscriptionTrackingConfig {
    public var dedupingWindow: TimeInterval = 1.0
    public var groupingDelay: TimeInterval = 0.1
}

// Subscriptions with identical filters share relay connections
```

### Connection Pooling

WebSocket connections are reused:

```swift
actor ConnectionPool {
    private var connections: [RelayURL: URLSessionWebSocketTask] = [:]
    
    func connection(for url: RelayURL) -> URLSessionWebSocketTask {
        if let existing = connections[url], existing.state == .running {
            return existing
        }
        // Create new connection
    }
}
```

## Security Considerations

### Private Key Handling

Private keys are handled securely:

```swift
public struct NDKPrivateKeySigner: NDKSigner {
    private let privateKey: String  // Never exposed publicly
    
    public init(privateKey: String) throws {
        // Validate key format
        guard privateKey.count == 64 else {
            throw NDKError.invalidKey("Private key must be 64 characters")
        }
        self.privateKey = privateKey
    }
}
```

### Signature Verification

All events can be verified:

```swift
// Configurable verification
let config = NDKSignatureVerificationConfig(
    enabled: true,
    blacklistRelaysOnFailure: true,
    failureThreshold: 10
)
```

## Testing Strategy

### Protocol-Based Testing

Protocols enable easy mocking:

```swift
// Mock relay for testing
class MockRelay: RelayProtocol {
    var sentMessages: [String] = []
    
    func send(_ message: String) async throws {
        sentMessages.append(message)
    }
}

// Mock signer
struct MockSigner: NDKSigner {
    let pubkey = "mock_pubkey"
    
    func sign(_ event: NDKEvent) async throws -> Signature {
        return "mock_signature"
    }
}
```

### Async Testing

Modern XCTest async support:

```swift
func testSubscription() async throws {
    let ndk = NDK(relayUrls: ["wss://mock.relay"])
    let subscription = ndk.subscribe(filters: [testFilter])
    
    var events: [NDKEvent] = []
    for try await event in subscription.prefix(10) {
        events.append(event)
    }
    
    XCTAssertEqual(events.count, 10)
}
```

## Future Considerations

### Extensibility Points

The architecture supports future additions:

1. **Custom Protocols**: New NIPs can be added via extensions
2. **Alternative Transports**: Protocol-based design allows non-WebSocket transports
3. **Plugin System**: Cache, signer, and wallet protocols enable plugins
4. **Performance Monitoring**: Hooks for metrics and observability

### Backward Compatibility

The library maintains compatibility through:

1. **Semantic Versioning**: Breaking changes only in major versions
2. **Protocol Evolution**: New protocol methods with default implementations
3. **Deprecation Warnings**: Clear migration paths for API changes

## Cashu Wallet Architecture (NIP-60/61)

### Overview

NDKSwift includes comprehensive support for Cashu ecash wallets through NIP-60 (wallet events) and NIP-61 (nutzaps):

```swift
// Wallet state management
actor ProofStateManager {
    // Centralized proof tracking
    // Handles spent/unspent states
    // Cross-mint operations
}

// Token event tracking
class NDKCashuWallet {
    // Publishes token events to Nostr
    // Tracks deleted/spent tokens
    // Manages mint connections
}
```

### Key Components

1. **Proof State Management**
   - Actor-based for thread safety
   - Tracks all proofs across mints
   - Handles spent detection

2. **Token Event System**
   - Kind 7375: Wallet state
   - Kind 7376: Token storage
   - Kind 5: Token deletion

3. **Nutzap Flow**
   - Creates P2PK locked tokens
   - Publishes nutzap events (kind 9321)
   - Handles redemption automatically

### Integration Points

- **NDK Event System**: Publishes wallet events
- **Signer**: Signs token events and nutzaps
- **Cache**: Stores proof states locally
- **Relay Pool**: Distributes wallet events

## Summary

NDKSwift's architecture prioritizes:

- **Safety**: Actor-based concurrency and strong typing
- **Performance**: Efficient relay management and caching
- **Flexibility**: Protocol-oriented design
- **Modern Swift**: AsyncSequence, async/await throughout
- **Developer Experience**: Simple APIs hiding complexity
- **Wallet Integration**: Native Cashu and NWC support

This architecture enables building robust Nostr applications while maintaining flexibility for future protocol evolution.