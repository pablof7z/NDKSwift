# Getting Started with NDKSwift

This guide will help you get up and running with NDKSwift in your iOS, macOS, tvOS, or watchOS app.

## Installation

### Swift Package Manager

In Xcode:

1. Go to **File → Add Package Dependencies**
2. Enter the repository URL: `https://github.com/nostr-dev-kit/ndk-swift`
3. Select version 0.6.1 or later
4. Click **Add Package**

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nostr-dev-kit/ndk-swift", from: "0.6.1")
]
```

## Basic Usage

### 1. Import and Initialize

```swift
import NDKSwift

// Create NDK instance with relay URLs
let ndk = NDK(relayUrls: [
    "wss://relay.damus.io",
    "wss://relay.primal.net",
    "wss://relay.nostr.band"
])

// Connect to relays
await ndk.connect()
```

### 2. Subscribe to Events

NDKSwift uses modern AsyncSequence for subscriptions:

```swift
// Subscribe to text notes (kind 1)
let subscription = ndk.subscribe(filters: [
    NDKFilter(kinds: [1], limit: 20)
])

// Process events as they arrive
for await event in subscription {
    print("New note from \(event.pubkey): \(event.content)")
}
```

### 3. Fetch Events (One-time Query)

For one-time queries, use the fetch methods:

```swift
// Fetch user profile
let user = ndk.getUser(npub: "npub1...")
let profile = try await user?.fetchProfile()

// Fetch recent notes
let events = try await ndk.fetchEvents(
    NDKFilter(kinds: [1], limit: 10)
)

// Fetch specific event
let event = try await ndk.fetchEvent("note1...")
```

### 4. Publish Events

To publish events, you need a signer:

```swift
// Generate a new key pair
let signer = try NDKPrivateKeySigner.generate()
ndk.signer = signer

// Create and publish an event
let event = NDKEvent(
    content: "Hello, Nostr! 🎉",
    tags: [["t", "introductions"]]
)

let publishedToRelays = try await ndk.publish(event)
print("Published to \(publishedToRelays.count) relays")
```

## Key Concepts

### Events

Events are the core data structure in Nostr:

```swift
// Create event with full control
let event = NDKEvent(
    pubkey: signer.publicKey,
    createdAt: Timestamp(Date().timeIntervalSince1970),
    kind: 1,  // Text note
    tags: [
        ["p", "recipient-pubkey"],  // Mention someone
        ["t", "swift"],             // Add hashtag
    ],
    content: "Building with #swift on Nostr!"
)

// Events are automatically signed when published
try await ndk.publish(event)
```

### Filters

Filters define what events you want to receive:

```swift
// Filter by author
let authorFilter = NDKFilter(
    authors: ["pubkey1", "pubkey2"],
    kinds: [1]  // Text notes only
)

// Filter by time range
let timeFilter = NDKFilter(
    kinds: [1],
    since: Timestamp(Date().timeIntervalSince1970 - 3600),  // Last hour
    limit: 50
)

// Filter by tags
var tagFilter = NDKFilter(kinds: [1])
tagFilter.addTagFilter("t", values: ["bitcoin", "lightning"])
```

### Users

Work with Nostr users:

```swift
// Get user by public key
let user = ndk.getUser("hex-pubkey")

// Or by npub
let user = ndk.getUser(npub: "npub1...")

// Fetch their profile
let profile = try await user?.fetchProfile()
print("Name: \(profile?.name ?? "Unknown")")
print("About: \(profile?.about ?? "")")

// Get who they follow
let following = try await user?.follows()
```

### Signers

NDKSwift supports multiple signing methods:

```swift
// Private key signer (local)
let signer = try NDKPrivateKeySigner(privateKey: "hex-private-key")

// Or from nsec
let signer = try NDKPrivateKeySigner(nsec: "nsec1...")

// Remote signer (NIP-46 Bunker)
let bunkerSigner = NDKBunkerSigner(
    remotePubkey: "bunker-service-pubkey",
    relayUrls: ["wss://relay.nsecbunker.com"]
)
```

## Common Patterns

### Real-time Chat

```swift
// Subscribe to a chat channel
let chatSub = ndk.subscribe(filters: [
    NDKFilter(
        kinds: [42],  // Live chat message
        tags: ["e": Set(["chat-room-id"])]
    )
])

