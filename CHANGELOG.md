# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Refactored codebase to improve maintainability (DRY/YAGNI/KISS/SRP principles)
  - Consolidated error constants: merged StringConstants.ErrorMessages into ErrorMessageConstants
  - Removed deprecated methods: NDKDataSource.currentValue() and NDKOutboxManager.getRecommendedRelaysForSubscription()
  - Removed TODO comments from production code per project policy
  - Updated LoadingView.swift to use first() instead of deprecated currentValue()
  - Moved magic number (batch size 100) to SQLiteConstants.queryBatchSize constant
  - Removed unused Foundation imports from NDK+Helpers.swift and NostrJSONConstants.swift

### Fixed
- Fixed memory leak in Posta app consuming 85GB+ of RAM
  - Removed manual session state monitoring that created infinite loops
  - Fixed duplicate session data subscriptions in NDKSessionData
  - Simplified HomeView to use reactive filter API as intended
  - Session data now properly checks if data is already available before creating new subscriptions
- Fixed duplicate session data loading in reactive filters
  - NDKSessionData.load() now checks if data is already available before creating subscriptions
  - Added active data source check to prevent multiple concurrent loads
  - Reactive filters no longer create duplicate subscriptions for the same data

### Changed
- Simplified Posta app to properly use reactive filter API
  - Removed manual state tracking for session data changes
  - Removed isLoadingFollows, isLoadingNotes, sessionMonitorTask
  - App now relies on NDK's internal subscription management
- Updated Socrates app to filter muted users
  - Audio events from muted users are now filtered out
  - Simplified refresh logic to avoid duplicate data source creation

### Removed
- Removed deprecated FeedView implementation in Olas app
  - Deleted Sources/Olas/Views/Feed/FeedView.swift (used old subscribe() API)
  - Deleted Sources/Olas/Views/Feed/FeedItemView.swift
  - App now uses only the modern reactive observer pattern

### Previously Fixed
- Fixed blocking issue in progressive session loading that prevented reactive filters from working
  - NDKSessionData.loadLists() was blocking on async stream iteration
  - Progressive strategy now properly loads from cache and continues in background
  - HomeView reactive filters now work correctly in Posta app
- Fixed fatal crash when accessing relay pool before initialization
  - InternalSubscriptionManager now delays relay monitoring until pool is available
  - Relay monitoring starts on first subscription creation instead of init
  - Prevents "Fatal error: Unexpectedly found nil while unwrapping Optional" crash
- Fixed subscription replay when relays reconnect
  - Implemented relay connection monitoring in InternalSubscriptionManager
  - Active subscriptions are now properly replayed to newly connected relays
  - Ensures events are delivered even when subscriptions are created before relay connections
- Fixed progressive preload strategy race condition
  - Progressive strategy now properly waits for cache load before returning
  - Prevents reactive filters from seeing empty follow lists when data exists in cache
- Outbox relay selection no longer blocks subscription creation
  - Fixed critical bug where getRecommendedRelaysForSubscription would hang waiting for relay lists
  - Subscriptions now start immediately with cached relay info or default relays
  - Relay discovery happens in background without blocking event delivery
  - Proper filter decomposition by relay for efficient querying

### Changed
- Outbox model now uses non-blocking relay resolution
  - getRecommendedRelaysForSubscription deprecated in favor of getOutboxStrategy
  - Authors without known relays use app's connected relays immediately
  - Background relay discovery updates subscriptions progressively
  - Filters are decomposed to send author-specific queries to each relay

### Added
- Dynamic subscription relay updates for outbox model
  - New RelayUpdateNotifier system that monitors relay discovery
  - Subscriptions automatically update when relay lists (kind:10002) are discovered
  - Public API for monitoring relay updates via ndk.outbox.relayUpdates AsyncStream
  - Relay update statistics available via getRelayUpdateStats()
  - Automatic creation of relay-specific subscriptions when relay info becomes available
  - Example: DynamicRelayUpdates.swift demonstrates the feature

### Improved
- Memory management and cleanup in outbox implementation
  - Changed relay lookup window from 5 minutes to 2 hours (more reasonable rate limiting)
  - Added automatic cleanup of old entries in RelayListLookupTracker (removes entries older than 4 hours)
  - Added periodic cleanup of stale subscriptions in RelayUpdateNotifier (removes after 24 hours)
  - Limited update subscription IDs to last 10 per subscription to prevent unbounded growth
  - Added hourly cleanup task in NDKDataRequirementManager for orphaned cache handles
- Fixed compilation warnings
  - Removed unnecessary async/await on non-async properties
  - Fixed unused variable warnings by using proper Swift patterns

### Fixed
- Ephemeral events (kinds 20000-29999) are now properly excluded from caching
  - SQLite cache skips saving ephemeral events in saveEvent and processEvent
  - Query operations automatically filter out ephemeral events
  - Memory cache also excludes ephemeral events
  - Added comprehensive tests for ephemeral event filtering

