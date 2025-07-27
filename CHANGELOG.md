# Changelog
All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- NIP-42 relay authentication support with new authentication states
- `NDKAuthenticationDelegate` protocol for controlling relay authentication
- New relay connection states: `authRequired`, `authenticating`, `authenticated`
- `isAuthenticated` property on `NDKRelay` to check authentication status
- Automatic detection of auth-required errors in publish failures
- Example code demonstrating NIP-42 authentication flow
- Unit tests for authentication state transitions and delegate behavior

### Changed
- `NDKRelayConnectionState` enum now includes authentication-related states
- Relay connections can now send messages when in `authenticated` state
- `isConnected` property now returns true for both `connected` and `authenticated` states

### Improved
- Refactored JSON encoding/decoding to use centralized `JSONCoding` utility throughout the codebase
- Moved `NDKSubscription` documentation to Internal Components section to clarify it's an implementation detail
- Cleaned up deprecated code comments in `NDKAuthManager`

### Documentation
- Updated API Reference to emphasize `NDKDataSource` as the primary public subscription API
- Added Internal Components section to documentation for implementation details

## [0.7.0] - 2025-01-27

### Added
- NIP-17 Private Direct Messages implementation with metadata privacy
- NIP-59 Gift Wrap protocol for event sealing and wrapping
- Support for chat messages (kind 14) and file messages (kind 15)
- Comprehensive unit tests with test vectors from nostr-tools
- Integration tests and example code for NIP-17 usage
- New `initialize()` method on NDKAuthManager for simplified session restoration

### Changed
- Reduced log verbosity by moving detailed event processing logs from INFO to DEBUG/TRACE level in NDKDataSource
- Simplified NDKAuthManager API - developers now just call `await authManager.initialize()` instead of manually restoring and switching sessions
- Deprecated `restoreSession()` method in favor of the new `initialize()` method

### Improved
- Authentication session restoration is now automatic and requires less boilerplate code
- Documentation updated to reflect the new simplified authentication pattern

## [0.6.0] - 2025-01-26

### Added
- NDKSwiftUI library providing SwiftUI components for Nostr apps
- Proper CI/CD workflow for automated testing and releases
- GitHub Actions workflow for release automation
- Interactive release script for version management

### Changed
- Updated Swift tools version to 6.0
- Migrated all example iOS apps to use published NDKSwift versions instead of local paths
- Separated example iOS apps into individual repositories:
  - Olas-iOS: Instagram-like social network
  - Nutsack: Cashu ecash wallet
  - Highlighter: Nostr highlights reader
  - Posta: Full-featured Nostr client
  - Ambulando: Audio walking app

### Fixed
- CashuSwift dependency issues by using the main branch of the original library
- Removed forked CashuSwift library from Libraries directory

### Improved
- Project organization with all iOS apps now in separate repositories
- Professional setup with proper build scripts and TestFlight deployment
- Documentation with comprehensive README files for each app

## [0.2.0] - 2025-01-26

### Added
- URLSessionProtocol to enable proper testing of BlossomClient
- Missing tests for NDKAuthManager.restoreSession() method
- Comprehensive documentation for AsyncSequence API usage
- Migration guide from callback-based to AsyncSequence patterns
- Convenience methods to HexValidator for backward compatibility (isValidHexString, isValidHexPubkey, isValidEventId, isValidSignature)
- ContentParserTests for testing content parsing functionality
- Shared BlossomServerManager class for use across example apps
- Shared ExampleRelayConstants for consistent relay usage in examples

### Changed
- BlossomClient now accepts URLSessionProtocol instead of concrete URLSession
- SimpleMockURLSession now conforms to URLSessionProtocol for testing

### Fixed
- Re-enabled BlossomClient metadata tests that were previously disabled
- Improved error logging in NDKSignatureVerificationSampler for better debugging
- Removed force unwrapping in NDKNWCWallet connection handling for safer code
- Test compilation errors by updating Tag usage to use array syntax
- TestFactories filter parameter ordering to match NDKFilter constructor
- Updated README.md to reflect current version (0.1.5)

