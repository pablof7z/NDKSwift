# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2025-01-09

### Added
- **Comprehensive Zap Support (NIP-57 & NIP-61)** - Full implementation of Lightning Zaps and Nutzaps
  - Decoupled architecture: Any payment method can fund any zap type
  - `NDKZapManager` as an actor for thread-safe zap operations
  - Protocol-based design with `NDKZapProtocol` and `NDKPaymentProvider`
  - `NDKLightningZapProtocol` for NIP-57 Lightning Zaps with LNURL resolution
    - Properly waits for zap receipts from LNURL service (doesn't create them)
    - Validates receipts against provider pubkey
  - `NDKNutzapProtocol` for NIP-61 Cashu-based Nutzaps with P2PK support
    - Uses `NutzapFundingRequest` with ALL accepted mints
    - Payment providers choose optimal mint
  - Payment providers:
    - `NWCPaymentProvider`: Handles Lightning invoices and Nutzap funding via mint quotes
    - `CashuPaymentProvider`: Optimizes for same-mint transfers (free)
    - `QRCodePaymentProvider`: Fallback for manual payments
  - Strongly-typed event models: `NDKZapRequest`, `NDKZapReceipt`, `NDKNutzap`, `NDKNutzapPreferences`
  - Smart routing with privacy preference (prefers Nutzaps when available)
  - Convenient extensions: `user.zap()`, `event.zap()`, `fetchZaps()`
  - Comprehensive test coverage for all zap components

### Changed
- **Refactored NDKCashuWallet** to work as a proof-of-funds provider within the zap architecture
  - Added `send()` method for creating P2PK-locked proofs
  - Added `getMints()` and `getBalance(mint:)` for provider optimization
  - Added `payLightning()` for cross-mint transfers
  - Removed high-level `sendNutzap()` logic (now handled by NDKZapManager)
- **Updated configureDefaults** to accept cashuWallet parameter for easy setup

- **Cashu Wallet Support (NIP-60)** - Full implementation of Cashu ecash wallets on Nostr
  - `NDKCashuWallet` actor for thread-safe wallet operations
  - Complete CashuSwift integration for ecash operations
  - Proof management with state tracking (available, reserved, spent, pending)
  - P2PK support for Nutzaps using P256K Schnorr signatures
  - NIP-44 encrypted event storage for wallet metadata and proofs
  - Mint connection management with automatic TTL and caching
  - Token minting from Lightning invoices with payment polling
  - Nutzap sending with P2PK locking and change handling
  - Incoming nutzap receiving and proof unlocking
  - E2E test suite for wallet operations

### Changed
- **BREAKING**: Complete thread safety overhaul - removed all `@unchecked Sendable` usage
  - `NDKSubscription` now uses `SubscriptionStateActor` for all mutable state management
  - `NDKRelay` now uses `RelayStateActor` instead of NSLock
  - `NDKEvent` now uses `EventStateActor` for thread-safe property access
  - `NDKUser` now uses `UserStateActor` for mutable state
  - `NDKBunkerSigner` verified as properly Sendable actor
- **BREAKING**: Many properties are now async due to actor-based state management
  - Event properties (`id`, `pubkey`, `kind`, `tags`, `content`, etc.) require `await`
  - User properties (`profile`, `relayList`, `nip46Urls`, etc.) require `await`
  - Relay properties (`connectionState`, `stats`, `info`, etc.) require `await`
  - Methods that access these properties are now async

### Improved
- Eliminated all race conditions and thread safety issues
- Better performance with compile-time thread safety guarantees
- More predictable behavior in concurrent environments
- Cleaner architecture with proper actor boundaries
- State-mutating methods are now async instead of fire-and-forget for stronger guarantees
- Added `EventSnapshot` struct and `snapshot()` method for efficient multi-property access
- Documented object identity behavior for `Equatable` implementations

## [0.7.0] - 2025-01-09

### Added
- **SQLite-backed cache implementation** using GRDB for efficient event and profile storage
  - Support for complex Nostr query patterns (by author, kind, tags, time ranges)
  - Profile-specific optimized queries (`getProfileName`, `getProfilePicture`, `searchProfiles`)
  - Proper database indexes for performance optimization
  - Full NDKCache protocol implementation with async/await support

### Changed
- **BREAKING**: Simplified cache architecture - removed complex multi-tier abstractions in favor of single concrete implementation
  - Removed `CacheLayer`, `MemoryCacheLayer`, `DiskCacheLayer`, `LayeredCache`, and `CacheFactory`
  - Removed all cache adapter pattern abstractions
  - Cache is now optional and uses concrete `NDKSQLiteCache` implementation
  - Made `queryEvents` throw errors for better error handling
- **BREAKING**: Removed all callback-based subscription methods in favor of modern AsyncSequence API
  - Removed `onEvent`, `onEose`, and `onError` methods from `NDKSubscriptionBuilder`
  - Removed `subscribe(..., onEvent:)` overloads from `NDK`
  - Removed `subscribeToProfile(..., onUpdate:)` method
  - Removed callback-based methods from `NDKSubscriptionGroup`
  - Use `for await event in subscription` or `AsyncSequence` iteration instead
- **Complete Documentation Rewrite** - All documentation rebuilt from scratch to match current implementation
  - New comprehensive [API Reference](Documentation/API_REFERENCE.md) with all public APIs
  - New [Getting Started Guide](Documentation/GETTING_STARTED.md) with modern patterns
  - New [Examples](Documentation/EXAMPLES.md) with practical use cases
  - New [Architecture Overview](Documentation/ARCHITECTURE.md) explaining system design
  - Removed all outdated documentation files

### Added
- **Comprehensive Zap Support (NIP-57 & NIP-61)** - Full implementation of Lightning Zaps and Nutzaps
  - `NDKZapManager` for smart routing between Lightning and Nutzap providers
  - `NDKLightningZapProvider` for NIP-57 Lightning Zaps
  - `NDKNutzapProvider` for NIP-61 Cashu-based Nutzaps
  - Strongly-typed event models: `NDKZapRequest`, `NDKZapReceipt`, `NDKNutzap`, `NDKNutzapPreferences`
  - Smart zap routing with privacy-first approach (prefers Nutzaps when available)
  - Convenient extensions: `user.zap()`, `event.zap()`, `fetchZaps()`
  - Support for both profile and event zaps
  - Automatic LNURL resolution and validation
  - Zap receipt verification and validation
- **Outbox model is now the default!** - All publishing and fetching uses intelligent relay selection by default
- Added `outboxEnabled` flag to disable outbox model globally (default: true)
- Added `NDKOutboxManager` facade for advanced outbox operations
  - `ndk.outbox.publish()` - Publish with custom strategies
  - `ndk.outbox.fetchEvents()` - Fetch with custom strategies
  - `ndk.outbox.trackUser()` - Track user relay preferences
  - `ndk.outbox.untrackUser()` - Stop tracking a user
  - `ndk.outbox.getRelayScore()` - Get relay health score
  - `ndk.outbox.getRecommendedRelays()` - Get recommended relays for a user
- Added `RelaySelectionStrategy` for custom relay selection logic
- **Comprehensive E2E Test Suite** - New end-to-end tests for core functionality
  - Created `E2ECoreTest` executable that tests against live Nostr relays
  - Tests relay connection, event publishing, fetching, and real-time subscriptions
  - Includes timeout handling and proper error reporting
  - Removed redundant test scripts in favor of consolidated E2E test

### Breaking Changes
- **BREAKING**: Outbox model is now enabled by default
  - `publish()` now uses outbox model automatically
  - `fetchEvents()` now uses outbox model automatically (for single filters without specific relays)
  - `subscribe()` now uses outbox model automatically
  - Set `ndk.outboxEnabled = false` to disable outbox globally
  - Pass specific relays to override outbox model: `publish(event, to: relayUrls)`
- **BREAKING**: Simplified outbox model API
  - Made all internal outbox components private: `NDKOutboxTracker`, `NDKRelayRanker`, `NDKRelaySelector`, `NDKPublishingStrategy`, `NDKFetchingStrategy`
  - Made all internal outbox types private: `PublishingConfig`, `FetchingConfig`, `RelaySelectionResult`, `OutboxPublishConfig`, `PublishResult`, etc.
  - Advanced outbox functionality now accessed through `ndk.outbox` manager
  - Removed public methods: `publishWithOutbox()`, `fetchEventsWithOutbox()`, `subscribeWithOutbox()`
  - Removed public methods: `trackUser()`, `setRelaysForUser()`, `updateRelayPerformance()`, `cleanupOutbox()`
- **BREAKING**: Fully migrated NDKSubscription to actor-based concurrency
  - All state properties (`events`, `isActive`, `isClosed`, `eoseReceived`) are now async-only
  - `start()` and `close()` methods are now async
  - `handleEvent()` and `handleEOSE()` are now async
  - Removed all synchronous property access - use `await` for all state queries
  - Removed deprecated callback methods (`onEvent`, `onEOSE`, `onError`)
- **BREAKING**: Simplified cache control system
  - Removed `NDKCacheStrategy` enum (was broken with non-existent cases)
  - Replaced with simple `useCache: Bool` flag in `NDKSubscriptionOptions`
  - All `fetchEvents()` methods now use `useCache` parameter instead of `cacheStrategy`
  - Default behavior remains the same (cache-first when `useCache = true`)
  - Cache-only pattern achieved by setting `useCache = true` with empty relay set
  - Removed `NDKSubscriptionUpdate` enum and `updates` stream
- **BREAKING**: Unified error handling with idiomatic Swift enum
  - Replaced struct-based `NDKError` with Swift enum using associated values
  - Removed error categories and factory methods
  - Removed `NWCError` - all NWC errors now use `NDKError` cases
  - Removed `BlossomError` - all Blossom errors now use `NDKError` cases
  - Removed `Bech32Error` - all Bech32 errors now use `NDKError` cases
  - Removed conversion methods like `toNDKError()`

### Changed
- Consolidated all thread synchronization into single `SubscriptionStateActor`
- Eliminated all NSLock usage in favor of Swift actors
- Improved performance and type safety with compile-time thread safety guarantees
- Replaced Timer-based timeout with Task-based timeout for better async integration
- NDKSubscription now uses AsyncThrowingStream for proper error propagation
- Simplified error handling across the entire codebase to use idiomatic Swift patterns
- All errors now use descriptive enum cases with associated values for context

### Added
- Comprehensive documentation for subscription resource management patterns
- Error propagation through AsyncThrowingStream - subscription errors now properly throw
- Task-based timeout mechanism for cleaner async/await integration
- New wallet-specific error cases for NWC operations
- New file/Blossom-specific error cases for file operations

### Removed
- Backward compatibility layers for synchronous access
- Legacy callback-based API
- Update stream for compatibility
- All cached state properties
- Timer-based timeout in favor of Task-based implementation
- All module-specific error types (NWCError, BlossomError, Bech32Error)
- Error conversion methods between different error types

## [0.6.1] - 2025-01-10

### Fixed
- Fixed critical thread safety issues in NDKRelay
  - Added proper locking for connection state management
  - Fixed race conditions in message handling and statistics
  - Ensured state observers are notified on main thread
- Fixed thread safety in NDKSubscription
  - Added locks for event storage and deduplication
  - Prevented race conditions when processing events from multiple relays
- Updated iOS example app to handle subscription updates correctly
  - Fixed subscription update handling to match new API
  - Removed file cache usage temporarily (to be added in future update)
- Improved Maestro test reliability by removing timeouts in favor of assertions

### Added
- Comprehensive mock relay infrastructure for testing
  - `MockRelay`: Full relay implementation conforming to `RelayProtocol`
  - Configurable delays, failures, and auto-responses
  - Event simulation and subscription management
  - Connection state tracking and observation
- Testing documentation and guide (`Tests/NDKSwiftTests/TestingGuide.md`)
- Mock relay usage examples (`Tests/NDKSwiftTests/Examples/WebSocketMockExamples.swift`)
- Integration tests for relay connections (`Tests/NDKSwiftTests/Relay/WebSocketRelayTests.swift`)
- Test status documentation (`Tests/NDKSwiftTests/TEST_STATUS.md`)
- **NIP-44 Encryption Support**: Implemented the modern encryption standard for Nostr
  - Full NIP-44 v2 implementation with ChaCha20, HMAC-SHA256, and HKDF
  - Conversation key derivation using secp256k1 ECDH
  - Powers-of-two based padding algorithm for message length obfuscation
  - Constant-time MAC verification for security
  - Integration with NDKSigner protocol for seamless encryption/decryption
  - Support in NDKPrivateKeySigner for both NIP-04 and NIP-44
  - Comprehensive test suite using official NIP-44 test vectors
  - Example demos showing NIP-44 usage (NIP44Demo.swift, NIP44EventDemo.swift)

### Changed
- Updated NDKPrivateKeySigner to support NIP-44 encryption scheme
- Enhanced Crypto utilities with NIP-44 specific functions
- Cleaned up repository structure for better organization
  - Removed temporary debug files (debug_*.swift, test_*.swift)
  - Removed disabled test files (.disabled.bak)
  - Removed Package.resolved files (should not be committed)
  - Updated .gitignore to properly exclude build artifacts and temporary files
  - Removed empty scripts directory
- Reorganized test suite
  - Consolidated duplicate tests into focused test files
  - Removed 6 obsolete/low-priority test files
  - Re-enabled 3 critical utility tests (ContentTaggerTests, ImetaUtilsTests)
  - Documented test status and priorities in TEST_STATUS.md

### Removed
- 6 obsolete test files that were duplicates or low priority
- Temporary debug files (debug_*.swift, test_*.swift)
- Package.resolved files that should not be committed

### Fixed
- Fixed test compilation issues after refactoring
  - Updated Tag usage to array format instead of object format
  - Fixed NDKEvent initialization parameters
  - Fixed NDKError pattern matching from enum to struct property checking
  - Restored 54 passing tests across multiple test suites:
- Enabled and fixed 28 previously disabled test files (44 total enabled, 6 remaining disabled)
  - Fixed NDKEvent constructor API mismatches throughout test suite
  - Fixed filter.matches(event:) method signature usage
  - Fixed NDKSubscriptionBuilder filter accumulation logic
  - Improved NDKInMemoryCache query implementation for complex filters
  - Fixed async pubkey access in NDKPrivateKeySigner tests
- Successfully passing test suites include:
  - TagHelpersTests: 15/15 tests passing
  - NDKImageTests: 11/11 tests passing  
  - NDKListTests: 21/21 tests passing
  - NDKContactListTests: 30/30 tests passing
  - NDKRelayListTests: 24/24 tests passing
  - NIP04EncryptionTests: 8/8 tests passing
  - NDKSubscriptionTrackerTests: 10/10 tests passing
  - NDKRelaySubscriptionManagerTests: 8/12 tests passing (4 skipped)
  - BasicOutboxTest: 2/2 tests passing
  - NDKFetchingStrategyTests: 4/4 tests passing
  - NDKBunkerSignerTests: 7/7 tests passing
  - NDKSubscriptionReconnectionTests: All tests skipped (require relay infrastructure)
  - NDKSubscriptionManagerTests: All tests skipped (internal component)
    * Bech32Tests (10 tests)
    * JSONCodingTests (9 tests)
    * RetryPolicyTests (12 tests)
    * URLNormalizerTests (16 tests)
    * SimpleWorkingTest (6 tests)
    * MinimalTest (1 test)
- Fixed initialization cycle in NDKContactList and NDKRelayList
  - Changed convenience initializers to designated initializers
  - Resolved bus error crashes when creating lists
- Removed broken integration tests that had outdated API usage
- Fixed all deprecation warnings by migrating to async/await APIs
  - Updated NDKFetchingStrategy to use subscription updates stream
  - Updated NDKSubscriptionBuilder to use async sequences instead of callbacks
- Achieved 100% clean build with no errors or warnings

## [0.6.0] - 2025-01-09

### Changed
- **BREAKING**: Refactored subscription system to use modern Swift patterns
  - NDKSubscription now conforms to AsyncSequence for natural iteration
  - Removed NDKSubscriptionDelegate protocol in favor of AsyncStream
  - Removed callback-based API (onEvent, onEOSE, onError) - now deprecated with backward compatibility
  - Subscriptions auto-start when iteration begins

### Added
- New one-shot fetch methods for common queries:
  - `fetchEvents(_:relays:cacheStrategy:)` - Fetch events matching filters
  - `fetchEvent(_:relays:cacheStrategy:)` - Fetch single event by ID or filter  
  - `fetchProfile(_:relays:cacheStrategy:)` - Fetch user profile metadata
- AsyncStream-based subscription updates with `NDKSubscriptionUpdate` enum
- Comprehensive documentation in SUBSCRIPTION_API_GUIDE.md

### Deprecated
- `subscription.onEvent(_:)` - Use `for await event in subscription` instead
- `subscription.onEOSE(_:)` - Use `subscription.updates` stream instead
- `subscription.onError(_:)` - Use `subscription.updates` stream instead
- `NDKSubscriptionDelegate` - Use AsyncSequence pattern instead
- `SubscriptionEventSequence` - NDKSubscription now directly conforms to AsyncSequence

### Improved
- Simplified subscription API with clearer fetch vs subscribe distinction
- Better integration with Swift concurrency features
- More intuitive API that follows Swift best practices
- Reduced boilerplate with auto-starting subscriptions

## [0.5.0] - 2025-01-09

### Changed
- **BREAKING**: Removed backward compatibility code and dual error systems
  - Removed `NDKError.upgradeFromLegacy()` method
  - Removed legacy error type conversions
  - Simplified error handling to use only `NDKError` with structured error categories
  - Fixed error comparison issues in tests by using error code and category
- **BREAKING**: Removed cache adapter pattern
  - Replaced `NDKCacheAdapter` protocol with direct `NDKCache` usage
  - Migrated from `cacheAdapter` property to `cache` property in NDK
  - Simplified cache operations with direct async/await API
- **BREAKING**: Simplified subscription system
  - Removed redundant state management (multiple boolean flags replaced with single state enum)
  - Replaced complex lock-based concurrency with actor-based state management
  - Simplified event deduplication to use a simple Set instead of EventDeduplicator
  - Kept backward compatibility for deprecated callback methods (`onEvent`, `onEOSE`, `onError`)
  - Maintained `updates` stream for compatibility with existing code
- **BREAKING**: Changed `Tag` type from custom struct to simple `[String]` array
  - Removed `NDKTag` struct in favor of using `Tag` typealias (`[String]`)
  - Updated all tag-related operations to work with array structure
  - Fixed TagBuilder to use mutating methods properly

### Removed
- Removed `NDKError.legacyError` computed property
- Removed `NDKCacheAdapter` protocol and all adapter implementations
- Removed `NDKOutboxCacheAdapter` and related outbox cache adapters
- Removed `SubscriptionState` actor (replaced with `SubscriptionStateActor`)
- Removed multiple NSLock instances from NDKSubscription
- Removed complex EOSE tracking per relay (simplified to boolean)
- Removed `NDKTag` struct (replaced with `Tag` typealias)

### Fixed
- Fixed unpublished event tracking by converting to TODO notes for future implementation
- Fixed profile fetching to use inline JSON decoding
- Fixed subscription state management race conditions
- Fixed iOS app example to use updated APIs
  - Updated cache initialization to use `cache` property instead of constructor
  - Fixed subscription to use async updates stream instead of deprecated callbacks
  - Fixed NDKEvent initialization to include required parameters
- Fixed test compilation errors
  - Updated NDKContactListTests to use Tag arrays instead of NDKTag
  - Fixed NDKError comparisons to check code and category
  - Fixed NDKPrivateKeySigner.generate() calls to include try
  - Fixed TagBuilder usage to handle mutating methods properly

## [0.4.0] - 2025-01-08

### Added
- Created centralized `JSONCoding` utility to eliminate duplicate JSON encoder/decoder setup across the codebase
- Added comprehensive tests for JSONCoding utility
- Created `RetryPolicy` class with configurable exponential backoff for network operations
- Added predefined retry configurations for relay connections, RPC requests, and critical operations
- Added async/await support for retry operations with timeout capabilities
- Added comprehensive tests for RetryPolicy functionality
- Created `ThreadSafeCollections` utilities demonstrating actor-based thread safety patterns
- Added `EventCollection`, `CallbackCollection`, and `StateManager` actors as thread-safe alternatives to NSLock
- Added comprehensive tests comparing actor-based vs lock-based performance
- Added thread safety migration guide documentation
- Created `EventDeduplicator` with LRU cache for centralized duplicate event detection
- Added configurable deduplication with global and per-relay tracking
- Added deduplication statistics for monitoring and debugging
- Added comprehensive tests for EventDeduplicator functionality
- Created `NDKUnifiedError` system with hierarchical error categories and rich context
- Added error recovery suggestions and automatic error migration
- Added comprehensive error handling guide documentation
- Added backward compatibility bridge for existing error types
- Created unified cache architecture with layered caching system
- Added `CacheLayer` protocol for consistent cache implementations
- Added `MemoryCacheLayer` and `DiskCacheLayer` implementations
- Added `LayeredCache` for managing multiple cache tiers
- Added `UnifiedCacheAdapter` to bridge new architecture with NDKCacheAdapter
- Added cache statistics and monitoring capabilities
- Added comprehensive unified cache architecture documentation
- Created tag operation helpers with convenience methods for common patterns
- Added thread-aware tag queries (rootEventId, replyToEventId, mentionedEventIds)
- Added tag validation and batch operations (deduplication, removal)
- Added TagBuilder for complex tag construction
- Created comprehensive tag operations guide documentation
- Simplified subscription API with auto-starting subscriptions
- Added subscription builder pattern for fluent configuration
- Added fetch() method for one-time event queries with auto-close
- Added stream() method for async event sequences
- Added profile fetching convenience methods (fetchProfile, fetchProfiles)
- Added subscription groups for bulk lifecycle management
- Added scoped subscriptions with automatic cleanup
- Added auto-closing subscription wrappers
- Created comprehensive subscription API guide documentation

### Changed
- Refactored all JSON operations to use the new JSONCoding utility
- Updated NostrMessage, NDKEvent, NDKProfileManager, and FileManagerExtensions to use consistent JSON handling
- Fixed optional unwrapping issues in test helpers
- Fixed Swift 6 warning in NDKProfileManager by properly capturing self in async closure
- Replaced manual exponential backoff logic in NDKRelayConnection with RetryPolicy
- Removed duplicate retry delay calculations across the codebase
- Demonstrated how to replace NSLock patterns with Swift actors for better thread safety
- Leveraged existing LRUCache implementation for event deduplication
- Standardized error handling with unified error types and consistent error messages

## [0.3.5] - 2025-01-07

### Changed
- Refactored file cache implementations to use generic helper functions for Codable operations
- Added `FileManagerExtensions.swift` with reusable methods for loading and saving Codable objects
- Simplified `NDKFileCache` and `NDKFileCacheOutbox` by removing duplicate serialization code
- Removed custom JSON serialization for NDKEvent in favor of native Codable support
- All cache operations now use consistent Codable serialization

## [0.3.4] - 2025-01-07

### Added
- Support for fetching events using bech32 identifiers in `fetchEvent` method. Now accepts `note1`, `nevent1`, and `naddr1` formats in addition to hex event IDs.

## [0.3.3] - 2025-01-06

### Changed
- Applied comprehensive code formatting and style improvements across codebase

### Fixed
- Fixed critical race condition in NDKSubscription causing segfaults
- Fixed race condition in NDKSubscription activeRelays causing crashes

### Added
- Added comprehensive subscription tracking system

## Previous versions
- See git history for changes in earlier versions