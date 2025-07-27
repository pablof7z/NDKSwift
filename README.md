# NDKSwift

The most feature-complete Swift implementation of the Nostr Development Kit. Build privacy-first, decentralized apps that work offline and sync seamlessly.

## ✨ Why NDKSwift?

**🚀 Local-First Architecture** - Your app works offline. Events publish optimistically and sync when reconnected.

**⚡ Modern Swift** - Built with async/await, AsyncSequence, and actors. No callback hell.

**💾 Smart Caching** - SQLite-powered with full-text search. Apps feel instant.

**💸 Built-in Wallets** - Lightning and Cashu wallets with zaps out of the box.

**📦 Complete Toolkit** - 20+ NIPs implemented. From basic notes to encrypted DMs to file storage.



## 🎯 Features at a Glance

- **Offline-First** - Optimistic publishing with automatic retry
- **Real-time Subscriptions** - Stream events with AsyncSequence
- **Session Data Management** - Reactive filters that auto-update with follow list changes
- **Smart Relay Management** - Automatic reconnection and message routing
- **Integrated Payments** - Lightning & Cashu wallets with nutzaps
- **File Storage** - Blossom protocol for decentralized media
- **Profile Semantic Caching** - 10x faster profile loading with direct column storage
- **Cross-Platform** - iOS, macOS, tvOS, watchOS support

## 📦 Installation

```swift
dependencies: [
    .package(url: "https://github.com/nostr-dev-kit/ndk-swift", from: "0.7.2")
]
```

## 🚀 Quick Start

```swift
import NDKSwift

// Initialize with SQLite cache for offline support
let ndk = NDK(
    relayUrls: ["wss://relay.damus.io", "wss://relay.primal.net"],
    cache: NDKSQLiteCache()
)

// Generate keys and connect
let signer = try NDKPrivateKeySigner.generate()
ndk.signer = signer
await ndk.connect()

// Stream real-time notes
let notes = ndk.observe(filter: NDKFilter(kinds: [1], limit: 50))
for await note in notes.events {
    print("\(note.content)")
}

// Publish (works offline!)
let event = try await NDKEventBuilder(ndk: ndk)
    .content("Hello, Nostr! 🎉")
    .build()
try await ndk.publish(event)
```


## 💡 Cool Things You Can Build

### 🔄 Offline-First Notes
```swift
// Your app works without internet!
let event = try await NDKEventBuilder(ndk: ndk)
    .content("Posted from airplane mode ✈️")
    .build()
try await ndk.publish(event)  // Queued locally, syncs when connected
```

### 🎭 Real-time Social Feed
```swift
// Stream notes with instant updates
let feed = ndk.observe(filter: NDKFilter(kinds: [1]))
for await note in feed.events {
    // New notes appear instantly - no pull-to-refresh needed!
}
```

### ⚡ One-Line Zaps
```swift
// Send Bitcoin instantly over Nostr
try await event.zap(amountSats: 1000, comment: "Great post! ⚡")
```

### 🔐 End-to-End Encrypted DMs
```swift
// Send encrypted messages (NIP-44)
let dm = try await NDKEventBuilder(ndk: ndk)
    .encryptedDirectMessage(to: recipientPubkey, content: "Secret message 🤫")
    .build()
```

### 📸 Decentralized File Storage
```swift
// Upload to Blossom servers
let imageURL = try await ndk.blossom.upload(imageData)
let event = try await NDKEventBuilder(ndk: ndk)
    .content("Check out this photo!")
    .imageAttachment(url: imageURL, blurhash: blurhash)
    .build()
```

## 📋 Supported NIPs

| NIP | Description | Status |
|-----|-------------|---------|
| [01](https://github.com/nostr-protocol/nips/blob/master/01.md) | Basic protocol flow | ✅ |
| [02](https://github.com/nostr-protocol/nips/blob/master/02.md) | Contact List | ✅ |
| [04](https://github.com/nostr-protocol/nips/blob/master/04.md) | Encrypted Direct Messages | ✅ |
| [09](https://github.com/nostr-protocol/nips/blob/master/09.md) | Event Deletion | ✅ |
| [10](https://github.com/nostr-protocol/nips/blob/master/10.md) | Reply Threading | ✅ |
| [18](https://github.com/nostr-protocol/nips/blob/master/18.md) | Reposts | ✅ |
| [19](https://github.com/nostr-protocol/nips/blob/master/19.md) | bech32-encoded entities | ✅ |
| [22](https://github.com/nostr-protocol/nips/blob/master/22.md) | Comments | ✅ |
| [25](https://github.com/nostr-protocol/nips/blob/master/25.md) | Reactions | ✅ |
| [44](https://github.com/nostr-protocol/nips/blob/master/44.md) | Versioned Encryption | ✅ |
| [46](https://github.com/nostr-protocol/nips/blob/master/46.md) | Nostr Connect | ✅ |
| [47](https://github.com/nostr-protocol/nips/blob/master/47.md) | Wallet Connect | ✅ |
| [57](https://github.com/nostr-protocol/nips/blob/master/57.md) | Lightning Zaps | ✅ |
| [60](https://github.com/nostr-protocol/nips/blob/master/60.md) | Cashu Wallet | ✅ |
| [61](https://github.com/nostr-protocol/nips/blob/master/61.md) | Nutzaps | ✅ |
| [65](https://github.com/nostr-protocol/nips/blob/master/65.md) | Relay List (Outbox) | ✅ |
| [77](https://github.com/nostr-protocol/nips/blob/master/77.md) | Negentropy Sync | ✅ |
| [89](https://github.com/nostr-protocol/nips/blob/master/89.md) | App Handlers | ✅ |
| [92](https://github.com/nostr-protocol/nips/blob/master/92.md) | Media Attachments | ✅ |
| [Blossom](https://github.com/hzrd149/blossom) | File Storage | ✅ |

## 📚 Learn More

**Documentation**: [Full docs](Documentation/) including [Getting Started](Documentation/GETTING_STARTED.md), [API Reference](Documentation/API_REFERENCE.md), and [Architecture](Documentation/ARCHITECTURE.md)

**Examples**: Check out the [Examples](Examples/) directory for runnable demos

## 🛠 Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Swift 5.5+
- Xcode 13.0+

## 🤝 Contributing

We welcome contributions! Check out our [Architecture Overview](Documentation/ARCHITECTURE.md) to understand the codebase structure.

## 📄 License

MIT License

## 🔗 Links

- [Nostr Protocol](https://github.com/nostr-protocol/nostr)
- [NDK TypeScript](https://github.com/nostr-dev-kit/ndk)
- [Awesome Nostr](https://github.com/aljazceru/awesome-nostr)
