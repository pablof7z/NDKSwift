# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Configurable subscription grouping delay via `groupingDelay` parameter
  - Set custom delay when calling `ndk.subscribe(filters:groupingDelay:)` 
  - Default remains 100ms for backward compatibility
  - Set to 0 to disable grouping for specific subscriptions
  - Multiple subscriptions within the delay window are merged into single relay requests
- Re-enabled subscription grouping that was previously disabled
  - Subscriptions with compatible filters are automatically merged
  - Reduces relay connections and improves efficiency
  - Grouping considers: kinds, filter structure, relay requirements, limits, closeOnEose, time constraints
- Full NIP-10 compliant e-tag and q-tag implementation with pubkey hints
  - `tagEvent` now requires an NDKEvent object (not just event ID) to automatically include pubkey hints
  - New `quoteEvent` method for adding NIP-10 compliant q-tags when citing events in content
  - The pubkey hint (5th position in e-tags, 4th in q-tags) helps with the outbox model to find events from author's write relays
  - Updated all event interaction methods (reactions, reposts, deletions, replies, quotes) to use the new NIP-10 compliant tagging
  - Removed backward compatibility - all event tagging must now use the event object for proper NIP-10 compliance

### Fixed
- **CRITICAL**: Fixed completely broken Nutzap implementation (NIP-61)
  - Nutzaps were putting the entire serialized token in the content field instead of using proof tags
  - Added proper `proof` tags containing JSON-encoded proofs as per NIP-61 specification
  - Added required `u` tags for mint URLs
  - Fixed content field to contain comment (not the token)
  - Fixed recipient P2PK key lookup to use `p2pk` tag instead of `pubkey` tag in kind:10019 events
  - Updated `NutzapPaymentRequest` to properly separate Nostr pubkey and P2PK key
  - Fixed `processIncoming` to parse proofs from tags instead of content field
  - Ensured P2PK keys have '02' prefix for Nostr compatibility

### Added
- Reactive profile observation API via `observeProfile(for:)` method
  - Returns an AsyncStream that yields profile updates in real-time
  - Immediately yields cached profiles if available
  - Automatically subscribes to profile updates from relays
  - Follows the same AsyncSequence pattern as NDKSubscription
  - Perfect for reactive UIs that need to display up-to-date profile information

### Fixed
- NIP60Wallet now properly exposes wallet configuration relays from kind 17375 events
  - Added `walletConfigRelays` property to expose relay URLs from the wallet configuration
  - NutsackiOS wallet settings now correctly shows relays from the wallet configuration event
  - Empty relay lists in the configuration are properly handled (wallet settings shows empty)
  - Removed redundant decryption in WalletEventProcessor - now uses NDKCashuWalletEvent's built-in methods
- Fixed NIP60Wallet mint synchronization issues in `processWalletConfiguration`
  - Mints that fail to load (network errors) are now properly handled and not added to wallet
  - Wallet now removes mints that are no longer in the configuration event
  - Event emissions now reflect actual MintManager state, not just requested configuration
  - Added detailed logging for mint addition/removal operations

### Changed
- Empty relay sets in `ndk.subscribe()` now behave the same as nil (use default relay selection)
  - Previously, passing an empty relay set would result in an inactive subscription
  - Now, both nil and empty sets will use the outbox model or all available relays

### Added
- Automatic relay connection for explicitly requested relays in subscriptions and publishing
  - When subscribing with specific relays, NDK now ensures they are connected before use
  - When publishing to specific relays, NDK now ensures they are connected before use
  - Publishing no longer blocks on slow relay connections - connections happen in parallel
  - Added comprehensive tests in RelayConnectionTests.swift

