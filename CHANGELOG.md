# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Mint caching support for Cashu wallets
  - Added `mint_info` and `keysets` tables to SQLite cache schema
  - Implemented `MintCache` protocol for standardized mint data caching
  - Added `CachedMintLoader` for automatic cache management with staleness checks
  - NDKCashuWallet now accepts optional `mintCache` parameter for performance optimization
  - Cache methods in NDKSQLiteCache: `saveMintInfo`, `getMintInfo`, `saveKeyset`, `getKeysets`, etc.
  - Support for checking cache staleness with configurable time intervals
  - In-memory cache implementation for testing
- New methods in NDKCashuWallet:
  - `getMintInfo(url:)` - Get mint info with caching support
  - `refreshMintKeysets(url:)` - Force refresh keysets from network

### Changed
- `NDKCashuWallet.init` now accepts optional `mintCache` parameter
- `addMint(url:)` now uses cached mint loader when available

### Technical Details
- Mint info cached for 24 hours by default
- Keysets cached for 1 hour by default
- Cache automatically updated when loading mints
- Foreign key constraints ensure keysets are deleted when mint is removed