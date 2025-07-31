# Bug Report: MemoryCache.queryEvents applies limit before sorting

## Issue
The `queryEvents` method in `MemoryCache` applies the limit filter before sorting the results by timestamp. This leads to incorrect results when querying with a limit.

## Location
`Sources/NDKSwift/Cache/MemoryCache.swift` lines 64-67

## Current Behavior
```swift
// Apply limit if specified
if let limit = filter.limit, limit > 0 {
    results = Array(results.prefix(limit))
}

// Sort by created_at descending
// ... sorting happens after limit
```

## Expected Behavior
The events should be sorted first, then the limit should be applied to get the most recent N events.

## Impact
When querying events with a limit, users may not get the most recent events as expected. Instead, they get an arbitrary subset of events (first N found) which are then sorted.

## Suggested Fix
Move the limit application after the sorting:

```swift
// Sort by created_at descending first
let sortedResults = await withTaskGroup(of: (NDKEvent, Timestamp).self) { ... }

// Then apply limit if specified
if let limit = filter.limit, limit > 0 {
    results = Array(sortedResults.prefix(limit))
} else {
    results = sortedResults
}
```

## Test Case
The test `testQueryEventsWithLimit` in `MemoryCacheTests.swift` was designed to catch this issue.