### Added
- Automatic processing of kind:5 deletion events (NIP-09) in NDKSubscriptionManager
- Author validation for deletion events - only original authors can delete their events
- Tombstone cache for deletion events that arrive before the original event (10-minute TTL)
- Comprehensive tests for deletion event processing including out-of-order scenarios (DeletionEventTests.swift)
- NIP-87 Cashu Mint Discovery support
  - Added `NDKCashuMintAnnouncement` for mint announcement events (kind: 38172)
  - Added `NDKMintRecommendation` for mint recommendation events (kind: 38000)
  - Added `MintDiscoveryManager` to discover mints from Nostr network in NutsackiOS
  - Added UI for discovering and selecting mints in NutsackiOS example app
  - Updated `WalletManager.discoverMints()` to use NIP-87 events
- NIP-60 Quote Tracking with automatic minting
  - Added automatic tracking of 7374 quote events on wallet startup
  - Implemented dynamic polling intervals using exponential backoff (2 minutes to 2 hours)
  - Quotes are monitored for up to 24 hours from creation
  - Successfully minted quotes are automatically deleted from Nostr
  - Fixed deposit polling bug where monitoring stopped after first check
- NIP-11 icon and banner support in NDKRelayInformation
  - Added `icon` and `banner` fields to match the updated NIP-11 specification
  - Updated NutsackiOS example to use NIP-11 icon field instead of favicon.ico
  - Relay icons now display in RelayManagementView and WalletSettingsView
- Epic payment received animations in NutsackiOS
  - Created sublime full-screen animation for received payments and nutzaps
  - Features lightning bolts, confetti, fireworks, falling coins, and particle effects
  - Includes haptic feedback for enhanced user experience
  - Automatically triggers for both ecash token redemption and nutzap receipts

### Fixed
- NIP-60 wallet incorrectly deleting token events when making new deposits
  - Completely refactored state management to follow ndk-wallet pattern
  - Added explicit WalletStateChange to separate intent from implementation
  - Replaced complex inference logic with simple calculateNewState function
  - Fixed deposit operations to no longer trigger deletion events
  - All wallet operations now explicitly declare what proofs to store/destroy
- Fixed wallet balance showing "-" instead of "0" in NutsackiOS
  - Removed unnecessary "-" display for zero balance in BalanceCard
  - The wallet already correctly loads balance via subscription

### Changed
- Event deletion API simplified - use `event.delete()` instead of `ndk.deleteEvent()`
- Logging in deletion processing now uses NDKLogger instead of print() for consistency
- **BREAKING**: Removed `displayName` parameter from `NDKSession` and `NDKAuthManager.createSession()`
  - Sessions now only use profile metadata from kind:0 events
  - Eliminates confusion between local display names and actual Nostr profile names

### Removed
- Deprecated `NDK.deleteEvent()` and `NDK.deleteEvents()` methods - use `NDKEvent.delete()` instead
- `displayName` field from `NDKSession` struct
- `bestDisplayName` computed property from `NDKSession` - use `profileName ?? shortIdentifier` directly
- `invalidDisplayName` error case from `NDKSessionError`

## [0.4.5] - 2025-07-16

### Changed
- Updated subscription ID generation to match ndk-core pattern instead of using UUIDs
  - Subscription IDs now follow format: `[meaningful-part]-[random-suffix]`
  - Meaningful part includes filter information (kinds, authors, tags, etc.) for better debugging
  - Random suffix ensures uniqueness (5 alphanumeric characters)
  - Example IDs: `kinds:1,3,7-a2x9k`, `kinds:0-auth,time-b3m5n`
  
### Added
- Added `fingerprint` property to `NDKFilter` for generating consistent filter identifiers
  - Used internally for subscription ID generation
  - Returns human-readable representation when possible, otherwise SHA256 hash prefix

## [0.4.4] - 2025-07-16

### Added
- Reactive relay state management with `NDKRelay.stateStream` AsyncStream
  - Provides real-time updates for connection state, statistics, and relay information
  - Unified `NDKRelay.State` struct combines all relay state into a single observable value
  - Eliminates need for polling in UI components
  
