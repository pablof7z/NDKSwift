# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Extended `NostrJSONConstants` with Cashu/wallet JSON field constants
  - Added constants for Cashu proof fields: `amount`, `secret`, `C`, `proofs`, `proof`, `mint`, `unit`
  - Added wallet event fields: `direction`, `state`
  - Eliminates hardcoded JSON field names in wallet and Cashu-related code

### Changed
- Updated wallet and Cashu code to use `NostrTagConstants` and `NostrJSONConstants` instead of hardcoded strings
  - `NDKNutzap` now uses tag constants for `amount`, `unit`, `proof`, `url`, `pubkey`, `event` tags
  - `NDKZapRequest` now uses tag constants for `pubkey`, `amount`, `lnurl`, `event`, `address` tags
  - `WalletEventManager` now uses tag constants for `proof` and `url` tags
  - `WalletTransactionHistory` now uses tag constants for `proof` and `pubkey` tags
  - `Nutzap` now uses JSON constants for notification userInfo

### Added
- `EventPublishingHelper` utility to eliminate duplicate `createAndPublish` patterns across event types
- `SQLiteQueryBuilder` to consolidate SQL query building logic and eliminate code duplication
- `RelayConstants` enum to centralize commonly used Nostr relay URLs
  - Provides constants for popular relays like Damus, Nostr Band, nos.lol, Primal, etc.
  - Includes pre-defined relay sets for different use cases (default, extended, test, wallet)
  - Eliminates hardcoded relay URLs throughout the codebase
- `ErrorMessageConstants` enum to consolidate common error messages
  - Reduces duplication of error strings like "Failed to parse", "Invalid format", etc.
  - Provides helper functions for consistent error message formatting
- `ValidationHelpers` enum to consolidate common validation patterns
  - String validation (isEmpty, normalize, hasLength)
  - URL validation helpers
  - Collection validation helpers
  - Numeric validation helpers
- `CollectionExtensions` with common collection operations
  - `hasElements`, `hasOneElement`, `hasMultipleElements` properties
  - String extensions for `hasContent`, `trimmed`, `normalized`
  - Optional collection helpers like `isNilOrEmpty`
- `StringFormatHelpers` for common string formatting patterns
  - Error message formatting
  - Relay URL display formatting
  - Hex string formatting and truncation
  - JSON pretty printing
  - Timestamp formatting
- `TypeAliases` file to consolidate common type aliases
  - `Timestamp`, `RelayURL`, `PublicKey`, `EventID`, etc.
  - Common callback and closure type aliases

### Fixed
- Relay health monitoring now correctly uses wallet-configured relays from kind 17375 events
  - Previously checked all NDK pool relays instead of wallet-specific ones
  - `getRelayHealth()` and `checkWalletHealth()` now use `walletRelays` property
  - Ensures accurate health reporting for relays that should contain wallet state
  - NutsackiOS: Added "Relay Health" menu item to access the monitoring UI

### Changed
- Refactored `NDKSQLiteCache` to use `SQLiteQueryBuilder`, eliminating duplicate query building logic
- Cleaned up Package.swift by removing commented-out dependencies (YAGNI principle)
- Removed unnecessary Foundation imports from utility files that don't need them
- Updated examples, tests, and source code to use `RelayConstants` instead of hardcoded relay URLs
- Updated `NDKErrorFactories` to use `ErrorMessageConstants` for consistent error messages
- Updated `NostrJSONConstants` to reference `NostrTagConstants.ProfileField` to avoid duplication
- Updated `Nutzap.swift` to use `NostrJSONConstants.kind` instead of hardcoded string

## [0.4.2] - 2025-07-21

### Fixed
- Nutzap fee handling to prevent `invalidSplit` errors when sending ecash
  - Now uses CashuSwift's `pick()` function for automatic fee calculation and proof selection
  - Ensures sufficient proofs are selected to cover both payment amount and fees
  - Adds fee buffer when checking mint balances for payment routing
  - Fixes issue where sending exact amounts (e.g., 10 sats) would fail due to unaccounted fees

### Added
- Immediate cache-first behavior for `NDKDataSource` subscriptions
  - Cache is now queried immediately when creating a data source, eliminating the 100ms grouping delay
  - Events from cache are delivered instantly, improving perceived performance
  - Network fetch is skipped entirely when cache is fresh (based on `maxAge` parameter)
  - `CachePolicy.networkOnly` prevents immediate cache hits when fresh data is required
  - Cache observation handles are properly managed to prevent duplicate event delivery
- Event-driven methods for `NDKDataSource` to replace polling patterns
  - `first(timeout:)` - Wait for and return the first event or nil if none arrive
  - `collect(timeout:limit:)` - Collect all events until EOSE or timeout
  - `eventsUntilEOSE` - AsyncStream that emits events and completes on EOSE
  - These methods properly wait for events to arrive from relays before returning
