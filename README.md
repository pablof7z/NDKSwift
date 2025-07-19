# NDKSwift

**Build unstoppable, local-first Nostr applications that work everywhere - even offline.**

NDKSwift is a modern Swift implementation of the Nostr Development Kit for Apple platforms. It embraces the local-first philosophy, ensuring your applications remain fast, resilient, and respectful of user autonomy - whether online, offline, or anything in between.

## Why NDKSwift?

### 🚀 Local-First by Design
Your data lives on your device first. Write a note on a plane, in a subway, or during an outage - NDKSwift ensures it reaches the world when it can. No spinners. No "connection failed" errors. Just instant, responsive software that respects your autonomy.

### 🔐 True Data Ownership  
With Nostr + NDKSwift, your social identity lives in your pocket, not on someone's server. Export it, back it up, move it between apps. Your followers, your content, your rules. No platform can delete your account or censor your voice.

### ⚡ Lightning Fast
Zero network latency for your own actions. Post instantly. Like instantly. Reply instantly. The network syncs in the background while your users experience native app performance.

## Core Features

- **Local-First Architecture**: Everything works offline - posts, likes, profiles, search
- **Optimistic Publishing**: Events appear immediately in local UI, sync when online
- **Automatic Retry**: Smart exponential backoff ensures your content always reaches relays
- **Progressive Sync**: Honest UI shows delivery status (sending → partial → confirmed)
- **Modern Swift**: Async/await, AsyncSequence, and actors for elegant concurrent code
- **Comprehensive NIPs**: Extensive protocol support including outbox model (NIP-65) and client identification (NIP-89)
- **Built-in Caching**: SQLite-powered local storage with full-text search
- **Wallet Integration**: Lightning (NWC) and Cashu support for seamless payments
- **Decentralized Storage**: Blossom protocol for censorship-resistant file hosting
- **Client Identification**: Automatic client tagging and application discovery (NIP-89)
- **Type Safety**: Strongly typed APIs prevent common errors at compile time

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

// Create a local-first Nostr app in seconds
let cache = NDKSQLiteCache() // Your personal Nostr database
let ndk = NDK(
    relayUrls: [
        "wss://relay.damus.io",
        "wss://relay.primal.net", 
        "wss://relay.nostr.band"
    ],
    cache: cache  // Enables local-first superpowers
)

// Generate your identity (or use existing keys)
let signer = try NDKPrivateKeySigner.generate()
ndk.signer = signer

// Configure client identification (NIP-89)
ndk.clientTagConfig = NDKClientTagConfig(
    name: "MyApp",
    address: "31990:mypubkey:myapp-ios", // Optional
    autoTag: true
)

// Subscribe to notes - works even offline!
let subscription = ndk.subscribe(filters: [
    NDKFilter(kinds: [1], limit: 50)
])

// Process events from cache AND network seamlessly
for await event in subscription {
    // Events flow from:
    // 1. Local cache (instant)
    // 2. Optimistic updates (instant) 
    // 3. Network relays (when connected)
    print("\(event.pubkey): \(event.content)")
}

// Publish instantly - even on airplane mode!
let event = NDKEvent(content: "Hello, decentralized world! 🌍")
try await ndk.publish(event)
// ✓ Appears immediately in local UI
// ✓ Syncs to relays when online
// ✓ Retries automatically if needed

// Connect when you want (or don't - it still works!)
await ndk.connect()
```

## The Local-First Advantage

Building with NDKSwift means your users get:

### 🚄 Subway-Proof Social
No more "No Internet Connection" errors. Your users can browse, post, and interact whether they're underground, in-flight, or in a remote cabin. The conversation continues uninterrupted.

### 🛡️ Censorship Immunity  
When your data lives locally first, no platform, government, or corporation can delete it. Users own their social graph, their content, and their identity. Truly unstoppable applications.

### ⚡ Native App Performance
Forget loading spinners. Every action feels instant because it IS instant. The network becomes an enhancement, not a dependency. Your app feels as fast as native because it runs like native.

### 🔄 Seamless Sync
NDKSwift handles the complexity of distributed systems. Events sync across devices and relays automatically. Conflicts resolve naturally. Your code stays simple while your app stays resilient.

## Core Concepts

### Events

Events are the fundamental data unit in Nostr:

```swift
let event = NDKEvent(
    content: "Building with NDKSwift!",
    tags: [["t", "nostr"], ["t", "swift"]]
)

// Sign and publish - works even when offline!
try await ndk.publish(event)
// ✓ Event appears instantly in local subscriptions
// ✓ Automatically retries when connectivity is restored
// ✓ Tracks confirmation state across all relays

// Configure optimistic publishing behavior
ndk.optimisticPublishingConfig.enabled = true // default
ndk.optimisticPublishingConfig.cacheUnpublishedEvents = true
ndk.optimisticPublishingConfig.dispatchToSubscriptions = true