### Improved
- API documentation now includes detailed AsyncSequence examples
- Better migration guidance for developers moving from callbacks to modern patterns
- Code safety by eliminating force unwrapping in NWC wallet connection
- ContentTagger public API documentation with comprehensive doc comments
- Code organization by removing trailing empty lines
- Reduced code duplication by creating shared components for example apps
- Eliminated code duplication in NDKEvent+Interactions deletion methods by refactoring common logic

## [0.1.5] - 2025-01-26

### Added
- Custom log handler support in NDKLogger for external integration
- Automatic cleanup of expired tombstones in MemoryCache (runs hourly)
- Comprehensive unit tests for NDKSignatureVerificationCache

### Changed  
- Replaced direct print statements with conditional logging in NDKLogger and NDKNetworkLogger
- NDKFilterFingerprint now uses NostrConstants.JSONField constants instead of hardcoded strings

### Improved
- Logging system now only outputs to console in DEBUG builds unless custom handler is set
- Memory management in MemoryCache with periodic tombstone cleanup
- Code consistency by using centralized constants for filter field names

### Changed
- Removed TODO comment in NDKDataRequirementManager that was already implemented

### Added
- Incoming events from relays are now tracked in NDKEventTracker with `markSeen` when received
- First relay to deliver an event is automatically set as the source relay in NDKEventTracker
- Per-author relay count configuration for outbox model (matches ndk-core behavior)
  - Publishing uses 2 relays per author by default (`OutboxConstants.relaysPerAuthor`)
  - Fetching uses 2 relays per author by default (`OutboxConstants.relaysPerAuthorForFetching`)
  - Relay selection now scales dynamically with the number of authors instead of using hard limits

### Fixed
- Fixed outbox subscriptions not connecting to all NIP-65 relays
  - `InternalSubscription` now uses `prepareRelays` with `autoConnect: true` to ensure relays are connected before sending REQ messages
  - This ensures all discovered relays from NIP-65 outbox model receive subscription requests
- Fixed race condition where events arrive before subscription consumers are ready
  - Added `autoStart` parameter to `InternalSubscriptionManager.createSubscription()`
  - `DataRequirement` now starts subscriptions after setting up event stream consumption
  - This prevents events from being lost when they arrive immediately after subscription creation
- Fixed CLOSE messages being sent to relays that never received REQ
  - `InternalSubscription` now tracks which relays successfully received REQ messages
  - CLOSE messages are only sent to relays that were actually active in the subscription
  - This eliminates unnecessary error logs for failed relay connections
- Improved relay connection handling for subscriptions
  - Subscriptions no longer attempt to send REQ to disconnected relays
  - REQ messages are automatically sent when relays connect via the replay mechanism
  - The replay mechanism now properly updates the active relay tracking
  - Closed subscriptions are properly removed and won't be replayed to newly connected relays

### Changed
- Improved outbox relay selection algorithm (aligned with ndk-core)
  - Connected relays are now prioritized over disconnected ones
  - Maximum relay limits increased: 30 for publishing (was 10), 50 for fetching (was 15)
  - These are soft limits that can be exceeded based on author count
  - Relay selection now considers connected state to minimize new connections
- Optimized relay connection handling from O(n) to O(1) for subscription replay
  - Added relay-to-subscription mapping in `InternalSubscriptionManager` for direct lookups
  - Separated universal subscriptions (no relay targets) from relay-specific subscriptions
  - When a relay connects, only relevant subscriptions are replayed without iterating through all active subscriptions
  - This significantly improves performance when managing many concurrent subscriptions
- Replaced hardcoded tag string literals with `NostrConstants` throughout codebase
  - Tag names like "p", "e", "a", "k" now use `NostrConstants.TagName` constants
  - Marker strings like "reply", "root", "redeemed" now use `NostrConstants.Marker` constants
  - Improves maintainability and reduces potential for typos
