# NDKSwift

Swift implementation of the Nostr Development Kit for Apple platforms (iOS, macOS, tvOS, watchOS).

## Overview

NDKSwift provides a comprehensive toolkit for building Nostr applications with:
- Local-first architecture with offline support
- Modern Swift concurrency (async/await, AsyncSequence)
- Automatic retry and delivery tracking
- Built-in SQLite caching with full-text search
- Lightning and Cashu wallet integration
- Blossom file storage support

## Features

- **Offline Support**: Optimistic publishing with automatic retry when reconnected
- **Modern Swift**: Async/await, AsyncSequence, and actors for concurrent operations
- **Caching**: SQLite-based event storage with full-text search
- **Wallets**: Lightning (NWC) and Cashu integration with zap support
- **File Storage**: Blossom protocol implementation
- **Type Safety**: Strongly typed APIs with compile-time validation
- **Comprehensive NIP Support**: NIPs 1, 2, 4, 9, 10, 18, 19, 22, 25, 44, 46, 47, 57, 60, 61, 65, 77, 89

## Installation

### Swift Package Manager

Add NDKSwift to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/nostr-dev-kit/ndk-swift", from: "0.6.2")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/nostr-dev-kit/ndk-swift`
3. Select version 0.6.2 or later

## Quick Start

```swift
import NDKSwift

// Initialize with cache for offline support
let cache = NDKSQLiteCache()
let ndk = NDK(
    relayUrls: [
        "wss://relay.damus.io",
        "wss://relay.primal.net", 
        "wss://relay.nostr.band"
    ],
    cache: cache
)

// Set up signer
let signer = try NDKPrivateKeySigner.generate()
ndk.signer = signer

// Configure client tagging (NIP-89)
ndk.clientTagConfig = NDKClientTagConfig(
    name: "MyApp",
    address: "31990:mypubkey:myapp-ios",
    autoTag: true
)

// Subscribe to text notes using declarative API
let dataSource = ndk.observe(
    filter: NDKFilter(kinds: [1], limit: 50),
    maxAge: 0,  // Real-time updates (0 = always fresh)
    cachePolicy: .cacheWithNetwork  // Use cache, then fetch new
)

// Stream events as they arrive
for await event in dataSource.events {
    print("\(event.pubkey): \(event.content)")
}

// Or get current snapshot
let currentEvents = await dataSource.currentValue()

// Publish event (works offline, syncs when connected)
let event = try await ndk.event()
    .content("Hello, Nostr!")
    .build()
try await ndk.publish(event)

// Connect to relays
await ndk.connect()
```


## Core Concepts

### Events

Events are the fundamental data unit in Nostr:

```swift
let event = try await ndk.event()
    .content("Building with NDKSwift!")
    .tags([["t", "nostr"], ["t", "swift"]])
    .build()

// Publish (automatically handled offline with optimistic publishing)
try await ndk.publish(event)

// Retry unpublished events
try await ndk.retryUnpublishedEvents()
```

### Comments (NIP-22)

Reply to any event type with threaded comments:

```swift
// Get blog posts using declarative API
let blogPostsSource = ndk.observe(
    filter: NDKFilter(kinds: [EventKind.longFormContent], limit: 1)
)
let blogPosts = await blogPostsSource.currentValue()

// Create comment when post is available
if let blogPost = blogPosts.first {
    let comment = try await ndk.reply(to: blogPost)
        .content("Great article!")
        .build()
    
    try await ndk.publish(comment)
    
    // Thread replies automatically
    let reply = try await ndk.reply(to: comment)
        .content("I agree!")
        .build()
}

// Subscribe to comments on content
let commentsSource = ndk.observe(
    filter: NDKFilter(
        kinds: [EventKind.genericReply],
        tags: ["A": blogPosts.first.map { [$0.tagAddress] } ?? []]
    )
)

// Stream comments as they arrive
for await comment in commentsSource.events {
    print("New comment: \(comment.content)")
}
```

### Declarative Data Access

NDKSwift provides a modern declarative API for accessing Nostr data with automatic caching and real-time updates:

