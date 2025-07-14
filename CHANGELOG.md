# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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