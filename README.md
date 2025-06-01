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

### Architecture
- Built with Swift's modern concurrency (async/await, actors)
- Protocol-oriented design for maximum flexibility
- Combine integration for reactive programming
- Thread-safe relay and subscription management

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/NDKSwift.git", from: "0.1.0")
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

## Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.9+

## License

Same as ndk-core