### Changed
- Made `NDKRelayStats`, `NDKRelayInformation`, and `NDKRelaySignatureStats` conform to Equatable
- Updated RelayStateActor to broadcast state changes to observers
- NutsackiOS: Refactored RelayManagementView to use reactive state observation instead of polling
  - Individual RelayRowView components now observe their own relay state
  - Real-time updates for connection status, statistics, and relay information
  - Improved performance by eliminating periodic polling

### Fixed
- Fixed issue where 7375 events weren't being published to relays when created in NutsackiOS app
  - Root cause was relay connections not being established before event publishing
  - Reactive state management ensures UI accurately reflects relay connection status

## [0.4.3] - 2025-07-16

### Added
- NutsackiOS: New wallet events view to display all NIP-60 token events (kind 7375)
  - Shows all token events with their deletion status (active/deleted)
  - Displays event details including mint, proofs, and proof states
  - Supports checking real-time proof states (spent/unspent) with mints
  - Tracks deletion via both NIP-09 deletion events and `del` tags in newer events
  - Accessible via Settings → Wallet → Wallet Events

## [0.4.2] - 2025-07-16

### Fixed
- Fixed invalid REQ message error in NIP-60 wallet deposits where Cashu quote IDs were being used as Nostr event IDs
  - Modified `WalletEventManager.saveQuoteEvent` to return the Nostr event ID
  - Updated `WalletEventManager.deleteQuoteEvent` to properly accept Nostr event IDs instead of Cashu quote IDs
  - Removed incorrect deletion of quote events during deposit monitoring since the Nostr event ID is not available at that point

## [0.4.1] - 2025-07-16

### Fixed
- NIP-60 wallet now properly includes `del` tags when creating new token events after spending proofs
  - Added proof ownership tracking with timestamps to `ProofStateManager`
  - New `getOwnerEventIds()` method returns previous owners of proofs
  - `WalletEventManager.updateTokenEvents()` now includes superseded event IDs in `del` tags
  - Prevents double-spending issues when syncing wallet state across clients

## [0.4.0] - 2025-07-16

### Changed
- **BREAKING**: Removed `fetchEvents(_ filter: NDKFilter)` method - use `fetchEvents(_ filters: [NDKFilter])` instead. This simplifies the API by having only one method that accepts an array of filters, which can contain a single filter.

## [0.3.3] - 2025-07-16

### Added
- Comprehensive network traffic logging system via `NDKLogger`
  - Configurable log levels: `.off`, `.error`, `.warning`, `.info`, `.debug`, `.trace`
  - Configurable log categories: `.network`, `.relay`, `.subscription`, `.event`, `.cache`, `.auth`, `.general`
  - Pretty-printed network messages showing parsed message types, event IDs, kinds, authors, etc.
  - Raw JSON output for debugging protocol issues
  - Enable/disable network traffic logging with `NDKLogger.shared.logNetworkTraffic`
  - Enable/disable pretty printing with `NDKLogger.shared.prettyPrintNetworkMessages`
- New example: `NetworkLoggingDemo.swift` demonstrating logging configuration

### Changed
- Updated `NDKRelayConnection` to use the new logging system instead of raw print statements
- Network traffic now shows both formatted and raw messages for easier debugging

### Documentation
- Added "Logging and Debugging" section to API Reference documentation
- Documented all NDKLogger configuration options and output format

## [0.3.2] - 2025-07-15

### Added
- New Cashu event types: `NDKCashuTokenEvent`, `NDKCashuQuoteEvent`, `NDKCashuSpendingHistory`, `NDKCashuWalletEvent`, and `NDKCashuMintList` that encapsulate encryption and publishing logic
- New EventKind constants: `cashuQuote` (7374), `cashuToken` (7375), `cashuSpendingHistory` (7376), and `cashuWalletConfig` (17375)
- Added `delete()` method to `NDKEvent` extension that creates and publishes deletion events
- Added `isLockedTo(pubkey:)` method to `CashuSwift.Proof` extension for checking P2PK locks
- Added `NIP60WalletEvent` type for wallet configuration events with proper data modeling
- New `NIP60Wallet.setup()` method that properly configures wallet with mints, relays, and optionally publishes mint list (kind 10019)
- Added `NDKCashuMintList` to wrap kind 10019 events for advertising accepted mints

