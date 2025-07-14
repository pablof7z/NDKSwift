# NDKSwift

A modern Swift implementation of the Nostr Development Kit for Apple platforms (iOS, macOS, tvOS, watchOS).

NDKSwift provides a comprehensive toolkit for building Nostr applications with Swift, featuring modern async/await patterns, type safety, and seamless integration with Apple's ecosystem.

## Features

- **Modern Swift Design**: Built with async/await, AsyncSequence, and actors for thread-safe concurrency
- **Comprehensive NIP Support**: Extensive protocol coverage (see supported NIPs below)
- **Flexible Architecture**: Protocol-oriented design allowing custom implementations
- **Outbox Model**: Intelligent relay selection and event routing (enabled by default)
- **Built-in Caching**: Optional caching with SQLite implementation
- **Wallet Integration**: Nostr Wallet Connect (NWC) support for payments
- **File Storage**: Blossom protocol support for decentralized file storage
- **Type Safety**: Strongly typed events, filters, and relay management

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

// Create NDK instance
let ndk = NDK(relayUrls: [
    "wss://relay.damus.io",
    "wss://relay.primal.net",
    "wss://relay.nostr.band"
])

// Connect to relays
await ndk.connect()

// Subscribe to text notes
let subscription = ndk.subscribe(filters: [
    NDKFilter(kinds: [1], limit: 10)
])

// Process events using AsyncSequence
for await event in subscription {
    print("\(event.pubkey): \(event.content)")
}

// Publish an event
let signer = try NDKPrivateKeySigner.generate()
ndk.signer = signer

let event = NDKEvent(content: "Hello, Nostr!", tags: [])
try await ndk.publish(event)
```

## Core Concepts

### Events

Events are the fundamental data unit in Nostr:

```swift
let event = NDKEvent(
    content: "Building with NDKSwift!",
    tags: [["t", "nostr"], ["t", "swift"]]
)

// Sign and publish
try await ndk.publish(event)
```

### Subscriptions

Subscribe to events using modern AsyncSequence patterns:

```swift
// Real-time subscription
let subscription = ndk.subscribe(filters: [
    NDKFilter(authors: [bobPubkey], kinds: [1])
])

for await event in subscription {
    // Process each event as it arrives
}

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

Enable caching for better performance:

```swift
let cache = NDKSQLiteCache()
let ndk = NDK(relayUrls: relayUrls, cache: cache)

// Events are automatically cached
// Queries check cache first
let cachedEvents = try await ndk.fetchEvents(filter, useCache: true)
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

## Supported NIPs

NDKSwift implements the following Nostr Implementation Possibilities:

### Core Protocol
- **NIP-01**: Basic protocol flow description
- **NIP-02**: Contact List and Petnames
- **NIP-09**: Event Deletion
- **NIP-10**: Reply conventions
- **NIP-18**: Reposts
- **NIP-19**: bech32-encoded entities
- **NIP-25**: Reactions
- **NIP-65**: Relay List Metadata (Outbox Model)

### Encryption & Security
- **NIP-04**: Encrypted Direct Messages (deprecated, use NIP-44)
- **NIP-44**: Versioned Encryption
- **NIP-46**: Nostr Connect (Remote Signing)

### Payments & Wallet
- **NIP-47**: Wallet Connect
- **NIP-57**: Lightning Zaps
- **NIP-60**: Cashu Ecash Wallet
- **NIP-61**: Nutzaps

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
- [API Reference](Documentation/API_REFERENCE.md) - Complete API documentation
- [Examples](Documentation/EXAMPLES.md) - Practical code examples
- [Architecture Overview](Documentation/ARCHITECTURE.md) - System design and patterns

## Examples

The [Examples](Examples/) directory contains runnable demos:

- `SimpleDemo.swift` - Basic usage example
- `StandaloneDemo.swift` - Self-contained demo (no compilation needed)
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