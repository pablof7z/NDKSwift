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

## Architecture Overview

### Core Architecture Patterns

1. **Protocol-Oriented Design**: The codebase heavily uses protocols (NDKSigner, NDKCacheAdapter, NDKWallet) to allow multiple implementations and testing flexibility.

2. **Actor-Based Concurrency**: Key components like NDKRelayPool, NDKFileCache, and BlossomClient use Swift actors for thread-safe state management. This requires understanding Swift's async/await patterns.

3. **Event-Driven Architecture**: The system revolves around NDKEvent objects that flow through relays, subscriptions, and caches. Events are immutable once signed.

4. **Relay Pool Pattern**: Multiple relay connections are managed by NDKRelayPool, which handles automatic reconnection, relay selection, and message routing.

### Key Architectural Components

**NDK Core Flow**:
- `NDK` → `NDKRelayPool` → `NDKRelayConnection` → WebSocket
- Events flow bidirectionally through this chain
- Subscriptions (`NDKSubscription`) filter incoming events
- Cache adapters intercept events for storage

**Signer Architecture**:
- `NDKSigner` protocol defines signing interface
- `NDKPrivateKeySigner` implements local signing
- Events must be signed before publishing
- Signers are async to support future remote signing (NIP-46)

**Cache System**:
- `NDKCacheAdapter` protocol allows pluggable storage
- `NDKInMemoryCache` for temporary storage
- `NDKFileCache` for persistent JSON-based storage
- Caches handle both events and user profiles

**Blossom Integration**:
- `BlossomClient` handles file upload/download
- Authorization uses Nostr events (kind 24242)
- Integrates with NDK through extension methods
- Supports multi-server uploads with fallback

### Cross-Component Interactions

1. **Event Publishing Flow**:
   - Create NDKEvent → Sign with NDKSigner → Publish through NDK → RelayPool broadcasts → Cache stores

2. **Subscription Flow**:
   - Create NDKFilter → Subscribe through NDK → RelayPool sends REQ → Events arrive → Filter matches → Cache stores → Subscription receives

3. **User Profile Loading**:
   - NDKUser.fetchProfile() → Creates metadata filter → Subscribes → Receives kind 0 event → Parses and caches profile

4. **Blossom File Upload**:
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
- File-based cache uses JSON for human readability
- Blossom support is implemented as an extension to NDK core

## Development Guidelines

- Always add and update a changelog file
- When making changes, decide to change version number and which level of semantic version to change
  - Major version (X.0.0): Breaking changes or significant rewrites
  - Minor version (0.X.0): New features or substantial improvements
  - Patch version (0.0.X): Bug fixes, performance improvements, small refactors

## Claude's Responsibilities

- You are also in charge of keeping the documentation and tutorial information highly in line with implementation and best practices

UUIDs are stupid and should never be used in the context of nostr.

- Unless otherwise specified, backward compatibility is not necessary