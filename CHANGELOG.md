# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.2] - 2025-01-10

### Added
- Content parsing functionality for rich text rendering
  - `ParsedContent` struct and `ContentSegment` enum for representing parsed Nostr content
  - `NDK.parseContent()` method to parse content and fetch referenced users/events
  - Support for parsing mentions (@npub), event references (nostr:nevent), hashtags, and URLs
  - `ParseContentOptions` for controlling parsing behavior and fetch timeouts
  - Enhanced `ContentTagger` with `parseContentSegments()` method
- `NDKUser.processMetadataEvent()` method for updating user profiles from metadata events

### Changed
- Enhanced content parsing to return `NDKUser` and `NDKEvent` objects instead of just bech32 strings
- Improved timeout handling in content parsing with proper error types

## [0.6.1] - Previous releases
- NWC (Nostr Wallet Connect) support
- NIP-44 encryption support
- Simplified codebase architecture