// Manually retry unpublished events if needed
try await ndk.retryUnpublishedEvents()
```

### Subscriptions

Subscribe to events using modern AsyncSequence patterns:

```swift
// Real-time subscription (receives optimistic events immediately)
let subscription = ndk.subscribe(filters: [
    NDKFilter(authors: [bobPubkey], kinds: [1])
])

for await event in subscription {
    // Process each event as it arrives (including optimistic events!)
    // You can check event confirmation state if needed
}

// Skip optimistic events if desired
var options = NDKSubscriptionOptions()
options.skipOptimisticEvents = true
let strictSubscription = ndk.subscribe(filters: [filter], options: options)

// Control subscription grouping delay (default: 100ms)
// Multiple subscriptions within this window may be merged into a single relay request
let sub1 = await ndk.subscribe(filters: [filter], groupingDelay: 0.2)  // 200ms delay
let sub2 = await ndk.subscribe(filters: [filter], groupingDelay: 0)    // No grouping

// One-shot fetch
let events = try await ndk.fetchEvents(
    NDKFilter(kinds: [0], authors: [alicePubkey])
)
```

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
// Unpublished events are stored and retried when online
// Deletion events (NIP-09) are automatically processed
// Queries check cache first
let cachedEvents = try await ndk.fetchEvents(filter, useCache: true)

// Check event confirmation state (for UI feedback)
let confirmationState = await cache.getEventConfirmationState(eventId: event.id)
switch confirmationState {
case .optimistic:
    // Show "sending..." indicator - event will retry automatically
case .partial(let confirmed, let pending):
    // Show "sent to \(confirmed.count) of \(confirmed.count + pending.count) relays"
case .confirmed:
    // Show "sent ✓" indicator
case nil:
    // Event not found or no tracking
}

// Monitor offline events
let unpublishedCount = try await cache.getUnpublishedEvents(limit: 100).count
if unpublishedCount > 0 {
    print("\(unpublishedCount) events waiting to be sent")
}
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

// Monitor relay health (NIP-60 relay tags)
let health = await wallet.getRelayHealth()
for relay in health {
    print("Relay \(relay.relay.url): \(relay.isHealthy ? "✅" : "❌")")
    if !relay.isHealthy {
        print("  Missing: \(relay.missingEvents.count) events")
        print("  Extra: \(relay.extraEvents.count) stale events")
    }
}

// Repair unhealthy relays by republishing missing events
for relay in health.filter({ !$0.isHealthy }) {
    try await wallet.repairRelay(relay.relay, missingEventIds: relay.missingEvents)
    print("Repaired relay: \(relay.relay.url)")
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

// Fetch zaps
let zaps = try await event.fetchZaps(includeNutzaps: true)
```

#### Client Identification (NIP-89)
```swift
// Configure automatic client tagging
ndk.clientTagConfig = NDKClientTagConfig(
    name: "MyApp",
    address: "31990:mypubkey:myapp-ios", // Optional
    autoTag: true,
    excludedKinds: [4] // Exclude DMs for privacy
)

// All published events now include client tags automatically
let event = try await ndk.event()
    .content("Hello from MyApp!")
    .build() // Includes: ["client", "MyApp", "31990:mypubkey:myapp-ios"]

// Or configure with just client name for simple identification
ndk.clientTagConfig = NDKClientTagConfig(
    name: "MyApp",
    autoTag: true
) // Creates: ["client", "MyApp"]

// Extract client info from events
if let clientTag = event.clientTag {
    print("Published by: \(clientTag.name)")
    if let address = clientTag.address {
        print("Handler: \(address)")
    }
}

// Create handler info to advertise your app
let handler = try await ndk.event()
    .nip89HandlerInfo(
        identifier: "myapp-ios",
        supportedKinds: [1, 6, 7], // Text, reposts, reactions
        handlerURLs: ["ios": "myapp://event/<bech32>"]
    )
    .build()
```

## Supported NIPs

NDKSwift implements the following Nostr Implementation Possibilities:

### Core Protocol
- **NIP-01**: Basic protocol flow description
- **NIP-02**: Contact List and Petnames
- **NIP-09**: Event Deletion
- **NIP-10**: Conventions for clients' use of e and p tags in text events (with pubkey hints, supports "a" tags for addressable events)
- **NIP-18**: Reposts
- **NIP-19**: bech32-encoded entities
- **NIP-25**: Reactions
- **NIP-65**: Relay List Metadata (Outbox Model)
- **NIP-89**: Recommended Application Handlers (Client Identification)

### Encryption & Security
- **NIP-04**: Encrypted Direct Messages (deprecated, use NIP-44)
- **NIP-44**: Versioned Encryption
- **NIP-46**: Nostr Connect (Remote Signing)

### Payments & Wallet
- **NIP-47**: Wallet Connect
- **NIP-57**: Lightning Zaps
- **NIP-60**: Cashu Wallet
- **NIP-61**: Nutzaps

### Negentropy
- **NIP-77**: Negentropy Protocol for efficient set reconciliation

### Storage & Files
- **Blossom**: Decentralized file storage protocol


### Additional Features
- Content tagging and parsing
- Relay pool management
- Event caching and persistence
- Subscription management with AsyncSequence

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