```swift
// Real-time subscription (maxAge: 0 means always fresh)
let dataSource = ndk.observe(
    filter: NDKFilter(authors: [bobPubkey], kinds: [1]),
    maxAge: 0,  // Always fetch latest
    cachePolicy: .cacheWithNetwork  // Show cached, then update
)

// Stream events as they arrive
for await event in dataSource.events {
    print("New note: \(event.content)")
}

// One-shot fetch with 5-minute cache tolerance
let profiles = ndk.observe(
    filter: NDKFilter(kinds: [0], limit: 100),
    maxAge: 300  // Accept cached data if < 5 minutes old
)
let currentProfiles = await profiles.currentValue()

// Convenience fetch method
let events = await ndk.observe(
    filter: NDKFilter(kinds: [1], limit: 50)
).fetch()

// Cache-only access (no network calls)
let cachedEvents = await ndk.observe(
    filter: NDKFilter(kinds: [1]),
    cachePolicy: .cacheOnly
).fetch()

// SwiftUI Integration
struct NotesView: View {
    let dataSource: NDKDataSource<NDKEvent>
    @State private var notes: [NDKEvent] = []
    
    var body: some View {
        List(notes, id: \.id) { event in
            Text(event.content)
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

// Transform events to custom types  
let userProfiles = ndk.observe(
    filter: NDKFilter(kinds: [0], authors: [pubkey]),
    transform: { event -> NDKUserProfile? in
        try? event.decodeMetadata()
    }
)

// Multiple data sources automatically share subscriptions
// Requests within 100ms are batched for efficiency
let aliceNotes = ndk.observe(
    filter: NDKFilter(authors: [alicePubkey], kinds: [1])
)

let bobProfile = ndk.observe(
    filter: NDKFilter(authors: [bobPubkey], kinds: [0])
)
```

#### Cache Policies

- **`.cacheWithNetwork`** (default): Returns cached data immediately, then fetches fresh data
- **`.cacheOnly`**: Only returns cached data, never hits the network
- **`.networkOnly`**: Always fetches fresh data, ignores cache

#### maxAge Parameter

- **`maxAge: 0`**: Always fetch fresh data (real-time subscription)
- **`maxAge: 300`**: Accept cached data if less than 5 minutes old
- **`maxAge: 3600`**: Accept cached data if less than 1 hour old

### Signers

NDKSwift supports multiple signing methods:

```swift
// Local private key
let signer = try NDKPrivateKeySigner(privateKey: "your-hex-private-key")

// Generate new key
let newSigner = try NDKPrivateKeySigner.generate()

// Remote signing (NIP-46)
let bunkerSigner = NDKBunkerSigner(remotePubkey: "bunker-pubkey", relayUrls: ["wss://relay.example.com"])
```

### Caching

Enable caching for better performance and offline support:

```swift
let cache = NDKSQLiteCache()
let ndk = NDK(relayUrls: relayUrls, cache: cache)

// Events are automatically cached
// Control cache behavior with maxAge and cachePolicy
let dataSource = ndk.observe(
    filter: filter,
    maxAge: 300,  // 5 minute cache tolerance
    cachePolicy: .cacheWithNetwork
)

// Check event confirmation state
let confirmationState = await cache.getEventConfirmationState(eventId: event.id)
switch confirmationState {
case .optimistic:
    // Event pending send
case .partial(let confirmed, let pending):
    // Partially delivered
case .confirmed:
    // Fully delivered
case nil:
    // Not tracked
}

// Monitor unpublished events
let unpublished = try await cache.getUnpublishedEvents(limit: 100)
print("\(unpublished.count) events pending")
```

### Wallets & Payments

NDKSwift provides comprehensive wallet support:

#### Cashu Ecash Wallet (NIP-60)
```swift
// Create a Cashu wallet
let wallet = ndk.createCashuWallet()

// Load wallet state from Nostr events
try await wallet.load()

// Mint tokens from Lightning invoice
try await wallet.mintTokens(amount: 1000, mintURL: "https://mint.example.com")

// Check balance
let balance = try await wallet.getBalance()
print("Balance: \(balance) sats")

// Send a payment
let paymentRequest = NDKPaymentRequest(
    recipient: recipientUser,
    amount: 100,
    comment: "Thanks!"
)
let confirmation = try await wallet.pay(paymentRequest)

// Check relay health (NIP-60)
let health = await wallet.getRelayHealth()
for relay in health {
    if !relay.isHealthy {
        try await wallet.repairRelay(relay.relay, missingEventIds: relay.missingEvents)
    }
}
```

#### NWC (Nostr Wallet Connect)
```swift
// Connect to a Lightning wallet via NWC
let nwcWallet = try NDKNWCWallet(
    uri: "nostr+walletconnect://...",
    ndk: ndk
)

// Pay an invoice
let invoice = "lnbc1000n1..."
let payment = try await nwcWallet.payInvoice(invoice)
```