for await message in chatSub {
    let author = ndk.getUser(message.pubkey)
    print("\(author?.displayName ?? "Unknown"): \(message.content)")
}
```

### Profile Updates

```swift
// Update your profile
let profileEvent = NDKEvent(
    kind: 0,  // Metadata
    content: """
    {
        "name": "Alice",
        "about": "Building on Nostr with Swift",
        "picture": "https://example.com/avatar.jpg",
        "nip05": "alice@example.com"
    }
    """
)

try await ndk.publish(profileEvent)
```

### Reply to Events

```swift
// Create a reply
let originalEvent = try await ndk.fetchEvent("note1...")
let reply = originalEvent?.createReply(
    content: "Great post! 👍",
    mentionAuthor: true
)

if let reply = reply {
    try await ndk.publish(reply)
}
```

### Reactions

```swift
// React to an event
let reaction = try await event.react(content: "🔥", publish: true)
```

## Best Practices

### 1. Error Handling

Always handle errors appropriately:

```swift
do {
    let events = try await ndk.fetchEvents(filter)
    // Process events
} catch NDKError.timeout {
    print("Request timed out")
} catch NDKError.relayError(let message) {
    print("Relay error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

### 2. Subscription Management

Close subscriptions when done to free resources:

```swift
let subscription = ndk.subscribe(filters: [filter])

// Use the subscription
for await event in subscription {
    // Process events
    if shouldStop {
        break
    }
}

// Subscription automatically closes when loop exits
// Or explicitly close:
await subscription.close()
```

### 3. Enable Caching

Use caching for better performance:

```swift
let cache = try NDKSQLiteCache()
let ndk = NDK(
    relayUrls: relayUrls,
    cache: cache
)

// Queries will check cache first
let events = try await ndk.fetchEvents(filter, useCache: true)
```

### 4. Relay Configuration

Choose relays appropriate for your use case:

```swift
// General purpose relays
let generalRelays = [
    "wss://relay.damus.io",
    "wss://relay.primal.net",
    "wss://relay.nostr.band"
]

// Paid relays (better quality/reliability)
let paidRelays = [
    "wss://relay.nostr.wine",
    "wss://eden.nostr.land"
]

// Geographic relays
let regionalRelays = [
    "wss://nostr-pub.wellorder.net",  // US
    "wss://nostr.mom",                 // EU
    "wss://relay.nostr.wirednet.jp"   // Asia
]
```

### 5. Cashu Wallet Integration (NIP-60/61)

NDKSwift includes built-in support for Cashu wallets:

```swift
// Initialize Cashu wallet
let cashuWallet = NDKCashuWallet(signer: signer, ndk: ndk)
await cashuWallet.connect()

// Check balance
let balance = await cashuWallet.totalBalance

// Send a nutzap (NIP-61)
let recipient = ndk.getUser(pubkey: "recipientPubkey")
let nutzap = try await cashuWallet.nutzap(
    amount: 100,
    comment: "Great post!",
    recipient: recipient,
    eventId: "eventToZap"
)

// Mint new tokens
let mintQuote = try await cashuWallet.mintQuote(amount: 1000)
// Pay the Lightning invoice...
let tokens = try await cashuWallet.mint(quote: mintQuote)
```

## Next Steps

- Check out the [API Reference](API_REFERENCE.md) for detailed documentation
- See [Examples](EXAMPLES.md) for more code samples
- Learn about [Architecture](ARCHITECTURE.md) for advanced usage
- Explore the [Examples directory](../Examples/) for runnable demos

## Troubleshooting

### Connection Issues

If relays aren't connecting:

```swift
// Enable debug mode
ndk.debugMode = true

// Monitor relay connections
for await relay in ndk.pool.relays {
    print("Relay \(relay.url): \(relay.connectionState)")
}
```

### Event Not Publishing

Check that:
1. You have a signer configured
2. At least one relay is connected
3. The event is valid

```swift
// Verify setup
guard ndk.signer != nil else {
    print("No signer configured!")
    return
}

let connectedRelays = ndk.pool.connectedRelays()
print("Connected to \(connectedRelays.count) relays")

// Validate event before publishing
try event.validate()
```

### Performance Issues

For large-scale applications:

```swift
// Limit concurrent subscriptions
let options = NDKSubscriptionOptions(
    limit: 100,
    timeout: 30.0
)

// Use specific relays for queries
let fastRelays = Set([relay1, relay2])
let events = try await ndk.fetchEvents(
    filter,
    relays: fastRelays
)

// Enable signature verification sampling
let ndk = NDK(
    relayUrls: relayUrls,
    signatureVerificationConfig: NDKSignatureVerificationConfig(
        samplingRate: 0.1  // Verify 10% of signatures
    )
)
```