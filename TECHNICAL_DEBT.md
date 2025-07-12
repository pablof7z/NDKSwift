# Technical Debt from Mint Caching Implementation

## 1. JSON-Only Storage Approach
**Issue**: We're storing mint info as raw JSON without extracting searchable fields.
- The database schema has columns for `name`, `pubkey`, `version`, etc., but we're storing `nil` for all of them
- This means we can't query mints by name, version, or other properties
- SQL queries like "find all mints supporting unit X" aren't possible

**Impact**: Low - The cache still works, but advanced queries require deserializing all JSON
**Resolution**: Extract key fields when storing, or remove unused columns

## 2. API Surface Inconsistency
**Issue**: Mixed API patterns between typed and raw data
- `getMintInfoData()` returns `Data` (raw JSON)
- But keysets still use typed `CashuSwift.Keyset` objects
- This creates an inconsistent developer experience

**Impact**: Medium - Developers must handle different patterns for similar data
**Resolution**: Either go fully typed or fully JSON-based

## 3. Cache Invalidation Strategy
**Issue**: No way to force cache refresh or invalidate specific entries
- `CachedMintLoader.invalidateMintCache()` is stubbed but not implemented
- No way to mark cache entries as invalid without deleting them
- No cache versioning for schema changes

**Impact**: Medium - Users may get stale data with no easy fix
**Resolution**: Implement proper cache invalidation methods

## 4. Missing Migration Path
**Issue**: No database migration strategy
- When schema changes, existing caches will break
- No version tracking in the database
- No migration scripts

**Impact**: High - Future updates may require users to delete cache
**Resolution**: Add schema versioning and migration support

## 5. Incomplete Test Coverage
**Issue**: Tests compile but many don't run due to other test failures
- Integration tests are minimal
- No tests for error cases (corrupt JSON, network failures)
- No performance benchmarks

**Impact**: Medium - Bugs may slip through
**Resolution**: Fix test suite and add comprehensive tests

## 6. Hardcoded Defaults
**Issue**: Cache durations are hardcoded
- Mint info: 24 hours
- Keysets: 1 hour
- No way to configure per-mint or globally

**Impact**: Low - Works for most cases but not flexible
**Resolution**: Make cache durations configurable

## 7. No Cache Size Management
**Issue**: Cache can grow indefinitely
- No maximum size limits
- No LRU eviction
- No cleanup of old entries

**Impact**: Medium - Could consume significant disk space over time
**Resolution**: Implement cache size limits and eviction policies

## 8. Error Handling
**Issue**: Many cache operations silently fail
- `try?` used extensively, swallowing errors
- No logging of cache misses or failures
- No metrics or monitoring hooks

**Impact**: Medium - Hard to debug cache issues
**Resolution**: Add proper error handling and logging

## 9. Thread Safety Concerns
**Issue**: While using actors, some edge cases aren't covered
- Concurrent mint updates could race
- No transaction support for multi-step operations

**Impact**: Low - Actors provide good protection but not perfect
**Resolution**: Add transaction support for complex operations

## 10. Documentation Gaps
**Issue**: Limited documentation on cache behavior
- No clear documentation on when cache is used vs. network
- No performance characteristics documented
- Example doesn't exist in the package

**Impact**: Low - Developers may not understand caching behavior
**Resolution**: Add comprehensive documentation

## Recommendations for Next Steps

1. **High Priority**:
   - Add database migration support
   - Implement cache invalidation
   - Fix test suite

2. **Medium Priority**:
   - Make cache durations configurable
   - Add cache size management
   - Improve error handling

3. **Low Priority**:
   - Extract searchable fields from JSON
   - Add performance benchmarks
   - Enhance documentation