#### Zaps (NIP-57 & NIP-61)
```swift
// Configure zap manager with wallets
ndk.zapManager.configureDefaults(
    wallet: cashuWallet,  // For nutzaps
    nwcWallet: nwcWallet  // For Lightning zaps
)

// Zap a user
let zapResult = try await user.zap(
    amountSats: 1000,
    comment: "Great post!",
    preferredType: .nutzap  // or .lightning
)

// Zap an event
let eventZap = try await event.zap(
    amountSats: 500,
    comment: "⚡"
)

// Subscribe to zaps on an event
let zapsSource = ndk.observe(
    filter: NDKFilter(
        kinds: [EventKind.zap],
        tags: ["e": [event.id]]
    ),
    maxAge: 0  // Real-time zap notifications
)

// Stream zaps as they arrive
for await zap in zapsSource.events {
    print("New zap: \(zap.amountSats ?? 0) sats")
}
```

#### Client Identification (NIP-89)
```swift
// Configure client tagging
ndk.clientTagConfig = NDKClientTagConfig(
    name: "MyApp",
    address: "31990:mypubkey:myapp-ios",
    autoTag: true,
    excludedKinds: [4] // Exclude DMs
)

// Events include client tags automatically
let event = try await ndk.event()
    .content("Hello from MyApp!")
    .build()

// Extract client info
if let clientTag = event.clientTag {
    print("Client: \(clientTag.name)")
}

// Create handler info
let handler = try await ndk.event()
    .nip89HandlerInfo(
        identifier: "myapp-ios",
        supportedKinds: [1, 6, 7],
        handlerURLs: ["ios": "myapp://event/<bech32>"]
    )
    .build()
```

## Supported NIPs

- **NIP-01** (Basic protocol flow description)
- **NIP-02** (Contact List and Petnames)
- **NIP-04** (Encrypted Direct Messages - deprecated)
- **NIP-09** (Event Deletion)
- **NIP-10** (Conventions for clients' use of e and p tags in text events)
- **NIP-18** (Reposts)
- **NIP-19** (bech32-encoded entities)
- **NIP-22** (Event kind 1111 - Comments)
- **NIP-25** (Reactions)
- **NIP-44** (Versioned Encryption)
- **NIP-46** (Nostr Connect - Remote Signing)
- **NIP-47** (Wallet Connect)
- **NIP-57** (Lightning Zaps)
- **NIP-60** (Cashu Wallet)
- **NIP-61** (Nutzaps)
- **NIP-65** (Relay List Metadata - Outbox Model)
- **NIP-77** (Negentropy - Set Reconciliation)
- **NIP-89** (Recommended Application Handlers)
- **Blossom** (Decentralized file storage protocol)

## Documentation

Comprehensive documentation is available in the [Documentation](Documentation/) directory:

- [Getting Started Guide](Documentation/GETTING_STARTED.md) - Step-by-step introduction
- [Local-First Philosophy](Documentation/LOCAL_FIRST.md) - Why local-first matters for Nostr
- [API Reference](Documentation/API_REFERENCE.md) - Complete API documentation
- [Examples](Documentation/EXAMPLES.md) - Practical code examples
- [Architecture Overview](Documentation/ARCHITECTURE.md) - System design and patterns
- [Optimistic Publishing](Documentation/OPTIMISTIC_PUBLISHING.md) - Deep dive into offline features
- [NIP-77 Implementation](Documentation/NIP77Implementation.md) - Negentropy sync protocol details

## Examples

The [Examples](Examples/) directory contains runnable demos:

- `SimpleDemo.swift` - Basic usage example
- `StandaloneDemo.swift` - Self-contained demo (no compilation needed)
- `OptimisticPublishingDemo.swift` - Offline publishing and retry demonstration
- `NWCDemo.swift` - Wallet integration example
- `BlossomDemo.swift` - File storage example
- `OutboxDemo.swift` - Outbox model demonstration
- `CashuDemo.swift` - Cashu wallet example
- `ZapDemo.swift` - Lightning and Nutzap examples

Run examples directly:
```bash
swift Examples/StandaloneDemo.swift
```

Or compile and run:
```bash
swift run --package-path Examples SimpleDemo
```

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Swift 5.5+
- Xcode 13.0+

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) and check the [Architecture Overview](Documentation/ARCHITECTURE.md) before submitting PRs.

## License

NDKSwift is released under the MIT License. See [LICENSE](LICENSE) for details.

## Links

- [Nostr Protocol](https://github.com/nostr-protocol/nostr) - The protocol NDKSwift implements
- [NDK (TypeScript)](https://github.com/nostr-dev-kit/ndk) - The original NDK implementation
- [Awesome Nostr](https://github.com/aljazceru/awesome-nostr) - Curated list of Nostr resources