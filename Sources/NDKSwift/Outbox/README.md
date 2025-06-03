# NDKSwift Outbox Model Implementation

The outbox model is a sophisticated relay selection algorithm that optimizes how Nostr events are published and fetched. It implements intelligent relay discovery and selection based on user preferences (NIP-65) and contextual information.

## Overview

The outbox model solves several key challenges:
- **Relay Discovery**: Automatically discovers which relays users read from and write to
- **Efficient Publishing**: Publishes events to relays where they're most likely to be seen
- **Optimized Fetching**: Fetches events from the minimal set of relays needed
- **Reliability**: Handles failures, retries, and proof-of-work requirements
- **Performance**: Tracks relay health and prioritizes responsive relays

## Core Components

### 1. NDKOutboxTracker
Manages relay information for users with an LRU cache.

```swift
// Track a user's relay preferences
await ndk.trackUser("user_pubkey")

// Manually set relay information
await ndk.setRelaysForUser(
    pubkey: "user_pubkey",
    readRelays: ["wss://read1.relay", "wss://read2.relay"],
    writeRelays: ["wss://write1.relay"]
)
```

### 2. NDKRelaySelector
Intelligently selects relays based on context and user preferences.

```swift
// Automatic relay selection for publishing
let result = try await ndk.publishWithOutbox(event)

// Custom configuration
let config = OutboxPublishConfig(
    minSuccessfulRelays: 3,
    maxRetries: 5,
    enablePow: true
)
let result = try await ndk.publishWithOutbox(event, config: config)
```

### 3. NDKPublishingStrategy
Handles publishing with retry logic, POW support, and status tracking.

```swift
// Publish and track status
let result = try await ndk.publishWithOutbox(event)
print("Published to \(result.successCount) relays")

// Check status later
let status = await ndk.publishingStrategy.getPublishResult(for: event.id)
```

### 4. NDKFetchingStrategy
Optimizes event fetching using the outbox model.

```swift
// Fetch with outbox optimization
let events = try await ndk.fetchEventsWithOutbox(
    filter: NDKFilter(authors: ["author1", "author2"], kinds: [1])
)

// Subscribe with outbox model
let subscription = try await ndk.subscribeWithOutbox(
    filters: [filter],
    eventHandler: { event in
        print("Received: \(event.content)")
    }
)
```

## Publishing Flow

1. **Relay Selection**:
   - User's configured write relays
   - Mentioned users' write/read relays  
   - Recommended relays from reply context
   - Fallback to default relays if needed

2. **Publishing Process**:
   - Concurrent publishing to selected relays
   - Automatic retry with exponential backoff
   - POW generation when required
   - NIP-42 authentication support

3. **Status Tracking**:
   - Real-time status updates per relay
   - Overall success/failure tracking
   - Persistent storage of unpublished events

## Fetching Flow

1. **Relay Selection**:
   - User's read relays
   - Authors' read relays (with write relay fallback)
   - Tagged users' relays
   - Contextual relays from filters

2. **Optimization**:
   - Minimizes total relay connections
   - Prioritizes relays serving multiple authors
   - Considers relay health and performance

3. **Subscription Management**:
   - Automatic deduplication
   - Connection pooling
   - Reconnection handling

## Configuration

### Global Configuration

```swift
ndk.outboxConfig = NDKOutboxConfig(
    blacklistedRelays: ["wss://spam.relay"],
    defaultPublishConfig: OutboxPublishConfig(
        minSuccessfulRelays: 2,
        maxRetries: 3,
        enablePow: true,
        maxPowDifficulty: 24
    ),
    defaultFetchConfig: OutboxFetchConfig(
        minSuccessfulRelays: 1,
        maxRelayCount: 10,
        timeoutInterval: 30.0
    ),
    autoRetryFailedPublishes: true,
    retryInterval: 300 // 5 minutes
)
```

### Per-Operation Configuration

```swift
// Publishing
let publishConfig = OutboxPublishConfig(
    minSuccessfulRelays: 3,
    publishInBackground: true
)

// Fetching  
let fetchConfig = OutboxFetchConfig(
    maxRelayCount: 5,
    preferWriteRelaysIfNoRead: true
)
```

## Cache Integration

The outbox model integrates with NDK's cache system for persistence:

```swift
// Use file cache with outbox support
let cache = try NDKFileCache()
let ndk = NDK(cacheAdapter: cache)

// Unpublished events are automatically cached
// and retried on next launch
await ndk.retryFailedPublishes()
```

## Relay Health Tracking

The system tracks relay performance automatically:

```swift
// Manual performance update
await ndk.updateRelayPerformance(
    url: "wss://relay.com",
    success: true,
    responseTime: 0.150
)

// Health metrics are used for relay ranking
let healthScore = await ndk.relayRanker.getRelayHealthScore("wss://relay.com")
```

## Best Practices

1. **Initialize User Relays**: Always track the current user's relay preferences
2. **Handle Missing Relay Info**: Check `missingRelayInfoPubkeys` in selection results
3. **Configure Appropriately**: Adjust min/max relay counts based on your use case
4. **Monitor Performance**: Use relay health tracking to improve reliability
5. **Clean Up Regularly**: Call `cleanupOutbox()` periodically

## Example: Complete Flow

```swift
// Initialize NDK with outbox
let ndk = NDK()
ndk.signer = try NDKPrivateKeySigner(privateKey: privateKey)

// Track current user's relays
let userPubkey = await ndk.signer!.publicKey()
await ndk.setRelaysForUser(
    pubkey: userPubkey,
    readRelays: ["wss://nos.lol", "wss://relay.damus.io"],
    writeRelays: ["wss://nos.lol", "wss://relay.nostr.band"]
)

// Create event with mentions
let event = NDKEvent(
    pubkey: userPubkey,
    kind: 1,
    tags: [["p", "mentioned_user_pubkey"]],
    content: "Hello Nostr!"
)

// Publish with outbox model
let result = try await ndk.publishWithOutbox(event)
print("Published to \(result.successCount)/\(result.relayStatuses.count) relays")

// Fetch replies
let replyFilter = NDKFilter(tags: ["e": [event.id!]], kinds: [1])
let replies = try await ndk.fetchEventsWithOutbox(filter: replyFilter)
```

## Troubleshooting

- **No relays selected**: Ensure users have NIP-65 relay lists or configure fallback relays
- **Publishing failures**: Check relay health scores and blacklist problematic relays
- **Slow fetching**: Reduce `maxRelayCount` or implement pagination
- **Memory usage**: Configure LRU cache size and cleanup intervals