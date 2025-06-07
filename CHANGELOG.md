# Changelog

All notable changes to NDKSwift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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