### Changed
- Fixed `NDK` initializer to use `MemoryCache()` instead of non-existent `NDKInMemoryCache()`
- Consolidated tag utility functions from `TagHelpers.swift` into `ContentTagger.swift`
- Updated `NDKUser.pay()` to return `PaymentConfirmation` instead of deprecated `NDKPaymentConfirmation`
- Updated example apps to use new payment types (`NutzapPaymentRequest` instead of deprecated `NDKNutzapRequest`)
- Updated Outbox documentation to clarify it's the default behavior, not an advanced feature
- Removed references to non-existent `publishWithOutbox()`, `fetchEventsWithOutbox()`, and `subscribeWithOutbox()` methods from documentation
- Renamed `NDKCashuWallet` to `NIP60Wallet` to better reflect it implements the NIP-60 specification
- Moved wallet directory from `Sources/NDKSwift/Wallets/Cashu/` to `Sources/NDKSwift/Wallets/NIP60/`
- Refactored `WalletEventManager` to use new object-oriented event types instead of procedural helper methods
- Updated all Cashu wallet code to use EventKind constants instead of hardcoded numbers
- **BREAKING**: Removed `NIP60Wallet.save()` method - use `setup()` instead
- **BREAKING**: Removed `NIP60Wallet.publishNutzapPreferences()` method - mint list publishing is handled by `setup()` with `publishMintList: true`
- **BREAKING**: Removed `NIP60Wallet.hasPublishedNutzapPreferences()` method - no longer needed
- **BREAKING**: Removed `NIP60Wallet.addMint()` and `removeMint()` methods - mint configuration is now event-driven through `NDKCashuWalletEvent.createAndPublish()`
- **BREAKING**: Removed `WalletEventManager.saveWalletEvent()` - use `NDKCashuWalletEvent.createAndPublish()` directly

### Fixed
- Fixed authentication flow in NDKAuthView to prevent returning to login screen after successful authentication
- Fixed ImportAccountView to use `ndk.fetchProfile()` instead of removed `user.fetchProfile()` method

### Documentation
- Added comprehensive [Authentication Guide](Documentation/AUTHENTICATION.md) covering NDKAuthManager, NDKAuthView, session management, and biometric authentication
- Updated documentation index to include authentication guide
- Enhanced examples documentation with link to authentication guide

### Removed
- Removed deprecated code from `TagHelpers.swift` and consolidated remaining utilities into `ContentTagger.swift`
- Removed `TagHelpers.swift` file after consolidation
- Removed all deprecated payment types from `NDKWallet.swift` (`NDKPaymentRequest`, `NDKPaymentConfirmation`, etc.)

## [0.3.1] - 2025-07-16

### Added
- Enhanced `RelayProtocol` with `publish` and `fetchEvents` methods for better testability
- New `subscribeToZaps()` method in `NDKZapManager` for reactive, event-driven zap loading
- Comprehensive documentation on event-driven patterns in `EVENT_DRIVEN_PATTERNS.md`
- Audit document `FETCHEVENTS_AUDIT.md` analyzing all `fetchEvents` usage in the codebase

### Changed
- Updated `fetchEvents` documentation with clear warnings about when to use it vs subscriptions
- Improved `RelayProtocol` abstraction by moving essential methods from extensions into the protocol
- Added deprecation warnings to blocking methods that have event-driven alternatives

### Fixed
- **NDKCashuWallet**: Removed broken `processIncomingTokenEvent` method that contained a recursive call bug causing stack overflow. Token events are now processed through the unified wallet subscription via `WalletEventProcessor`

### Documentation
- Added extensive guidance on when to use `fetchEvents` vs subscriptions
- Created examples demonstrating proper event-driven patterns for common use cases
- Documented anti-patterns to avoid (e.g., sequential fetching in loops)

## [0.3.0] - 2025-07-15

