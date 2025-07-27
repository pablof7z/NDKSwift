# Getting Started with NDKSwift

This guide will help you get up and running with NDKSwift in your iOS, macOS, tvOS, or watchOS app.

## Installation

### Swift Package Manager

In Xcode:

1. Go to **File → Add Package Dependencies**
2. Enter the repository URL: `https://github.com/nostr-dev-kit/ndk-swift`
3. Select version 0.7.3 or later
4. Click **Add Package**

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nostr-dev-kit/ndk-swift", from: "0.7.3")
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

NDKSwift uses a modern declarative data access pattern with automatic caching:

```swift
// Subscribe to text notes (kind 1) with real-time updates
let textNotesSource = ndk.observe(
    filter: NDKFilter(kinds: [1], limit: 20),
    maxAge: 0,  // Always fetch fresh data
    cachePolicy: .cacheWithNetwork  // Show cached first, then update
)

// Stream events as they arrive
Task {
    for await event in textNotesSource.events {
        print("New note: \(event.content)")
    }
}

// Or collect all events (waits for EOSE)
let currentNotes = await textNotesSource.collect(timeout: 10.0)

// Use in SwiftUI views
struct NotesView: View {
    let dataSource: NDKDataSource<NDKEvent>
    @State private var notes: [NDKEvent] = []
    
    var body: some View {
        List(notes, id: \.id) { event in
            Text("Note from \(event.pubkey): \(event.content)")
        }
        .task {
            // Update UI on main thread
            for await event in dataSource.events {
                await MainActor.run {
                    notes.append(event)
                }
            }
        }
    }
}
```

### 3. Access Specific Data

Use the observe API with different cache strategies:

```swift
// Get user profile with transformation
let user = ndk.getUser(npub: "npub1...")
let profileSource = ndk.observe(
    filter: NDKFilter(kinds: [0], authors: [user.pubkey]),
    maxAge: 3600,  // Cache valid for 1 hour
    transform: { event -> NDKUserProfile? in
        try? event.decodeMetadata()
    }
)

// Get the profile (waits for EOSE or timeout)
let profiles = await profileSource.collect(timeout: 5.0)
if let profile = profiles.first {
    print("Name: \(profile.name ?? "Unknown")")
}

// Access recent notes with 5-minute cache
let recentNotesSource = ndk.observe(
    filter: NDKFilter(kinds: [1], limit: 10),
    maxAge: 300  // Accept cached data up to 5 minutes old
)

// Get specific event by ID (always fresh)
let eventSource = ndk.observe(
    filter: NDKFilter(ids: ["eventId..."]),
    maxAge: 0,  // Always fetch from relays
    cachePolicy: .networkOnly  // Skip cache entirely
)

// Cache-only access for offline support
let cachedNotes = ndk.observe(
    filter: NDKFilter(kinds: [1]),
    cachePolicy: .cacheOnly  // Never hit network
)
```

#### Understanding Cache Parameters

- **maxAge**: How old cached data can be before fetching fresh
  - `0`: Always fetch fresh (real-time)
  - `300`: 5 minutes
  - `3600`: 1 hour
  - `86400`: 1 day

- **cachePolicy**: How to balance cache vs network
  - `.cacheWithNetwork`: Return cache immediately, then fetch updates
  - `.cacheOnly`: Only use cache, no network calls
  - `.networkOnly`: Always fetch fresh, ignore cache

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
    createdAt: Timestamp.now,
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
    since: Timestamp.now - 3600,  // Last hour
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

// Fetch their profile using observe API
if let user = user {
    let profileSource = ndk.observe(
        filter: NDKFilter(kinds: [0], authors: [user.pubkey]),
        maxAge: 3600  // 1 hour cache
    )
    
    let events = await profileSource.collect(timeout: 5.0)
    if let profile = try? events.first?.decodeMetadata() {
        print("Name: \(profile.name ?? "Unknown")")
        print("About: \(profile.about ?? "")")
    }
    
    // Get who they follow
    let contactsSource = ndk.observe(
        filter: NDKFilter(kinds: [3], authors: [user.pubkey])
    )
    
    let contactEvents = await contactsSource.collect(timeout: 5.0)
    if let contactEvent = contactEvents.first {
        let following = contactEvent.referencedPubkeys()
        print("Following \(following.count) users")
    }
}
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
let chatSource = ndk.observe(
    filter: NDKFilter(
        kinds: [42],  // Live chat message
        tags: ["e": Set(["chat-room-id"])]
    ),
    maxAge: 0  // Real-time messages
)

for await message in chatSource.events {
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
// Fetch the original event
let eventSource = ndk.observe(
    filter: NDKFilter(ids: ["eventId..."])
)

let events = await eventSource.collect(timeout: 5.0)
if let originalEvent = events.first {
    // Create a reply using the builder
    let reply = try await NDKEventBuilder.reply(to: originalEvent, ndk: ndk)
        .content("Great post! 👍")
        .build()
    
    try await ndk.publish(reply)
}
```

### Reactions

```swift
// React to an event
let reaction = try await NDKEventBuilder(ndk: ndk)
    .kind(EventKind.reaction)
    .content("🔥")
    .tag(["e", event.id])
    .tag(["p", event.pubkey])
    .build()

try await ndk.publish(reaction)
```

## Best Practices

### 1. Error Handling

Always handle errors appropriately:

```swift
do {
    let dataSource = ndk.observe(filter: filter)
    
    // For streaming
    for await event in dataSource.events {
        // Process events
    }
    
    // Or collect all events (waits for EOSE)
    let events = await dataSource.collect(timeout: 10.0)
    // Process events
} catch {
    print("Error: \(error)")
}
```

### 2. Subscription Management

Data sources automatically manage their lifecycle:

```swift
// Create a data source
let dataSource = ndk.observe(
    filter: filter,
    maxAge: 0  // Real-time
)

// Use in a task - automatically cleans up
Task {
    for await event in dataSource.events {
        // Process events
        if shouldStop {
            break  // Automatically closes subscription
        }
    }
}

// The subscription is managed internally and closes when:
// - The AsyncSequence iteration ends
// - The DataSource is deallocated
// - No more observers are active
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

// Monitor relay health (NIP-60 relay tags)
let health = await cashuWallet.getRelayHealth()
print("Wallet relays: \(health.filter { $0.isHealthy }.count)/\(health.count) healthy")

// Auto-repair unhealthy relays
for relay in health.filter({ !$0.isHealthy }) {
    try await cashuWallet.repairRelay(relay.relay, missingEventIds: relay.missingEvents)
}
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