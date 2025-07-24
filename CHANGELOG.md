# Changelog
All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Note: This release contains breaking changes. NDKAuthView has been removed from the core library._

### Fixed
- Fixed authentication state race condition where session creation wouldn't immediately activate the session
- Fixed `switchToSession` to avoid unnecessary state transitions when switching to a just-created session
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