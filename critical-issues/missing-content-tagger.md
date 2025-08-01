# Critical Issue: Missing ContentTagger Implementation

## Problem
The test file `ContentTaggerTests.swift` contains extensive tests for a `ContentTagger` type that doesn't exist in the codebase.

## Details
- Tests expect methods like:
  - `ContentTagger.generateHashtags(from:)`
  - `ContentTagger.decodeNostrEntity(_:)`
  - `ContentTagger.parseContentSegments(_:)`
  - `ContentTagger.generateContentTags(_:)`
- The actual `ContentTagger.swift` file only contains Tag extensions
- All ContentTagger tests are failing due to missing implementation

## Impact
- 8+ test methods are failing in ContentTaggerTests
- These tests cannot pass without the implementation
- The tests suggest important functionality for parsing Nostr content

## Options
1. Implement the missing ContentTagger functionality based on test expectations
2. Remove/disable the ContentTaggerTests until implementation is added
3. Refactor tests to use existing functionality

## Test Coverage
The tests cover:
- Hashtag generation from content
- Decoding Nostr entities (npub, note, etc.)
- Parsing content segments with mentions
- Generating content tags
- Tag validation