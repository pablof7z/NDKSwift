# NDKSwift

NDKSwift is a Swift implementation of the Nostr Development Kit, providing a comprehensive toolkit for building Nostr applications on Apple platforms.

## Features

### Core Features
- **Abstract Signers**: Support for multiple signer types (nsec-based, NIP-46, read-only npub mode)
- **Multi-User Sessions**: Active user management and seamless switching between accounts
- **Relay Management**: Automatic connection handling with quadratic backoff, relay pools, and blacklisting
- **Smart Publishing**: Automatic relay selection based on user preferences and Outbox model
- **Offline-First**: Components react to event arrival without loading states
- **Caching**: Adapter-based caching system with SQLite implementation
- **Subscription Grouping**: Intelligent merging of similar subscriptions for efficiency
- **Blossom Support**: Full implementation of BUD-01 through BUD-04 for decentralized file storage

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