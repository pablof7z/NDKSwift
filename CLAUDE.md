# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

NDKSwift is a Swift implementation of the Nostr Development Kit, providing a toolkit for building Nostr applications on Apple platforms (iOS, macOS, tvOS, watchOS). It follows the architecture patterns of the original NDK while being idiomatic to Swift.

## Build and Development Commands

### Building
```bash
# Build the main library
swift build

# Build with release optimizations
swift build -c release

# Build examples (from Examples directory)
cd Examples && swift build
```

### Testing
```bash
# Run all tests
swift test

# Run tests with verbose output
swift test --verbose

# Run a specific test
swift test --filter NDKEventTests

# Run tests in parallel
swift test --parallel
```

### Running Examples
```bash
# Run standalone demo (no compilation needed)
swift Examples/StandaloneDemo.swift

# Run compiled examples
swift run --package-path Examples SimpleDemo
swift run --package-path Examples NostrDemo
swift run --package-path Examples FileCacheDemo
swift run --package-path Examples BlossomDemo
```

### Package Management
```bash
# Update dependencies
swift package update

# Resolve dependencies
swift package resolve

# Generate Xcode project
swift package generate-xcodeproj
```

### Building iOS Apps (Examples/Apps)

For iOS apps that use XcodeGen (project.yml):

```bash
# Always regenerate project after adding/removing files
cd Examples/Apps/Highlighter
./refresh-project.sh

# Build with clean output using xcbeautify
./build.sh

# Custom build configurations
DESTINATION="platform=iOS Simulator,name=iPhone 16 Pro" ./build.sh
CONFIGURATION=Release ./build.sh

# Manual commands if needed
xcodegen generate
xcodebuild -project Highlighter.xcodeproj -scheme Highlighter -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build | xcbeautify
```

#### Code Signing Configuration

The project.yml files now include code signing settings. You can either:
1. Set the DEVELOPMENT_TEAM environment variable: `export DEVELOPMENT_TEAM=YOUR_TEAM_ID`
2. Or hardcode your team ID in the project.yml file

This ensures code signing persists across project regenerations.

## Architecture Overview

### Core Architecture Patterns

1. **Protocol-Oriented Design**: The codebase heavily uses protocols (NDKSigner, NDKCache, NDKWallet) to allow multiple implementations and testing flexibility.

2. **Actor-Based Concurrency**: Key components like NDKPool, NDKOutboxManager, and BlossomClient use Swift actors for thread-safe state management. This requires understanding Swift's async/await patterns.

3. **Event-Driven Architecture**: The system revolves around NDKEvent objects that flow through relays, subscriptions, and caches. Events are immutable once signed.

4. **Relay Pool Pattern**: Multiple relay connections are managed by NDKPool, which handles automatic reconnection, relay selection, and message routing.

5. **AsyncStream-Based Subscriptions**: Subscriptions use Swift's AsyncStream for modern, composable event streaming that integrates naturally with async/await.

### Key Architectural Components

**NDK Core Flow**:
- `NDK` → `NDKPool` → `NDKRelayConnection` → WebSocket
- Events flow bidirectionally through this chain
- Subscriptions filter incoming events through NDKDataSource
- Cache interceptors store events in NDKSQLiteCache

**Relay-Level Subscription Grouping** (matches ndk-core):
- Each relay has its own `NDKRelaySubscriptionManager`
- Subscriptions with the same fingerprint are grouped into `NDKRelaySubscriptionGroup`
- Groups execute with configurable delays (default 100ms) to batch subscriptions
- Filter merging happens at execution time on each relay
- Filters with limits are concatenated, filters without limits have their values merged

**Event Processing Flow**:
- Events → `NDKSubscriptionManager.processEvent()` → `NDKDataSource.handleEvent()` → Cache
- Kind 5 deletion events are automatically processed by `NDKSubscriptionManager`
- Referenced events are removed from cache with proper NIP-09 author validation
- Only the original author can delete their own events
- Database transactions ensure atomic deletion operations

**Signer Architecture**:
- `NDKSigner` protocol defines signing interface
- `NDKPrivateKeySigner` implements local signing
- Events must be signed before publishing
- Signers are async to support future remote signing (NIP-46)

**Cache System**:
- `NDKCache` protocol allows pluggable storage
- `NDKSQLiteCache` for persistent storage with migrations
- `MemoryCache` for in-memory caching with LRU eviction
- Caches handle events, profiles, and wallet data

**Blossom Integration**:
- `BlossomClient` handles file upload/download
- Authorization uses Nostr events (kind 24242)
- Integrates with NDK through extension methods
- Supports multi-server uploads with fallback

### Cross-Component Interactions

1. **Event Publishing Flow**:
   - Create NDKEvent → Sign with NDKSigner → Publish through NDK → RelayPool broadcasts → Cache stores