- Added utility extensions to reduce code duplication
- Major test infrastructure improvements
  - Reorganized test directory structure with consistent Unit/Integration/E2E separation
  - Fixed test file naming inconsistencies (all tests now follow `*Tests.swift` pattern)
  - Created comprehensive test helpers: `TestFactories`, `TestAssertions`, `TestFixtures`
  - Added base test classes: `NDKTestCase`, `NDKIntegrationTestCase`, `NDKPerformanceTestCase`
  - Improved test isolation and resource cleanup
  - Added tests for core components: `NDK`, `NDKEventManager`, `NDKSubscription`
  - Test coverage foundation established for future 80% coverage target
  - Added `nilIfEmpty` property to `String` and `Collection` types
  - Added `setOrNil` property to `String` collections for cleaner optional Set conversion
  - Replaced multiple `.isEmpty ? nil : value` patterns with new extensions
- Replaced magic numbers with named constants
  - Added `defaultCashuFeeBuffer` constant to `PaymentConstants`
  - Replaced hardcoded fee buffer values (1000) with the constant
- Consolidated error messages into `ErrorMessageConstants`
  - Added NDK-specific error messages: `ndkInstanceNotSet`, `ndkNotAvailable`, `ndkReferenceLost`
  - Replaced 12 hardcoded error messages across 5 files
- Created `ValidationConstants` for consistent validation messages
  - Added constants for hex validation requirements (64 character hex, Expected 32 bytes)
  - Replaced hardcoded validation strings in NDKPrivateKeySigner, NWCConnectionURI, and ContentTagger
- Applied `nilIfEmpty` extension across the codebase
  - Replaced 6 instances of `.isEmpty ? nil : value` pattern
  - Updated ContentTagger, Bech32, and NDKCashuEvents for cleaner code

### Fixed
- Replaced force unwrap with safer `compactMap` in `IDGenerator.randomId()`
  - While the force unwrap was technically safe, using `compactMap` follows best practices
- Fixed subscription ID length issues causing "subscription id too long" errors from relays
  - Shortened relay discovery subscription IDs from ~195 to ~21 characters
  - Replaced UUID-based subscription IDs with shorter random IDs (6-8 characters)
  - Updated NDKOutboxManager, NDKOutboxTracker, and NDK+Session to use compact IDs
  - Added tests to ensure subscription IDs stay under 32 characters

## [0.1.4] - 2025-07-25

### Changed
- Consolidated duplicate constants to follow DRY principle
  - Removed redundant `NostrEventKeys.swift` file
  - Updated all references to use centralized `NostrConstants` instead
  - Replaced string literals ("relay", "secret") with appropriate constants throughout codebase
- Eliminated code duplication in string validation
  - Updated `StringExtensions` to use `ValidationHelpers` methods
  - Removed duplicate implementations of `hasContent`, `trim`, and `normalize`

### Fixed
- Removed unnecessary `await` on non-async property access in `NDKDataRequirementManager`
  - Fixed compiler warnings about awaiting synchronous properties
  - Improved code clarity by removing misleading async indicators

## [0.1.3] - 2025-07-24

### Fixed
- Fixed subscription ID length issue that caused errors with some relays (e.g., purplepag.es)
  - Subscription IDs are now significantly shortened to prevent "subscription id too long" errors
  - Kind descriptions use abbreviated forms (e.g., "kind31933" → "k31933", "metadata" → "meta")
  - Author prefixes reduced from 8 to 4 characters
  - Relay host names are shortened by removing common prefixes and TLDs
  - This ensures compatibility with all Nostr relays regardless of their ID length limits

### Changed
- Outbox relays from `NDKOutboxConfig` are now automatically connected during `NDK.connect()`
  - Previously, outbox relays like `purplepag.es` were configured but never connected
  - These relays are now marked with `.outboxConfig` origin for proper tracking
