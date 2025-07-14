# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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