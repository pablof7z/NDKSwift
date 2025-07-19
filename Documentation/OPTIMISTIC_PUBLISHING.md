# Optimistic Publishing & Offline Support

NDKSwift implements optimistic publishing by default, ensuring your Nostr applications remain responsive even when offline or experiencing connectivity issues.

## Overview

Optimistic publishing means:
- Events appear immediately in local subscriptions (instant UI feedback)
- Automatic retry when connectivity is restored
- Confirmation tracking across multiple relays
- Consistent UI state with relay state

## How It Works

### 1. Event Publishing Flow

When you publish an event:

```swift
let event = try await ndk.event()
    .content("Hello, Nostr!")
    .kind(1)
    .build()

try await ndk.publish(event)
```

The following happens automatically:

1. **Immediate Cache Storage**: Event is saved to cache
2. **Local Dispatch**: Event appears instantly in active subscriptions
3. **Relay Publishing**: Publishes to relays in parallel (non-blocking)
4. **State Tracking**: Cache tracks which relays have confirmed

### 2. Offline Behavior

When offline or relays are unreachable:

- Events are cached with target relays marked as "unpublished"
- Local subscriptions still see the event immediately
- When connection resumes, unpublished events are automatically retried
- Exponential backoff prevents overwhelming relays

### 3. Event Confirmation States

Events progress through three states:

```swift
// Check event confirmation state
let state = await cache.getEventConfirmationState(eventId: event.id)

switch state {
case .optimistic:
    // Event published locally but not confirmed by any relay
    print("Pending...")
    
case .partial(let confirmed, let pending):
    // Event confirmed by some relays, pending on others
    print("Confirmed: \(confirmed.count)/\(confirmed.count + pending.count)")
    
case .confirmed:
    // Event confirmed by all target relays
    print("Delivered!")
}
```

## Configuration

### Subscription Options

While publishing is always optimistic, subscriptions can filter optimistic events:

```swift
// Default behavior (includes optimistic events)
let subscription = ndk.subscribe(filters: [filter])

// Only relay-confirmed events
var options = NDKSubscriptionOptions()
options.skipOptimisticEvents = true
let strictSubscription = ndk.subscribe(filters: [filter], options: options)
```

## Managing Unpublished Events

### Check Unpublished Events

```swift
// Get all unpublished events
let unpublished = try await cache.getUnpublishedEvents()

for (event, relays) in unpublished {
    print("Event \(event.id) pending on: \(relays)")
}
```

### Manual Retry

```swift
// Retry all unpublished events
try await ndk.retryUnpublishedEvents()

// Retry to specific relay
try await ndk.retryUnpublishedEvents(toRelay: "wss://relay.damus.io")

// Retry specific event
try await ndk.retryUnpublishedEvent(eventId, toRelay: relayUrl)
```

### Clear Failed Events

```swift
// Remove specific event from retry queue
try await cache.removeUnpublishedEvent(eventId: event.id)

// Clear all unpublished events
try await cache.clearUnpublishedEvents()
```

## Event Sources

When processing events in subscriptions, you can distinguish their source:

```swift
for await (event, source) in subscription {
    switch source {
    case .optimistic:
        // Locally published, pending confirmation
        showPendingIndicator()
        
    case .relay(let relay):
        // Confirmed by specific relay
        removePendingIndicator()
        
    case .cache:
        // Loaded from cache on startup
        // Check confirmation state if needed
    }
}
```

## Best Practices

### 1. UI Indicators

Show pending state for optimistic events:

```swift
struct PostView: View {
    let event: NDKEvent
    @State private var isPending = false
    
    var body: some View {
        HStack {
            Text(event.content)
            if isPending {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .task {
            let state = await cache.getEventConfirmationState(eventId: event.id)
            isPending = (state == .optimistic)
        }
    }
}
```

### 2. Handle Retry Failures

Monitor failed publishes:

```swift
// Periodic check for stuck events
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
    Task {
        let unpublished = try await cache.getUnpublishedEvents()
        if !unpublished.isEmpty {
            // Show user notification or retry
            try await ndk.retryUnpublishedEvents()
        }
    }
}
```

### 3. Connection State Monitoring

React to connection changes:

```swift
// Monitor connection state and retry on reconnect
for await connectionState in ndk.connectionState {
    if connectionState == .connected {
        // Connection restored, retry pending events
        try await ndk.retryUnpublishedEvents()
    }
}

// Or retry with custom logic
func retryFailedEvents() async throws {
    let unpublished = try await cache.getUnpublishedEvents(limit: 100)
    
    for event in unpublished {
        // Check event age
        let age = TimeInterval(Timestamp.now - event.createdAt)
        
        // Skip old events
        if age > 3600 { continue }
        
        // Retry with specific relays based on event type
        let targetRelays = selectRelaysForEvent(event)
        try await ndk.publish(event, to: targetRelays)
    }
}
```

## Technical Details

### Deduplication

When relay confirmations arrive for optimistically published events:
- The system automatically deduplicates based on event ID
- Subscriptions receive only one copy of each event
- Event source updates from `.optimistic` to `.relay`

### Special Cases

- **Relay Lists (kind 10002)**: Never published optimistically to prevent sync issues
- **Ephemeral Events**: Published optimistically but not cached
- **Replaceable Events**: Latest version always wins

### Performance Considerations

- Optimistic events use minimal memory
- Cache cleanup happens automatically
- No performance impact on subscriptions
- Parallel relay publishing for efficiency

## Example: Offline-First Chat

```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    let ndk: NDK
    
    func sendMessage(_ text: String) async {
        // Create and publish message
        let event = try await ndk.event()
            .content(text)
            .kind(42)
            .tag(["e", chatRoomId])
            .build()
            
        do {
            try await ndk.publish(event)
            // Message appears immediately in UI via subscription
        } catch {
            // Even on error, optimistic publishing ensures it's queued
            print("Message will be sent when connection is restored")
        }
    }
    
    func startListening() {
        Task {
            let filter = NDKFilter(kinds: [42], tags: ["e": [chatRoomId]])
            let subscription = ndk.subscribe(filters: [filter])
            
            for await (event, source) in subscription {
                let message = ChatMessage(from: event)
                
                // Update UI state based on source
                if case .optimistic = source {
                    message.isPending = true
                }
                
                messages.append(message)
            }
        }
    }
}
```

## Migration Notes

If you're updating from a version with configurable optimistic publishing:

1. Remove any `optimisticPublishingConfig` settings - it's now always enabled
2. Remove `NDKOptimisticPublishingConfig` usage
3. Publishing behavior remains the same, just simpler
4. `skipOptimisticEvents` on subscriptions still works as before