- Example demonstrating event-driven nutzap preference handling (`EventDrivenNutzapExample.swift`)
- Nutzap tracking and redemption state management in NIP60Wallet
  - Track all incoming nutzaps with their amount, sender, and comment
  - Monitor redemption status through kind:7376 spending history events
  - Public APIs to query nutzaps by state (pending/redeemed)
  - `getNutzaps()` - Get all nutzaps sorted by creation date
  - `getPendingNutzaps()` - Get only unredeemed nutzaps
  - `getRedeemedNutzaps()` - Get only redeemed nutzaps
  - `isNutzapRedeemed(eventId)` - Check if a specific nutzap is redeemed
  - `getTotalPendingNutzapAmount()` - Get total amount of pending nutzaps
  - `getTotalRedeemedNutzapAmount()` - Get total amount of redeemed nutzaps
  - Automatic tracking of nutzap state through spending history events
  - Loads historical nutzaps and their redemption state on wallet initialization

- Unified transaction history API in NIP60Wallet
  - `WalletTransaction` struct represents all transaction types (mint, melt, send, receive, nutzaps)
  - Uses random UUIDs for stable transaction IDs that persist across state changes
  - Fully reactive implementation using NDKDataSource for real-time updates
  - Comprehensive lookup indices for efficient transaction finding
  - `getTransactionHistory()` - Get complete transaction history sorted by date
  - `getTransactions(types:)` - Filter by transaction types
  - `getTransactions(direction:)` - Filter by incoming/outgoing
  - `getRecentTransactions(limit:)` - Get most recent transactions
  - `getTransactionSummary()` - Get statistics (counts, amounts by type, totals)
  - Real-time updates via event stream with `transactionAdded` and `transactionUpdated` events
  - Support for pending transactions that exist before any Nostr events
  - Automatic matching of events to existing transactions
  - Progressive status updates (pending → processing → completed)
  - Apps no longer need to merge different event types manually

### Changed
- Major refactoring of zap protocol selection to eliminate redundant fetches
  - All recipient data (profile, nutzap preferences) now fetched once and cached
  - Created `RecipientZapInfo` struct to hold all zap-related data
  - Updated `NDKZapProtocol` interface to accept pre-fetched `RecipientZapInfo`
  - `canZap()` is now a synchronous check on pre-fetched data
  - Zap manager caches recipient info for 24 hours with automatic deduplication
  - Relay selection uses nutzap-specific relays from kind:10019 or falls back to user's connected relays
- Updated `NDKNutzapProtocol` to use event-driven `collect()` method for fetching preferences
- Improved subscription handling to ensure events are delivered before methods return
- Completed migration from `currentValue()` to `collect()` throughout the codebase
  - `fetchRelayList()`, `fetchContactList()`, and `fetchProfiles()` now use `collect()` to ensure most recent events are used
  - All example code migrated to use event-driven patterns
  - Test code updated to use appropriate async methods
  - `NDKFetchingStrategy`, `NDKLightningZapProtocol`, `NDKZapManager`, and `WalletTransactionHistory` migrated
  - Created comprehensive migration guide in `Examples/CurrentValueMigrationGuide.swift`

### Fixed  
- Fixed race condition where `NDKDataSource.currentValue()` could return empty array before subscription started
  - Methods now properly wait for initial data or EOSE before returning

### Deprecated
- `currentValue()` method on `NDKDataSource` - use event-driven methods instead
  - Use `first()` to get the first event
  - Use `collect()` to get all events until EOSE
  - Use `events` AsyncStream for continuous updates
  - Use `eventsUntilEOSE` for processing events as they arrive until completion

## [0.4.1] - 2025-07-21

### Fixed
- Fixed nutzap processing by correcting the kind:10019 mint list event format
  - Changed P2PK pubkey tag from "p2pk" to "pubkey" as specified in NIP-61
  - Added relay tags to kind:10019 events for proper nutzap routing
  - Added comprehensive logging throughout the nutzap receive flow
  - Nutzaps should now be properly received and redeemed by the wallet

### Added
- Event ID filter optimization for improved subscription efficiency
  - Filters requesting specific event IDs now check cache first
  - Cached event IDs are automatically excluded from relay requests
  - Subscriptions close immediately after receiving all requested IDs
  - No network request is made if all IDs are already cached
  - Reduces network traffic and relay load for immutable event data
- NIP-92 Media Attachments support with automatic URL extraction
  - Automatic imeta tag creation for media URLs in content
  - Manual imeta tag builder methods  
  - Seamless Blossom integration with automatic blurhash and dimension extraction
  - NDKEvent extensions for extracting and working with imeta tags
  - Support for all NIP-92 fields including fallback URLs
- NIP60Wallet REPL: Added `validate` command to verify and reconcile proof states
  - Supports dry run mode with `-d` flag to check proofs without modifying wallet state
  - Can validate all mints or a specific mint by URL
  - Shows detailed proof states (valid/spent/pending) with visual indicators
  - Automatically removes spent proofs in non-dry-run mode
  - Provides comprehensive validation summaries per mint and overall

### Fixed
- Fixed CashuDeposit to properly track and clean up quote events after successful deposits
  - `requestMintQuote` now returns both the quote and its event ID when persisting
  - `monitorDeposit` accepts an optional quote event ID for cleanup
  - Successfully used quotes are automatically deleted from Nostr storage
  - Prevents accumulation of obsolete quote events

