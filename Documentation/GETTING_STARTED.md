# Getting Started with NDKSwift

This guide will help you get up and running with NDKSwift in your iOS, macOS, tvOS, or watchOS app.

## Important: Use Built-in Components

Before implementing custom solutions, check if NDKSwift already provides what you need:

- **Profile Management**: Use `NDKProfileManager` directly instead of creating wrappers
- **UI Components**: Import `NDKSwiftUI` for ready-made components like `NDKProfilePicture`, `NDKDisplayName`, etc.
- **Hex/Npub/Nsec Conversions**: Use built-in `Bech32` utilities and `String` extensions
- **Relay Management**: Use NDK's built-in relay management instead of custom implementations

## Installation

### Swift Package Manager

In Xcode:

1. Go to **File → Add Package Dependencies**
2. Enter the repository URL: `https://github.com/nostr-dev-kit/ndk-swift`
3. Select version 0.7.6 or later
4. Click **Add Package**

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nostr-dev-kit/ndk-swift", from: "0.7.6")
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
let textNotesSource = ndk.subscribe(
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
    let dataSource: NDKSubscription<NDKEvent>
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

Use the fetch and subscribe APIs with different strategies:

```swift
// Get user profile using ProfileManager (recommended)
let user = ndk.getUser(npub: "npub1...")!
for await metadata in await ndk.profileManager.subscribe(for: user.pubkey, maxAge: TimeConstants.hour) {
    if let metadata = metadata {
        print("Name: \(metadata.displayName ?? metadata.name ?? "Unknown")")
    }
    break  // If you only need the current profile
}

// Stream recent notes
for await event in ndk.subscribe(filter: NDKFilter(kinds: [1], limit: 10)).events {
    print("Note: \(event.content)")
}

// Subscribe to real-time updates using subscribe API
let dataSource = ndk.subscribe(
    filter: NDKFilter(kinds: [1], limit: 10),
    maxAge: 0  // Real-time updates
)
for await event in dataSource.events {
    print("New event: \(event.content)")
}

// Get specific event by ID
let eventSource = ndk.subscribe(
    filter: NDKFilter(ids: ["eventId..."]),
    cachePolicy: .networkOnly  // Skip cache entirely
)
let events = await eventSource.collect(timeout: 5.0)
let event = events.first

// Cache-only access for offline support
let cachedNotes = ndk.subscribe(
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
// Create event using builder pattern (recommended)
let event = try await NDKEventBuilder()
    .content("Building with #swift on Nostr!")
    .kind(1)  // Text note
    .tag(["p", "recipient-pubkey"])  // Mention someone
    .tag(["t", "swift"])             // Add hashtag
    .build(signer: ndk.signer!)

// Publish the signed event
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

// Fetch profile using NDKProfileManager (recommended approach)
// The profile manager is built into NDK - no need to create one
if let user = user {
    // This returns cached data immediately if available, then fetches fresh data
    for await profile in await ndk.profileManager.subscribe(for: user.pubkey, maxAge: TimeConstants.hour) {
        if let profile = profile {
            print("Name: \(profile.displayName ?? profile.name ?? "Unknown")")
            print("About: \(profile.about ?? "")")
        }
        break  // If you only need the profile once
    }
    
    // For continuous profile updates (e.g., on a profile page)
    for await profile in await ndk.profileManager.subscribe(for: user.pubkey, maxAge: 0) {
        // This will keep the subscription open and yield updates
        updateUI(with: profile)
    }
    
    // Get who they follow
    let contactsSource = ndk.subscribe(
        filter: NDKFilter(kinds: [3], authors: [user.pubkey])
    )
    
    let contactEvents = await contactsSource.collect(timeout: 5.0)
    if let contactEvent = contactEvents.first {
        let following = contactEvent.taggedUsers()
        print("Following \(following.count) users")
    }
}
```

### Identifier Conversions (Hex/Npub/Nsec)

NDKSwift provides complete support for all Nostr identifier formats. **Never implement your own conversion functions:**

```swift
// Convert hex pubkey to npub
let npub = try String.toNpub(hexPubkey)
let hexPubkey = try String.fromNpub(npub)

// Work with private keys
let signer = try NDKPrivateKeySigner(nsec: "nsec1...")
let nsec = try signer.nsec  // Get nsec from signer
let npub = try signer.npub  // Get npub from signer

// Event ID conversions
let noteId = try Bech32.note(from: eventId)
let eventId = try Bech32.eventId(from: noteId)

// Complex identifiers
let nevent = try Bech32.nevent(
    eventId: event.id,
    relays: ["wss://relay.damus.io"],
    author: event.pubkey
)

// Validation
if hexString.isValid32ByteHex { /* valid pubkey */ }
if Bech32.isBech32(inputString) { /* valid bech32 */ }
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
let chatSource = ndk.subscribe(
    filter: NDKFilter(
        kinds: [42],  // Live chat message
        tags: ["e": Set(["chat-room-id"])]
    ),
    maxAge: 0  // Real-time messages
)

for await message in chatSource.events {
    let author = ndk.getUser(message.pubkey)
    // Fetch profile if needed
    if let metadata = await ndk.profileManager.getCachedProfile(for: message.pubkey) {
        print("\(metadata.displayName ?? metadata.name ?? "Unknown"): \(message.content)")
    } else {
        print("\(message.pubkey.prefix(8))...: \(message.content)")
    }
}
```

### Profile Updates

```swift
// Update your profile
let profileData = [
    "name": "Alice",
    "about": "Building on Nostr with Swift",
    "picture": "https://example.com/avatar.jpg",
    "nip05": "alice@example.com"
]

let profileEvent = try await NDKEventBuilder()
    .kind(0)  // Metadata
    .content(JSONCoding.encode(profileData))
    .build(signer: ndk.signer!)

try await ndk.publish(profileEvent)
```

### Reply to Events

```swift
// Fetch the original event
let eventSource = ndk.subscribe(
    filter: NDKFilter(ids: ["eventId..."])
)

let events = await eventSource.collect(timeout: 5.0)
if let originalEvent = events.first {
    // Create a reply
    let reply = originalEvent.createReply(
        content: "Great post! 👍",
        mentionAuthor: true
    )
    
    // Sign and publish
    let signedReply = try await NDKEventBuilder(ndk: ndk)
        .event(reply)
        .build(signer: ndk.signer!)
    
    try await ndk.publish(signedReply)
}
```

### Reactions

```swift
// React to an event (using NDK interaction methods)
try await ndk.react(to: event, with: "🔥")

// Or use the event methods directly
let reaction = try await event.react(with: "🔥", signer: ndk.signer!, ndk: ndk)
try await ndk.publish(reaction)

// Like/dislike shortcuts
try await ndk.like(event)     // + reaction
try await ndk.dislike(event)  // - reaction
```

## Best Practices

### 1. Error Handling

Always handle errors appropriately:

```swift
do {
    let dataSource = ndk.subscribe(filter: filter)
    
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
let dataSource = ndk.subscribe(
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
// - No more subscribers are active
```

### 3. Enable Caching

Use caching for better performance:

```swift
let cache = try await NDKSQLiteCache(path: nil)
let ndk = NDK(
    relayUrls: relayUrls,
    cache: cache
)

// Queries will check cache first (cache is used by default)
for await event in ndk.subscribe(filter: filter).events {
    // Process events from cache and network
}
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
// Initialize Cashu wallet (NIP-60)
let cashuWallet = NIP60Wallet(ndk: ndk)
await cashuWallet.connect()

// Check balance
let balance = await cashuWallet.totalBalance

// Send a nutzap (NIP-61)
let recipient = ndk.getUser("recipientPubkey")
let nutzapRequest = NutzapRequest(
    recipient: recipient,
    amount: 100,
    comment: "Great post!",
    eventId: "eventToZap"
)
let nutzap = try await cashuWallet.pay(nutzapRequest)

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
let relays = await ndk.relays
for relay in relays {
    let state = await relay.connectionState
    print("Relay \(relay.url): \(state)")
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

let (connected, total) = await ndk.getRelayConnectionSummary()
print("Connected to \(connected) of \(total) relays")

// Validate event before publishing
try event.validate()
```

### Performance Issues

For large-scale applications:

```swift
// Use specific relays for queries
let fastRelays = Set(["wss://relay1.com", "wss://relay2.com"])
for await event in ndk.subscribe(
    filter: filter,
    relays: fastRelays,
    exclusiveRelays: true  // Only use specified relays
).events {
    print("Event from fast relay: \(event.content)")
}

// Enable signature verification sampling
let ndk = NDK(
    relayUrls: relayUrls,
    signatureVerificationConfig: NDKSignatureVerificationConfig(
        samplingRate: 0.1  // Verify 10% of signatures
    )
)
```