### Changed
- **BREAKING**: Unified payment protocols into a single, clearer system
  - `NDKPaymentRequest` and `NDKPaymentConfirmation` are now deprecated in favor of `PaymentRequest` and `PaymentConfirmation` defined in `ZapTypes.swift`
  - New concrete types: `LightningInvoiceRequest`, `NutzapPaymentRequest`, `LightningPaymentConfirmation`, `NutzapConfirmation`
  - Protocol now uses `amountSats` instead of `amount` for clarity
  - Simplified protocol by removing unnecessary fields like `tags` and `unit` from base protocol
  - Updated all wallet implementations (NDKCashuWallet, NDKNWCWalletProtocol) to use new protocols
  - Updated payment providers to use new unified types
- Consolidated wallet event handling into single `WalletEventProcessor` actor
  - Replaced 7 separate event handler structs with one cohesive processor
  - Removed entire `EventHandlers` directory and simplified architecture
  - Event processing logic now uses a simple switch statement instead of protocol dispatch
  - Improves maintainability and reduces cognitive overhead
- **BREAKING**: Integrated MintCache functionality directly into NDKCache protocol
  - Removed separate `MintCache` protocol
  - Added mint caching methods to `NDKCache` protocol with default implementations
  - Updated `NDKSQLiteCache` to no longer need dual protocol conformance
  - Simplified architecture by having a single cache interface for all data types
  - `CachedMintLoader` now uses `NDKCache` directly
  - Renamed `InMemoryMintCache` to `FullInMemoryCache` to better reflect its complete NDKCache implementation
  - Updated parameter names from `mintCache` to `cache` in `NDKCashuWallet` and `MintManager` initializers

## [0.2.1] - 2025-07-14

### Fixed
- Fixed handling of "del" tags in token events to properly delete proofs from superseded events
- Unified deletion logic between kind:5 delete events and "del" tags to ensure consistent behavior

### Changed
- **BREAKING**: Removed `NDKPaymentMethod.nwc` case as NWC (Nostr Wallet Connect) is not a payment method but a wallet connection protocol
  - NWC wallets now only report support for `.lightning` payment method
  - Removed NWC payment method checks from `NDKUser.getPaymentMethods()`
  - Updated `WalletAdapterPaymentProvider` to remove NWC method references

## [0.2.0] - 2025-07-14

### Changed
- **BREAKING**: Major refactoring of NDKCashuWallet to improve architecture and maintainability
  - Reduced NDKCashuWallet from 2,298 lines to 1,367 lines (40.5% reduction)
  - Extracted proof state management into dedicated ProofStateManager actor
  - Extracted event operations into WalletEventManager actor
  - Extracted payment operations into PaymentProcessor actor
  - Extracted nutzap operations into NutzapProcessor actor
  - Extracted health monitoring into WalletHealthMonitor actor
  - Improved thread safety using Swift actors for all state management
  - Enhanced separation of concerns following SRP, DRY, KISS, and YAGNI principles
  - Moved RelayHealth type from NDKCashuWallet to WalletHealthMonitor

### Added
- ProofStateManager: Thread-safe proof state tracking with reservation system
- WalletEventManager: Centralized NIP-60 event creation and management
- PaymentProcessor: Handles Lightning payments and cross-mint transfers
- NutzapProcessor: Dedicated handler for nutzap sending and receiving
- WalletHealthMonitor: Relay synchronization and proof state reconciliation
- **CLI-Nutsack**: New command-line NIP-60 wallet calculator example
  - Full navigatable menu system with arrow key support
  - Balance tracking across multiple mints
  - Send/receive nutzaps (NIP-61)
  - Transaction history with table view
  - Mint management interface
  - Proof statistics and management

### Fixed
- Improved concurrent operation safety with actor-based state management
- Better error handling and recovery in payment operations
- More reliable proof state tracking and reconciliation
- CashuSwift API compatibility issues
- Build errors in NutsackiOS example app related to refactored types

## [0.1.0] - Previous version