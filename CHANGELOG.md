# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> **Suggested version**: 0.3.0 (Minor version bump due to new features)

## [0.3.0] - 2025-01-14

### Fixed
- **NutsackiOS Balance Display Issue**: Fixed wallet showing "-" balance after successful deposit
  - Fixed `monitorDeposit` to use proper `update()` method instead of directly appending proofs
  - Added balance refresh mechanism when returning from MintView
  - Added periodic balance updates every 5 seconds while wallet view is visible
  - Added debugging logs to track proof state and balance calculations

### Added
- **Improved Mint Caching System** for Cashu wallets with type-safe API
  - Created `NDKMintInfo` public struct to properly handle mint information
  - New `MintCache` protocol with typed methods instead of raw JSON data
  - Added `NDKSQLiteCacheMigrated` with proper database migrations using GRDB's DatabaseMigrator
  - Implemented cache invalidation with `invalidateMintCache(url:)` method
  - Added LRU (Least Recently Used) cache eviction with `pruneMintCache(maxMints:)`
  - Cache size management and statistics with `getCacheStats()`
  - Debug logging support for troubleshooting cache operations
  - Structured mint data columns for efficient querying (name, pubkey, version, units)
  - Last accessed timestamp tracking for LRU eviction
  - In-memory cache implementation (`InMemoryMintCache`) for testing

- **Database Migrations** for cache evolution:
  - v1: Initial schema with events and profiles
  - v2: Added mint caching with JSON storage
  - v3: Added structured mint data columns with automatic data migration

- **New Cache Methods**:
  - `saveMintInfo(_:url:)` - Save typed NDKMintInfo
  - `getMintInfo(url:)` - Get typed NDKMintInfo with automatic access time update
  - `invalidateMintCache(url:)` - Force cache refresh
  - `deleteMint(url:)` - Remove mint and associated keysets
  - `getCachedMintUrls()` - List all cached mints
  - `pruneMintCache(maxMints:)` - Limit cache size with LRU eviction

- **Enhanced NDKCashuWallet Integration**:
  - `getMintInfo(url:)` - Returns typed `NDKMintInfo` instead of internal CashuSwift types
  - Proper error handling with debug logging
  - Fallback to network fetch when cache is unavailable

- **NIP-18 Repost Support**:
  - `NDKEvent.repost(signer:)` - Create reposts with automatic kind selection (6 for text notes, 16 for others)
  - `NDKEvent.quoteRepost(comment:signer:)` - Create quote reposts with NIP-19 references
  - `NDK.repost(_:)` and `NDK.quoteRepost(_:comment:)` - High-level APIs with automatic publishing
  - Proper handling of NIP-70 protected events (empty content in reposts)
  - Builder factory method `NDKEventBuilder.repost(_:includeContent:)`

- **NIP-25 Reaction Support**:
  - `NDKEvent.react(with:signer:)` - Create reactions with any content
  - `NDKEvent.like(signer:)` and `NDKEvent.dislike(signer:)` - Convenience methods for +/- reactions
  - `NDK.react(to:with:)`, `NDK.like(_:)`, and `NDK.dislike(_:)` - High-level APIs with automatic publishing
  - Automatic k tag inclusion for kind reference
  - Builder factory method `NDKEventBuilder.reaction(_:to:)`

- **NIP-09 Event Deletion Support**:
  - `NDKEvent.createDeletionRequest(reason:signer:)` - Create deletion requests for individual events
  - `NDK.deleteEvent(_:reason:)` and `NDK.deleteEvents(_:reason:)` - High-level APIs for single and bulk deletions
  - Automatic k tag inclusion for deleted event kinds
  - Builder factory methods `NDKEventBuilder.deletion(event:reason:)` and `deletion(events:reason:)`

### Changed
- **Unified SQLite Cache Implementation**:
  - Merged `NDKSQLiteCacheMigrated` into `NDKSQLiteCache` as the single implementation
  - Now includes proper database migration support using GRDB's DatabaseMigrator
  - Maintains backward compatibility with existing cache databases
  - Cleaner API with just one cache class to use

### Changed
- **BREAKING**: `MintCache` protocol now uses typed `NDKMintInfo` instead of raw `Data`
- `NDKSQLiteCache` mint methods now handle typed data internally
- `CachedMintLoader.loadMintInfo()` returns `NDKMintInfo` instead of raw JSON
- Improved error handling throughout the caching system (replaced `try?` with proper `do-catch`)
- Cache updates last_accessed timestamp on reads for accurate LRU tracking

### Fixed
- Resolved issue with CashuSwift.Mint.Info having internal properties by creating public NDKMintInfo
- Fixed test compilation errors with async assertions
- Added missing JSONCoding helper for consistent JSON encoding/decoding
- Improved database performance with proper indexes and query optimization

### Technical Details
- Mint info cached for 24 hours by default (configurable)
- Keysets cached for 1 hour by default (configurable)
- Cache automatically tracks access patterns for LRU eviction
- Foreign key constraints ensure data integrity
- Debug mode available for troubleshooting cache operations
- Automatic JSON data migration when upgrading database schema