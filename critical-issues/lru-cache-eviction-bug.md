# LRUCache Eviction Logic Bug

## Issue Description
The `LRUCache.evictOldest()` method has a critical bug in its eviction logic that causes incorrect behavior when the cache is full and contains expired entries.

## Current Behavior
In `Sources/NDKSwift/Utils/LRUCache.swift`, the `evictOldest()` method (lines 167-191):
- Looks for the oldest entry that **isn't** expired to evict
- Only removes expired entries if they're encountered while searching
- This means expired entries might not be evicted first when the cache is full

## Expected Behavior
When the cache reaches capacity and new items are added:
1. All expired entries should be evicted first
2. Only if there are no expired entries should the oldest non-expired entry be evicted

## Failing Test
`testExpiredEntriesEviction` in `Tests/NDKSwiftTests/Unit/Utils/LRUCacheTests.swift`:
- Creates a cache with capacity 2 and TTL of 0.1 seconds
- Adds two items and waits for them to expire
- Adds two new items
- Expects the cache to contain only the two new items (expired ones should be evicted)
- Actual result: Cache still contains old expired entries

## Root Cause
The eviction logic prioritizes keeping expired entries over evicting them, which is the opposite of what should happen.

## Proposed Fix
The `evictOldest()` method should be refactored to:
1. First remove all expired entries
2. If the cache is still over capacity after removing expired entries, then evict the oldest non-expired entry

## Impact
- Memory usage: Expired entries may unnecessarily consume memory
- Cache effectiveness: New valid entries might be rejected while expired entries remain
- Test reliability: The test correctly identifies this bug

## Recommendation
This is a critical bug that affects the core functionality of the LRU cache. It should be fixed in a separate focused PR to ensure proper cache behavior.