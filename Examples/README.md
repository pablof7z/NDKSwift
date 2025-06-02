# NDKSwift Examples

This directory contains example applications and demonstrations of NDKSwift functionality.

## Examples

### 📖 StandaloneDemo.swift
A comprehensive API demonstration that shows all major NDKSwift features and usage patterns. This is a self-contained demo that doesn't require compilation.

**Run it:**
```bash
swift Examples/StandaloneDemo.swift
```

**Features demonstrated:**
- Bech32 encoding/decoding (npub, nsec, note)
- Event creation, validation, and signing
- Filtering and subscription patterns
- Relay connection management
- User profile handling
- Caching strategies
- High-level convenience APIs

### 📱 BasicUsage.swift
Shows basic usage patterns for NDKSwift models and simple operations. Good starting point for understanding the core concepts.

### 🚀 NostrDemoMain.swift
A comprehensive console application that demonstrates real-world usage patterns. This is a compiled executable that shows all major NDKSwift features.

### 🧪 SimpleDemoMain.swift
A minimal demo showing key functionality in a simple format. This is a compiled executable for quick testing.

### 💾 FileCacheDemo.swift
Comprehensive demonstration of the file-based cache adapter, showing persistent storage, querying, profile management, and performance testing.

### 🌸 BlossomDemo.swift
Complete demonstration of Blossom protocol support including:
- File upload to Blossom servers
- Server discovery (BUD-01)
- Upload with authorization (BUD-02)
- List and delete operations (BUD-03, BUD-04)
- Integration with Nostr events (NIP-94 file metadata)
- Image event creation with automatic Blossom upload

## Running the Examples

### Quick Start
The easiest way to see NDKSwift in action:

```bash
# Run the standalone API demo (no compilation needed)
swift Examples/StandaloneDemo.swift

# Or run the full test suite to see everything working
swift test
```

### Building and Running Compiled Examples
To build and run the compiled examples:

```bash
# Navigate to Examples directory
cd Examples

# Build the examples
swift build

# Run SimpleDemo
./.build/debug/SimpleDemo

# Run NostrDemo (comprehensive demo)
./.build/debug/NostrDemo

# Run FileCacheDemo (cache demonstration)
./.build/debug/FileCacheDemo
```

### Alternative: Run from Root Directory
```bash
# From NDKSwift root directory
swift run --package-path Examples SimpleDemo
swift run --package-path Examples NostrDemo
swift run --package-path Examples FileCacheDemo
```

## What You'll See

The examples demonstrate NDKSwift's capabilities:

### ✅ Working Features
- **Bech32 Encoding**: Full npub/nsec/note support
- **Event Handling**: Creation, validation, signing
- **Subscriptions**: Callback-based and async stream APIs
- **Relay Connections**: WebSocket with auto-reconnection
- **Cross-Platform**: Works on Linux and Apple platforms
- **Caching**: In-memory cache with adapter pattern
- **User Profiles**: Complete profile management
- **Comprehensive Testing**: 74/84 tests passing (88%)

### 🚧 Planned Features
- SQLite cache adapter
- Outbox model (NIP-65) support
- NIP-46 remote signing
- Additional signer types

## Test Results
Current test status shows excellent functionality:

- **Bech32Tests**: 9/9 tests ✅
- **NDKEventTests**: 8/8 tests ✅  
- **NDKFilterTests**: 9/9 tests ✅
- **NDKSubscriptionTests**: 16/16 tests ✅
- **NDKUserTests**: 8/8 tests ✅
- **Overall**: 74/84 tests passing (88% success rate)

## API Highlights

### Basic Usage
```swift
import NDKSwift

// Initialize NDK
let ndk = NDK(relayUrls: ["wss://relay.damus.io"])

// Create events
let event = NDKEvent(
    pubkey: "your_pubkey",
    createdAt: Timestamp(Date().timeIntervalSince1970),
    kind: EventKind.textNote,
    content: "Hello Nostr!"
)

// Subscribe to events
let filter = NDKFilter(kinds: [1], limit: 20)
let subscription = ndk.subscribe(filters: [filter])

subscription.onEvent { event in
    print("Received: \(event.content)")
}
```

### Bech32 Support
```swift
// Encode/decode npub
let npub = try Bech32.npub(from: pubkey)
let pubkey = try Bech32.pubkey(from: npub)

// Encode/decode nsec
let nsec = try Bech32.nsec(from: privateKey)
let privateKey = try Bech32.privateKey(from: nsec)
```

### Async Streams
```swift
for await event in subscription.eventStream() {
    print("Event: \(event.content)")
}
```

## Contributing

When adding new examples:

1. Keep them focused on specific functionality
2. Include error handling where appropriate
3. Add comments explaining key concepts
4. Test your examples before committing
5. Update this README with new examples

## Support

- Run `swift test` to verify functionality
- Check test output for current implementation status
- See main README.md for full project documentation