2. **Subscription Flow (AsyncSequence)**:
   - Create NDKFilter → Subscribe through NDK → Returns AsyncSequence
   - DataRequirement manages deduplication and relay selection
   - NDKDataSource added to relay's subscription manager
   - Multiple subscriptions with same fingerprint grouped together
   - Groups execute after delay, merging filters into single REQ
   - Events arrive → Routed to all subscriptions in group → Cache stores → Yield to iterator

3. **One-Shot Fetch Flow**:
   - Create NDKFilter → Call fetchEvents/fetchEvent → Subscribe with closeOnEose → Collect events → Return when EOSE received

4. **User Profile Loading**:
   - Call fetchProfile() → Creates metadata filter → Fetches events → Parses JSON → Returns NDKUserProfile

**Filter Fingerprinting and Grouping**:
- Fingerprints based on filter structure (which fields are present)
- Time constraints (since/until) included in fingerprint
- closeOnEose subscriptions prefixed with '+' to separate from continuous subscriptions
- Filters with same fingerprint can be merged at relay level

5. **Blossom File Upload**:
   - Data → Calculate SHA256 → Create auth event → Upload to Blossom → Create file metadata event → Publish to Nostr

## Testing Approach

- Unit tests use XCTest with async/await support
- Mock implementations (MockURLSession, MockRelay) for network testing
- Test files mirror source structure in Tests/NDKSwiftTests/
- Each major component has comprehensive tests
- Blossom tests use MockURLSession to avoid network dependencies

## Development Notes

- The codebase uses Timestamp (Int64) for Unix timestamps consistently
- Event IDs are lowercase hex strings
- All public keys are hex encoded (not npub)
- Relay URLs are normalized using URLNormalizer (adds trailing slashes, strips auth, removes www, etc. - matches ndk-core)
- SQLite cache uses GRDB.swift for persistent storage
- Blossom support is implemented as an extension to NDK core
- JSON encoding/decoding should always use JSONCoding utility for consistency

## Subscription API Design

### Modern Swift Patterns

The subscription system uses modern Swift patterns for cleaner, more intuitive code:

1. **AsyncSequence for Continuous Streams**:
   ```swift
   // Modern pattern - self-explanatory and composable
   for await event in subscription {
       handleEvent(event)
   }
   ```

3. **No Callback Hell**: The API avoids nested callbacks in favor of linear async/await code

4. **Automatic Resource Management**: Subscriptions clean up when their AsyncSequence completes

### Design Rationale

- **Fetch vs Subscribe**: Clear distinction between one-time data needs (fetch) and ongoing updates (subscribe)
- **AsyncSequence**: Natural fit for event streams, integrates with Swift concurrency
- **Backward Compatibility**: Deprecated callback methods still work but guide users to modern patterns
- **Auto-Start**: Subscriptions start automatically when iteration begins, reducing boilerplate

## Development Guidelines

- Always add and update a changelog file
- When making changes, decide to change version number and which level of semantic version to change
  - Major version (X.0.0): Breaking changes or significant rewrites
  - Minor version (0.X.0): New features or substantial improvements
  - Patch version (0.0.X): Bug fixes, performance improvements, small refactors

## Claude's Responsibilities

- You are also in charge of keeping the documentation and tutorial information highly in line with implementation and best practices
- When refactoring APIs, ensure examples and tests are updated to use the new patterns
- Prefer modern Swift patterns (async/await, AsyncSequence) over callback-based APIs
- Guide users toward best practices through API design and clear deprecation messages

## Examples and Demos

The repository includes various standalone examples and feature demos in the `Examples/` directory:

- **GettingStarted/**: Basic examples for learning NDKSwift
- **Features/**: Specific feature demonstrations (OutboxDebugger, DebugKind0Fetcher, etc.)
- **Scripts/**: Testing scripts and utilities
- **StandaloneDemo.swift**: Simple runnable demo
- **NIP60Wallet.swift**: Cashu wallet integration example

To run examples:
```bash
# Run standalone demo (no compilation needed)
swift Examples/StandaloneDemo.swift

# Run feature demos
swift run --package-path Examples SimpleDemo
swift run --package-path Examples NostrDemo
swift run --package-path Examples FileCacheDemo
swift run --package-path Examples BlossomDemo
```

## Important Development Principles

- Prefer clean code over backward compatibility - avoid leaving code that needs refactoring later
- Use deprecation warnings when changing APIs to guide users
- Always use NDKLogger for logging instead of print statements in production code
- Centralize JSON operations through JSONCoding utility for consistency
- Follow the "never wait, always stream" pattern for data operations

## Claude Memories

- Every time you finish doing significant work, ask Gemini for a code-review; explain what the intended task was and any significant notes plus the files you worked on. To ask for the review use command: `vibe-tools repo "<prompt>"`
