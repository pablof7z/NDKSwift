# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added comprehensive NIP-92 (Media Attachments) support with automatic imeta tag generation
  - Automatic extraction of media URLs from event content (images, videos, audio, PDFs)
  - Manual imeta tag builder methods for custom metadata
  - Seamless Blossom integration with `imetaTag(from:)` method
  - Support for all NIP-92 fields: url, alt, dim, m, blurhash, x, size, fallback
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