### Added
- Added `check` command to NIP60Wallet example REPL for validating proof states
  - Check proofs against specific mint or all configured mints
  - Shows proof states: unspent, spent, or pending
  - Provides summary statistics for proof validation
  - Automatically reconciles proof states after checking
- Added modular LNURL resolution system for proper zap receipt validation
  - `LNURLResolver` protocol for easy replacement with library implementations
  - Support for LUD16 (Lightning Address) resolution
  - Automatic extraction of provider pubkey from LNURL metadata
  - Fallback handling for services that use recipient's pubkey
  - Comprehensive error handling and logging
  - Unit tests for LNURL resolution scenarios
- Added comprehensive NIP-05 caching system with proactive caching and lazy verification
- Added profile semantic caching for optimized performance
  - Profiles now stored with individual fields in database columns
  - No JSON parsing required on retrieval (average <0.1ms per profile)
  - Additional/custom profile fields stored as efficient binary plist
  - Backward compatible with JSON-only profiles from before migration
  - Migration v11 automatically converts existing profiles to semantic format
  - Performance improvement: ~10x faster profile retrieval compared to JSON parsing
  - Automatic extraction of NIP-05 identifiers from kind:0 events
  - Verification states: unverified, verified, invalid, expired, failed
  - Smart caching with configurable TTL (24 hours default)
  - Rate limiting per domain to prevent abuse
  - NIP-05 search with prefix matching for autocomplete
  - Self-healing cache that corrects wrong associations
  - SQLite storage with optimized search indexes
  - **Performance Improvements**:
    - Dedicated `NIP05Manager` actor for better modularity and encapsulation
    - In-memory LRU cache layer for frequently accessed entries
    - In-flight request deduplication prevents duplicate network calls
    - Batch verification support for stale entries
  - **API Improvements**:
    - `ndk.nip05Manager` provides centralized NIP-05 operations
    - Cache statistics and health monitoring
    - Flexible cache clearing options
  - `NDKUser.fromNip05()` now uses cache with optional force verification
  - `ndk.searchNIP05()` for instant prefix search without network requests
  - `ndk.verifyNIP05()` and `user.verifyNIP05()` for lazy verification
- Added comprehensive NIP-92 (Media Attachments) support with automatic imeta tag generation
  - Automatic extraction of media URLs from event content (images, videos, audio, PDFs)
  - Manual imeta tag builder methods for custom metadata
  - Seamless Blossom integration with `imetaTag(from:)` method
  - Support for all NIP-92 fields: url, alt, dim, m, blurhash, x, size, fallback
  - **Automatic blurhash calculation and dimension extraction during Blossom uploads**
  - Blurhash dependency added for client-side image processing
  - Example demonstrating various NIP-92 usage patterns
  - Comprehensive unit tests for NIP-92 functionality

### Fixed
- Fixed fatal error "Duplicate elements of type 'WeakObserver' were found in a Set" by using ObjectIdentifier instead of UUID for WeakObserver identity. This ensures the same observer can be registered multiple times without causing crashes.
- Removed duplicate WeakObserver definition from MemoryCache, now using the shared definition from CacheObservation.swift
- Fixed SQLite migration error "table relay_sources already exists" by adding existence checks in Migration_v6_RelaySources. The migration now safely skips table creation if it already exists and uses IF NOT EXISTS for indexes and triggers.
- Fixed Swift continuation leak in `publishEvent` by ensuring all pending event continuations are properly resumed when the connection is closed or encounters an error. This prevents "SWIFT TASK CONTINUATION MISUSE" warnings.
- Fixed SQLite error "table relay_sources has no column named subscription_id" by adding Migration_v8_AddSubscriptionId to handle existing databases that were created with an older schema. This migration adds the missing subscription_id column to the relay_sources table.

## [0.4.0] - 2025-07-21

### Breaking Changes
- **REMOVED**: All `fetchEvent` and `fetchEvents` methods have been removed from the API
  - These imperative fetch methods have been replaced with the reactive `observe()` pattern
  - Use `NDKDataSource` and `ndk.observe()` for all event fetching needs
  - For one-shot queries, use `observe()` with `maxAge` parameter
- **REMOVED**: `fetchEvents` method from `RelayProtocol` interface
- **REMOVED**: `fetchEvents` method from `NDKRelay` implementation
- **REMOVED**: `fetchEvents` method from `NDKOutboxManager` - replaced with `observe()` method
- **REMOVED**: `fetchEvents` method from `NDKFetchingStrategy` - replaced with `observe()` method

### Changed
- Updated `NDKFilter` documentation to use `observe()` examples instead of `fetchEvents`
- Removed `fetchEvents` string constant from `StringConstants.Operations`
- Refactored internal outbox model code to use `NDKDataSource` pattern

### Migration Guide
To migrate from the old fetch methods to the new observe pattern:

```swift
let dataSource = ndk.observe(filter: NDKFilter(ids: ["event_id"]), maxAge: 3600)
let event = await dataSource.currentValue().first

let dataSource = ndk.observe(filter: filter, maxAge: 3600)
let events = await dataSource.currentValue()
```