### Added
- NDKSwiftUI Markdown Renderer
  - Complete markdown syntax support (headings, bold, italic, code blocks, lists, etc.)
  - Full Nostr entity parsing (npub, note, nevent, naddr, mentions, hashtags)
  - Inline image rendering with AsyncImage
  - Customizable styling with predefined themes (minimal, dark, nostr, compact)
  - Progressive disclosure with NDKMarkdownPreview component
  - Action handlers for mentions, hashtags, links, and Nostr entities
  - Integration with ContentParser for accurate Nostr entity detection
  - Support for custom markdown configurations
- Session Data Management System with reactive subscriptions
  - NDKSessionData for managing follow lists, mute lists, blocked relays, and web-of-trust data
  - Observable states for session data readiness
  - Automatic session restoration with data preloading
  - Progressive loading strategy (cache-first, update in background)
  - Efficient O(1) lookups for muted pubkeys and blocked relays
- Reactive Filter System
  - ReactiveFilter struct for dependency-based filter updates
  - Automatic subscription swapping when follows change
  - Efficient re-subscription with minimal event re-downloading
  - Support for Web of Trust filtering (optional)
  - Automatic filtering of muted pubkeys from event streams
- NDK Session Extensions
  - `startSession()` method for initializing authenticated sessions
  - `observe(ReactiveFilter)` for reactive event streams with mute filtering
  - `fetchEvents(ReactiveFilter)` for one-time reactive queries with mute filtering
- SubscriptionSwapManager for efficient subscription updates
- Blocked Relay Protection
  - Automatic exclusion of blocked relays from outbox operations
  - Relay selector respects user's blocked relay list (kind:10006)
  - Cached blocked relay checks for performance
- Support for NDKFollowPack (NIP-51, kinds 39089 and 39092)
  - Create and manage follow packs with title, description, image, and pubkey collections
  - Support for both regular follow packs and media follow packs
  - Rich image metadata support using imeta tags
  - Fetch follow packs by user, identifier, or globally
  - Convert between NDKEvent and NDKFollowPack representations
- Comprehensive tests for NDKFollowPack functionality
- Example demonstrating follow pack creation and management
- ReactiveFilterDemo example showing automatic subscription updates

### Changed
- Session subscriptions now use meaningful subscription IDs for easier debugging
  - Session lists: `session_lists_[pubkey_prefix]`
  - Web of Trust: `session_wot_[pubkey_prefix]`
  - Reactive filters: `reactive_[dependencies]_[pubkey_prefix]`
  - Data source subscriptions: descriptive IDs based on filter content (e.g., `metadata_author_12345678_abcd`)

### Fixed
- Posta app now properly displays cached follow lists immediately instead of showing "Loading your follows..."
- Session data state is checked immediately after session start to avoid missing initial cached state
- **BREAKING**: Removed `ndk.event()` and `ndk.reply()` extension methods to reduce namespace pollution
  - Use `NDKEventBuilder(ndk: ndk)` instead of `ndk.event()`
  - Use `NDKEventBuilder.reply(to: event, ndk: ndk)` instead of `ndk.reply(to: event)`
- **BREAKING**: Updated various static factory methods to require `ndk` parameter:
  - `NDKEvent.encryptedDirectMessage()` now requires `ndk` parameter
  - `NDKEvent.createFileMetadata()` now requires `ndk` parameter
  - `NDKEvent.mintAnnouncement()` now requires `ndk` parameter
  - `BlossomAuth` static methods now require `ndk` parameter
- Made `NDKEventBuilder` init public for direct instantiation

### Fixed
- Fixed Posta app relay management to properly use NDKRelayCollection
  - Removed duplicate state management that caused relay status to be incorrect
  - Now directly uses NDK's relay collection for accurate real-time status

### Improved
- Enhanced filter aggregation logic in NDKDataRequirementManager
  - Filters with same tag keys but different values are now properly aggregated
  - Multiple subscriptions to similar resources (e.g., project statuses) now result in fewer network requests
  - Example: 3 subscriptions to different projects now create 1 aggregated REQ instead of 3 separate ones
  - Fixed relay initialization to use centralized relay list

## [0.4.1] - 2025-01-22

### Fixed
- Validate P2PK pubkey format in nutzaps (must be 33 bytes starting with "02" or "03" for compressed secp256k1 keys)
- Update transaction status to 'failed' for malformed nutzaps instead of keeping them as 'processing'
- Add detailed error information to failed transactions for better user feedback
- Include P2PK pubkey data in proof decoding logs for easier debugging
- LocalizedError conformance for NutzapRedemptionError to provide user-friendly error messages

