# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Created centralized `JSONCoding` utility to eliminate duplicate JSON encoder/decoder setup across the codebase
- Added comprehensive tests for JSONCoding utility
- Created `RetryPolicy` class with configurable exponential backoff for network operations
- Added predefined retry configurations for relay connections, RPC requests, and critical operations
- Added async/await support for retry operations with timeout capabilities
- Added comprehensive tests for RetryPolicy functionality
- Created `ThreadSafeCollections` utilities demonstrating actor-based thread safety patterns
- Added `EventCollection`, `CallbackCollection`, and `StateManager` actors as thread-safe alternatives to NSLock
- Added comprehensive tests comparing actor-based vs lock-based performance
- Added thread safety migration guide documentation
- Created `EventDeduplicator` with LRU cache for centralized duplicate event detection
- Added configurable deduplication with global and per-relay tracking
- Added deduplication statistics for monitoring and debugging
- Added comprehensive tests for EventDeduplicator functionality

### Changed
- Refactored all JSON operations to use the new JSONCoding utility
- Updated NostrMessage, NDKEvent, NDKProfileManager, and FileManagerExtensions to use consistent JSON handling
- Fixed optional unwrapping issues in test helpers
- Fixed Swift 6 warning in NDKProfileManager by properly capturing self in async closure
- Replaced manual exponential backoff logic in NDKRelayConnection with RetryPolicy
- Removed duplicate retry delay calculations across the codebase
- Demonstrated how to replace NSLock patterns with Swift actors for better thread safety
- Leveraged existing LRUCache implementation for event deduplication

## [0.3.5] - 2025-01-07

### Changed
- Refactored file cache implementations to use generic helper functions for Codable operations
- Added `FileManagerExtensions.swift` with reusable methods for loading and saving Codable objects
- Simplified `NDKFileCache` and `NDKFileCacheOutbox` by removing duplicate serialization code
- Removed custom JSON serialization for NDKEvent in favor of native Codable support
- All cache operations now use consistent Codable serialization

## [0.3.4] - 2025-01-07

### Added
- Support for fetching events using bech32 identifiers in `fetchEvent` method. Now accepts `note1`, `nevent1`, and `naddr1` formats in addition to hex event IDs.

## [0.3.3] - 2025-01-06

### Changed
- Applied comprehensive code formatting and style improvements across codebase

### Fixed
- Fixed critical race condition in NDKSubscription causing segfaults
- Fixed race condition in NDKSubscription activeRelays causing crashes

### Added
- Added comprehensive subscription tracking system

## Previous versions
- See git history for changes in earlier versions