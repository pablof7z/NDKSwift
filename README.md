# NDKSwift

NDKSwift is a Swift implementation of the Nostr Development Kit, providing a comprehensive toolkit for building Nostr applications on Apple platforms.

## Features

### Core Features
- **Abstract Signers**: Support for multiple signer types (nsec-based, NIP-46, read-only npub mode)
- **Multi-User Sessions**: Active user management and seamless switching between accounts
- **Relay Management**: Automatic connection handling with quadratic backoff, relay pools, and blacklisting
- **Smart Publishing**: Automatic relay selection based on user preferences and Outbox model
- **Offline-First**: Components react to event arrival without loading states
- **Caching**: Adapter-based caching system with in-memory and file-based implementations
- **Advanced Subscription Management**: Intelligent grouping, merging, and EOSE handling for optimal performance
- **NIP-19 Support**: Comprehensive bech32 encoding/decoding for user-friendly identifiers (npub, note, nevent, naddr)
- **Blossom Support**: Full implementation of BUD-01 through BUD-04 for decentralized file storage
- **Payment Integration**: Support for Lightning zaps and Cashu-based payments

### Architecture
- Built with Swift's modern concurrency (async/await, actors)
- Protocol-oriented design for maximum flexibility
- Combine integration for reactive programming
- Thread-safe relay and subscription management

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/pablof7z/NDKSwift.git", from: "0.1.0")
]
```

## Usage

```swift
import NDKSwift

// Initialize NDK
let ndk = NDK()

// Create and set a signer
let signer = NDKPrivateKeySigner(privateKey: "your-nsec-here")
ndk.signer = signer

// Connect to relays
await ndk.connect()

// Subscribe to events
let subscription = ndk.subscribe(
    filters: [
        NDKFilter(kinds: [1], limit: 10)
    ]
)

for await event in subscription {
    print("Received event: \(event)")
}
```

## Key Features

### NIP-19 Identifiers

Work with user-friendly bech32-encoded identifiers:

```swift
// Create user from npub
let user = NDKUser(npub: "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft")

// Get npub from user
print(user.npub) // Automatically encodes to bech32

// Event encoding with context
let noteId = try event.encode() // Simple note1...
let richEventId = try event.encode(includeRelays: true) // nevent1... with relay hints
```

### Advanced Subscription Management

Intelligent subscription optimization automatically improves performance:

```swift
// Subscriptions are automatically grouped and optimized
let subscription = ndk.subscribe(
    filters: [NDKFilter(kinds: [1], authors: ["pubkey"])],
    options: NDKSubscriptionOptions(
        cacheStrategy: .cacheFirst, // Try cache first, then relays
        closeOnEose: false,
        limit: 100
    )
)

// Get performance statistics
let stats = await ndk.getSubscriptionStats()
print("Requests saved through grouping: \(stats.requestsSaved)")
print("Events deduplicated: \(stats.eventsDeduped)")
```

Features:
- **Automatic Grouping**: Similar subscriptions are merged to reduce relay load
- **Event Deduplication**: Prevents duplicate events with 5-minute deduplication window  
- **Smart EOSE Handling**: Dynamic timeouts based on relay responses
- **Cache Strategies**: Multiple cache integration patterns (cache-first, parallel, etc.)
- **Performance Metrics**: Comprehensive statistics for monitoring

## Caching

NDKSwift includes an adapter-based caching system with multiple storage backends:

### In-Memory Cache
Fast, temporary storage that's lost when the app terminates:

```swift
let cache = NDKInMemoryCache()
ndk.cacheAdapter = cache
```

### File Cache
Persistent JSON-based storage that survives app restarts:

```swift
let fileCache = try NDKFileCache(path: "my-app-cache")
ndk.cacheAdapter = fileCache
```

Features:
- Human-readable JSON files for easy debugging
- Thread-safe operations with concurrent reads
- In-memory indexes for fast queries
- Automatic handling of replaceable events (metadata, contacts)
- Support for unpublished events and profiles
- NIP-05 caching with expiration
- Encrypted event storage
- Performance: ~650ms to cache 100 events, ~16ms to query them

Example usage:
```swift
// Initialize with file cache
let cache = try NDKFileCache(path: "nostr-cache")
let ndk = NDK(
    relayUrls: ["wss://relay.damus.io"],
    cacheAdapter: cache
)

// Events are automatically cached as they arrive
let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])])

// Query cached events later
let cachedEvents = await cache.query(subscription: subscription)
```

## Blossom Support

NDKSwift includes full support for the Blossom protocol (BUD-01 through BUD-04) for decentralized file storage:

```swift
// Upload a file to Blossom servers
let imageData = // ... your image data
let blobs = try await ndk.uploadToBlossom(
    data: imageData,
    mimeType: "image/jpeg"
)

// Create an image event with Blossom
let imageEvent = try await NDKEvent.createImageEvent(
    imageData: imageData,
    mimeType: "image/jpeg",
    caption: "Beautiful sunset 🌅",
    ndk: ndk
)

// Use the Blossom client directly
let client = ndk.blossomClient
let blob = try await client.uploadWithAuth(
    data: data,
    mimeType: "application/pdf",
    to: "https://blossom.primal.net",
    signer: signer
)
```

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.9+

## Documentation

- [API Reference](Documentation/API_REFERENCE.md) - Complete API documentation for all NDKSwift classes and protocols
- [iOS App Tutorial](Documentation/IOS_APP_TUTORIAL.md) - Step-by-step guide to building a Nostr iOS app
- [Advanced Usage Guide](Documentation/ADVANCED_USAGE.md) - Advanced patterns and best practices
- [Examples](Examples/README.md) - Working example applications

## License

Same as ndk-core