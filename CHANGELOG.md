# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
// Old way:
let event = try await ndk.fetchEvent("event_id")
let events = try await ndk.fetchEvents(filter)

// New way:
let dataSource = ndk.observe(filter: NDKFilter(ids: ["event_id"]), maxAge: 3600)
let event = await dataSource.currentValue().first

let dataSource = ndk.observe(filter: filter, maxAge: 3600)
let events = await dataSource.currentValue()
```