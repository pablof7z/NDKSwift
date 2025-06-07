# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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