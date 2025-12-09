# NDKMetaSubscription Design

## Overview

`NDKMetaSubscription` is a reactive subscription that returns events pointed to by e-tags and a-tags, rather than the matching events themselves. This enables discovery feeds, notifications, and engagement-based sorting.

## Use Cases

1. **Discovery feed** - "Trending in your network" - content reposted/zapped by follows
2. **Article comments** - articles being commented on by follows
3. **Notifications** - interactions pointing to your content

## Public API

```swift
@Observable
public final class NDKMetaSubscription {
    // The pointed-to events, sorted by current sort mode
    public private(set) var events: [NDKEvent] = []

    // Whether EOSE has been received
    public private(set) var eosed: Bool = false

    // Number of pointed-to events
    public var count: Int { events.count }

    // Change sort mode (triggers instant re-sort, no refetch)
    public var sort: NDKMetaSubscriptionSort

    // Get all interactions pointing to a specific event
    public func eventsTagging(_ event: NDKEvent) -> [NDKEvent]

    // Stop the subscription
    public func stop()

    // Clear all data
    public func clear()
}

public enum NDKMetaSubscriptionSort {
    case time          // Content creation time (newest first)
    case count         // Most interactions first
    case tagTime       // Most recent interaction first
    case uniqueAuthors // Most diverse engagement first
}

extension NDK {
    public func metaSubscribe(
        filter: NDKFilter,
        sort: NDKMetaSubscriptionSort = .tagTime,
        options: NDKSubscriptionOptions? = nil
    ) -> NDKMetaSubscription
}
```

## Internal Architecture

### Data Flow

1. Subscribe to pointer events matching the filter (e.g., reposts from follows)
2. Extract e-tags and a-tags from each pointer event
3. Batch fetch the referenced events (with deduplication)
4. Track the relationship: which pointers point to which content
5. Sort the pointed-to events based on current sort mode
6. Update reactively as new pointer events arrive

### Data Structures

```swift
// tagId -> pointed-to event
private var targetEvents: [String: NDKEvent] = [:]

// tagId -> array of pointer events
private var pointersByTarget: [String: [NDKEvent]] = [:]
```

### Sorting Algorithms

| Sort | Algorithm |
|------|-----------|
| `time` | Sort by `event.createdAt` descending |
| `count` | Sort by `pointersByTarget[tagId].count` descending |
| `tagTime` | Sort by max `created_at` of pointers descending |
| `uniqueAuthors` | Sort by unique pubkeys in pointers descending |

## Usage Examples

### Discovery Feed

```swift
let feed = ndk.metaSubscribe(
    filter: NDKFilter(kinds: [6, 16], authors: follows),
    sort: .tagTime
)

ForEach(feed.events) { event in
    let reposters = feed.eventsTagging(event)
    PostCard(event: event, repostedBy: reposters.count)
}
```

### Notifications

```swift
let notifications = ndk.metaSubscribe(
    filter: NDKFilter(kinds: [6, 16, 7, 9735], "#p": [myPubkey]),
    sort: .tagTime
)
```

### Article Comments

```swift
let articles = ndk.metaSubscribe(
    filter: NDKFilter(kinds: [1111], authors: follows),
    sort: .count
)
```

## Requirements

- iOS 17+ (uses @Observable)
- Mirrors ndk-svelte's $metaSubscribe API