### Improved
- Enhanced error handling for invalid nutzaps with malformed P2PK pubkeys
- Better transaction status tracking for failed nutzap redemptions
- More informative logging when processing nutzap proofs
- UI improvements for failed transactions:
  - Show amount in red instead of green for failed transactions
  - Display X icon overlay on avatar for failed nutzaps
  - Remove "+" sign prefix for failed incoming transactions
  - Reduce opacity of failed transactions to indicate disabled state
  - Show detailed error information in transaction details

## [0.4.0] - 2025-01-21

### Fixed
- Fixed wallet balance showing as 0 even when token events are processed
  - Changed token event processing to add new proofs before processing deletions
  - This ensures proofs that appear in both old and new events are properly transferred
  - Added enhanced logging to ProofStateManager for debugging balance calculations
  - Fixed issue where proofs marked as deleted were not being restored when re-added in newer events
- Fixed wallet configuration events being processed out of order during initial load
  - Added tracking of newest configuration timestamp to ensure only the most recent config is applied
  - Prevents older cached configurations from overwriting newer ones
  - Removed duplicate timestamp tracking from WalletEventManager to eliminate technical debt
- Fixed transaction history not updating reactively when new wallet events arrive in NutsackiOS
  - WalletManager now uses property observer (didSet) to automatically update UI transactions array
  - Payment operations now create pending transactions immediately for instant UI feedback
  - Spending history events are now created synchronously to avoid race conditions
  - Transaction status updates are properly propagated through the wallet's transaction history system
- Fixed compilation errors in NutsackiOS WalletManager
  - Updated transaction type enum values to match NDKSwift (`.send`, `.receive`, `.melt` instead of incorrect names)
  - Added temporary nutzap event ID for pending transactions
  - Resolved naming conflicts between view components
- Fixed mint keysets being fetched repeatedly instead of using cached versions
  - MintManager now properly stores loaded mints in memory after loading from cache
  - requestMintQuote now uses loadMint which respects the cache instead of checking empty in-memory state
  - This significantly reduces network requests when minting tokens
  - Updated cache TTLs to more reasonable values: mint info cached for 7 days (was 24 hours), keysets cached for 3 days (was 1 hour)
- Fixed initial balance not displaying in NutsackiOS home screen
  - WalletManager now explicitly fetches and sets the initial balance after wallet loads
  - Added missing pendingAmount property to WalletManager (computed property that calculates from pending transactions)
  - Fixed ProofStateManager to properly update proof state when processing token events with same timestamp
  - Added balance change notification after processing token events in NIP60Wallet
  - Changed initial lastNotifiedBalance to -1 to ensure first balance notification is always emitted
  - Enhanced logging in ProofStateManager to track proof additions and balance calculations

### Added
- Extended `NostrJSONConstants` with Cashu/wallet JSON field constants
  - Added constants for Cashu proof fields: `amount`, `secret`, `C`, `proofs`, `proof`, `mint`, `unit`
  - Added wallet event fields: `direction`, `state`
  - Eliminates hardcoded JSON field names in wallet and Cashu-related code
- Transaction detail drawer in NutsackiOS app for viewing detailed transaction information
- Mint information display in transaction history for NutsackiOS app
  - Shows mint name (when available) or hostname in transaction list
  - Displays full mint information in transaction detail drawer
  - Fetches mint metadata from NDKMintInfo including name and description
  - Clickable transaction rows in Recent Activity and Transaction History views
  - Comprehensive transaction details including status, date, memo, mint URL, and more
  - Support for viewing sender/recipient profiles for nutzaps
  - Share transaction functionality with formatted text output
- Added zap functionality to NIP60Wallet example with `NDKUser.zap()` integration
  - Support for sending zaps via npub, hex pubkey, or NIP-05 identifiers
  - Automatic configuration of wallet as payment provider for NDK zap manager
  - Profile fetching for recipient display names using `profileManager.observe()`

### Changed
- Updated wallet and Cashu code to use `NostrTagConstants` and `NostrJSONConstants` instead of hardcoded strings
  - `NDKNutzap` now uses tag constants for `amount`, `unit`, `proof`, `url`, `pubkey`, `event` tags
  - `NDKZapRequest` now uses tag constants for `pubkey`, `amount`, `lnurl`, `event`, `address` tags
  - `WalletEventManager` now uses tag constants for `proof` and `url` tags
  - `WalletTransactionHistory` now uses tag constants for `proof` and `pubkey` tags
  - `Nutzap` now uses JSON constants for notification userInfo
- Replaced duplicate `NostrTag` enum with `NostrTagConstants.TagName` throughout the codebase
  - Updated `NDKBlockedMintsEvent`, `NDKCashuEvents`, `NDKList`, `NDKEvent`, `NDKEventExtensions`, `WalletEventProcessor`
  - Removed duplicate `NostrTag` enum from `TagValidation.swift`
  - All tag references now use the centralized `NostrTagConstants` for better maintainability

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