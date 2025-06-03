# Relay Tracking in NDKSwift

## Overview

NDKSwift provides comprehensive relay tracking for events, allowing you to know:
- Which relays an event has been seen on
- Publishing status for each relay (success/failure/pending)
- Detailed failure reasons when publishing fails

## Event Relay Properties

Every `NDKEvent` instance tracks relay information through the following properties:

### `seenOnRelays: Set<String>`
A set of relay URLs where this event has been observed. This is automatically populated when:
- An event is received from a relay during subscription
- An event is fetched from a relay

### `relayPublishStatuses: [String: RelayPublishStatus]`
A dictionary mapping relay URLs to their publish status. This tracks the outcome of publishing attempts to each relay.

## Publishing Status Tracking

When you publish an event, the relay statuses are automatically tracked:

```swift
// Using standard publish
let event = NDKEvent(ndk: ndk)
event.kind = 1
event.content = "Hello Nostr!"

let publishedRelays = try await ndk.publish(event)

// Check which relays succeeded
print("Successfully published to: \(event.successfullyPublishedRelays)")
print("Failed on relays: \(event.failedPublishRelays)")

// Get detailed status for each relay
for (relay, status) in event.relayPublishStatuses {
    switch status {
    case .succeeded:
        print("✅ \(relay): Success")
    case .failed(let reason):
        print("❌ \(relay): Failed - \(reason)")
    case .pending:
        print("⏳ \(relay): Pending")
    case .inProgress:
        print("🔄 \(relay): In Progress")
    case .rateLimited:
        print("⚠️ \(relay): Rate Limited")
    case .retrying(let attempt):
        print("🔁 \(relay): Retrying (attempt \(attempt))")
    }
}
```

## Outbox Model Publishing

When using the outbox model, you get even more detailed tracking:

```swift
// Publish with outbox model
let result = try await ndk.publishWithOutbox(event)

// The PublishResult contains comprehensive information
print("Event ID: \(result.eventId)")
print("Overall status: \(result.overallStatus)")
print("Success count: \(result.successCount)")
print("Failure count: \(result.failureCount)")

// Relay-specific results
for (relay, status) in result.relayStatuses {
    print("\(relay): \(status)")
}

// The event itself is also updated with all relay statuses
print("Event published to: \(event.successfullyPublishedRelays)")
```

## Relay Status Types

### `RelayPublishStatus`
An enum representing the status of publishing to a specific relay:

- `.pending` - Not yet attempted
- `.inProgress` - Currently publishing
- `.succeeded` - Successfully published
- `.failed(PublishFailureReason)` - Failed with specific reason
- `.rateLimited` - Rate limited by relay
- `.retrying(attempt: Int)` - Retrying after failure

### `PublishFailureReason`
Detailed reasons for publish failures:

- `.connectionFailed` - Could not connect to relay
- `.timeout` - Publishing timed out
- `.invalid(String)` - Event rejected as invalid
- `.pow(difficulty: Int)` - Requires proof of work
- `.authRequired` - Authentication required
- `.blocked` - User/event blocked by relay
- `.duplicate` - Event already exists
- `.tooLarge` - Event size exceeds limit
- `.rateLimited` - Rate limit exceeded
- `.unknown` - Unknown failure reason

## Tracking Events Seen on Relays

When subscribing to events, each received event automatically tracks which relay it came from:

```swift
let subscription = ndk.subscribe(filters: [filter]) { event in
    print("Event \(event.id ?? "") seen on relays: \(event.seenOnRelays)")
    
    // The relay property shows which relay this specific instance came from
    if let relay = event.relay {
        print("Received from: \(relay.url)")
    }
}
```

## Helper Properties

NDKEvent provides convenience properties for relay tracking:

### `successfullyPublishedRelays: [String]`
Returns an array of relay URLs where publishing succeeded.

### `failedPublishRelays: [String]`
Returns an array of relay URLs where publishing failed.

### `wasPublished: Bool`
Returns true if the event was successfully published to at least one relay.

## Example: Complete Publishing Flow

```swift
// Create and configure event
let event = NDKEvent(ndk: ndk)
event.kind = 1
event.content = "Testing relay tracking"
event.pubkey = signer.publicKey()

// Publish with outbox model for intelligent relay selection
let result = try await ndk.publishWithOutbox(
    event,
    config: OutboxPublishConfig(
        minSuccessfulRelays: 3,
        maxRetries: 2,
        enablePow: true
    )
)

// Check overall result
if result.overallStatus == .succeeded {
    print("✅ Published successfully!")
    print("   Published to \(result.successCount) relays")
    
    // Show successful relays
    for relay in event.successfullyPublishedRelays {
        print("   ✓ \(relay)")
    }
} else {
    print("❌ Publishing failed or partially failed")
    print("   Succeeded: \(result.successCount)")
    print("   Failed: \(result.failureCount)")
    
    // Show detailed failures
    for (relay, status) in event.relayPublishStatuses {
        if case .failed(let reason) = status {
            print("   ✗ \(relay): \(reason)")
        }
    }
}

// Later, check if event has been seen elsewhere
let filter = NDKFilter(ids: [event.id!])
let events = try await ndk.fetchEvents(filters: [filter])

if let fetchedEvent = events.first {
    print("Event now seen on \(fetchedEvent.seenOnRelays.count) relays:")
    for relay in fetchedEvent.seenOnRelays {
        print("   - \(relay)")
    }
}
```

## Best Practices

1. **Always check `wasPublished`** before assuming an event was successfully sent
2. **Use `successfullyPublishedRelays`** to verify minimum relay coverage
3. **Examine `failedPublishRelays`** and their reasons to handle failures appropriately
4. **Monitor `seenOnRelays`** to track event propagation across the network
5. **Use the outbox model** for automatic retry and optimal relay selection

## Persistence

Relay tracking information is ephemeral and exists only for the lifetime of the NDKEvent instance. If you need to persist this information:

1. Store the relay statuses in your own database
2. Use the cache adapter to store metadata
3. Include relay information in custom event tags