# Changelog
All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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