- Improved fallback relay selection to enhance privacy and reduce network spam
  - Fallback now only uses explicit relays + current user's relays
  - Previously used ALL connected relays as fallback, which could expose data to unintended relays
  - This change ensures broadcasts only go to user-intended relays when specific relay selection fails

### Added  
- New `NDKRelayOrigin.outboxConfig` case to track relays added from outbox configuration
- `NDKPool.getCurrentUserRelayUrls()` method to retrieve current user's relay list for fallback selection

## [0.1.2] - 2025-07-24

### Changed
- Web of Trust kind:3 fetching now exclusively uses outbox relays during session initialization
  - This reduces network traffic by only querying the configured `outboxRelays` for contact lists
  - Previously fetched from all connected relays, creating unnecessary data transfer
  - Uses `exclusiveRelays: true` to ensure only outbox relays are queried

### Fixed
- Fixed thread safety crash in `DataRequirement` class by converting it to an actor
  - Resolved `EXC_BAD_ACCESS` crash when accessing `observerHandles` dictionary from multiple threads
  - This crash could occur when navigating to user profiles in apps using NDKSwift
  - All mutable state in `DataRequirement` is now protected by Swift's actor isolation

## [0.1.0] - 2025-07-24

_Note: This release contains breaking changes. NDKAuthView has been removed from the core library._

### Fixed
- Fixed authentication state race condition where session creation wouldn't immediately activate the session
- Fixed `switchToSession` to avoid unnecessary state transitions when switching to a just-created session
- Fixed Socrates app bypassing authentication in DEBUG mode by removing DebugContentView
  - App now properly shows AuthenticationView when not logged in
  - Authentication flow works correctly in both DEBUG and RELEASE builds
- Custom subscription IDs are now preserved exactly as provided without adding random suffixes
  - When using `NDKDataSource` or `ndk.observe()` with a custom `subscriptionId`, the ID is now used as-is
  - This is particularly important for NIP-60 wallet implementations that rely on specific subscription IDs
  - Relay-specific subscriptions (for outbox model) still get a relay suffix appended (e.g., "my-id_relay.host")
- Fixed expert prompt documentation that incorrectly referenced `NDKSubscription` as a public API
  - Clarified that apps should use `ndk.observe()` which returns `NDKDataSource`
  - `NDKSubscription` is an internal implementation detail not meant for direct use
  - Removed references to non-existent `NDKSubscriptionBuilder`
  - Fixed EventKind references to use numeric values (1, 0, 4, etc) instead of symbolic constants
  - Fixed references from "follow list" to "contact list" to match actual implementation
  - Updated `syncEvents` method signature to include required `relay` parameter
  - Added documentation for custom subscription IDs feature
- Fixed subscription aggregation to group filters by structure (tag keys) rather than values
  - Multiple filters with the same kinds and tag keys but different tag values are now aggregated into a single REQ message
  - For example, 5 queries for kind 1111 with different #e values will result in 1 REQ with all 5 event IDs
  - This significantly reduces the number of subscriptions sent to relays when fetching related data
  - Uses new `AggregationSignature` for grouping while keeping `FilterSignature` for cache matching

### Removed
- **BREAKING**: Removed `NDKAuthView` and `NDKAuthConstants` from NDKSwift
  - Apps should implement their own authentication UI using `NDKAuthManager` directly
  - This follows the Single Responsibility Principle and gives apps full control over their auth UI/UX
  - See the updated [Authentication Guide](Documentation/AUTHENTICATION.md) for migration examples

### Changed
- `NDKAuthManager.createSession()` now immediately activates the created session, preventing UI race conditions
- Socrates app now directly observes `NDKAuthManager` for authentication state instead of going through `NostrManager`
  - This follows separation of concerns principle - authentication UI logic shouldn't be managed by NostrManager
  - Provides cleaner architecture and more direct state management
- Improved Socrates authentication implementation
  - Updated to use `NDKAuthManager.shared` directly with `@Observable` pattern
  - Fixed potential retain cycle in authentication state observation
  - Added proper error handling in authentication check