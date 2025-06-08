# Tag Operations Guide

## Overview

NDKSwift provides comprehensive tag operation helpers that simplify working with Nostr event tags. This guide covers the enhanced tag APIs that make tag manipulation more intuitive and less error-prone.

## Tag Structure

In Nostr, tags are arrays of strings where:
- Position 0: Tag name (e.g., "e", "p", "t")
- Position 1: Primary value (e.g., event ID, pubkey, hashtag)
- Position 2+: Optional additional values (relay hints, markers, etc.)

## Safe Tag Access

### Array Safety

Use safe subscripts to avoid crashes:

```swift
let tag = ["e", "eventid", "wss://relay.com", "reply"]

// Safe access
let name = tag[safe: 0]      // "e"
let value = tag[safe: 1]     // "eventid"
let relay = tag[safe: 2]     // "wss://relay.com"
let marker = tag[safe: 3]    // "reply"
let missing = tag[safe: 4]   // nil (no crash)
```

### Tag Properties

Convenient properties for common tag elements:

```swift
let tag: Tag = ["e", "eventid", "wss://relay.com", "reply"]

tag.name        // "e"
tag.value       // "eventid"
tag.relayHint   // "wss://relay.com"
tag.marker      // "reply"
```

## Tag Creation

### Basic Tag Helpers

Add common tags with type-safe methods:

```swift
var event = NDKEvent(content: "Hello Nostr!")

// Reply to another event
event.tagReply(to: parentEvent, relay: "wss://relay.damus.io")

// Add root reference
event.tagRoot(rootEvent)

// Mention another event
event.tagMention(mentionedEvent)

// Add hashtags
event.tagHashtag("nostr")
event.tagHashtag("#bitcoin")  // # is automatically removed
event.tagHashtags(["lightning", "zaps"])

// Add URLs
event.tagURL("https://nostr.com", petname: "Nostr Protocol")

// Add subject/title (for long-form content)
event.tagSubject("My Article Subject")
event.tagTitle("Article Title")

// Add images
event.tagImage("https://example.com/image.jpg", width: 800, height: 600)
```

### Addressable Events (NIP-33)

Tag parameterized replaceable events:

```swift
// Tag an addressable event (e.g., long-form content)
let article = NDKEvent(kind: 30023)  // Long-form content
article.tags = [["d", "my-article-slug"]]

event.tagAddressableEvent(article, relay: "wss://relay.com")
// Creates: ["a", "30023:pubkey:my-article-slug", "wss://relay.com"]
```

## Tag Queries

### Basic Queries

Retrieve tag values efficiently:

```swift
// Get all values at a specific position
let allHashtags = event.tagValues("t")  // ["nostr", "bitcoin"]
let allRelayHints = event.tagValues("e", at: 2)  // Relay URLs

// Get tags with specific markers
let rootTags = event.tags(withName: "e", marker: "root")
let replyTags = event.tags(withName: "e", marker: "reply")

// Get first matching tag
let rootTag = event.tag(withName: "e", marker: "root")
```

### Thread-Aware Queries

Navigate event threads easily:

```swift
// Thread navigation
let rootId = event.rootEventId          // ID of thread root
let replyToId = event.replyToEventId    // ID being replied to
let mentions = event.mentionedEventIds   // All mentioned event IDs

// Check thread status
if event.isReply {
    print("This is a reply")
} else if event.isRootPost {
    print("This is a root post")
}
```

### Content Queries

Extract specific content types:

```swift
// Get all hashtags
let hashtags = event.hashtags  // ["nostr", "bitcoin"]

// Get mentioned pubkeys
let mentions = event.mentionedPubkeys  // ["pubkey1", "pubkey2"]

// Get URLs with optional petnames
let urls = event.urls
for (url, petname) in urls {
    print("\(url) - \(petname ?? "No name")")
}

// Get addressable event references
let refs = event.addressableEventRefs
for ref in refs {
    print("Kind: \(ref.kind), Author: \(ref.pubkey), ID: \(ref.identifier)")
}

// Long-form content metadata
let subject = event.subject
let title = event.title

// Images
let images = event.imageURLs
for (url, dimensions) in images {
    print("Image: \(url) \(dimensions ?? "")")
}
```

## Thread Building

### Creating Replies

Build threaded conversations:

```swift
// Create a simple reply
let reply = originalPost.createReply(content: "Great post!")

// Reply maintains thread structure:
// - Tags the original event as "reply"
// - Preserves or creates root reference
// - Tags the original author
// - Copies relevant p tags for mentions

// Create reply with additional tags
let reply = originalPost.createReply(
    content: "I agree! #nostr",
    additionalTags: [["t", "nostr"]]
)
```

### Thread Structure

The reply builder handles NIP-10 thread structure:

```swift
// Root post
let root = NDKEvent(content: "Starting a thread")
// tags: []

// First reply
let reply1 = root.createReply(content: "First reply")
// tags: [
//   ["e", "root_id", "", "root"],
//   ["e", "root_id", "", "reply"],
//   ["p", "root_author"]
// ]

// Nested reply
let reply2 = reply1.createReply(content: "Reply to reply")
// tags: [
//   ["e", "root_id", "", "root"],      // Preserved root
//   ["e", "reply1_id", "", "reply"],   // Direct parent
//   ["p", "reply1_author"],
//   ["p", "root_author"]                // Mentioned participants
// ]
```

## Batch Operations

### Managing Multiple Tags

Efficient bulk tag operations:

```swift
// Remove all tags of a type
event.removeTags(withName: "t")  // Remove all hashtags

// Replace all tags of a type
let newHashtags = [["t", "nostr"], ["t", "bitcoin"]]
event.replaceTags(withName: "t", with: newHashtags)

// Add multiple tags at once
let additionalTags = [
    ["p", "pubkey1"],
    ["p", "pubkey2"],
    ["r", "https://example.com"]
]
event.addTags(additionalTags)
```

### Tag Maintenance

Clean up and validate tags:

```swift
// Remove duplicate tags
event.deduplicateTags()

// Remove invalid tags
event.removeInvalidTags()

// Both operations preserve tag order
```

## Tag Builder

For complex tag construction:

```swift
var builder = TagBuilder()

let tags = builder
    .event("event123", relay: "wss://relay.com", marker: "root")
    .event("event456", marker: "reply")
    .pubkey("pubkey123", relay: "wss://relay.com")
    .pubkey("pubkey456", petname: "Alice")
    .hashtag("nostr")
    .hashtag("bitcoin")
    .url("https://nostr.com", petname: "Nostr Protocol")
    .custom(["custom", "tag", "values"])
    .build()

event.tags = tags
```

## Filter Helpers

Enhanced filter creation:

```swift
var filter = NDKFilter()

// Add hashtag filters (automatically lowercased)
filter.addHashtagFilter("Nostr", "Bitcoin", "Lightning")

// Add URL filters
filter.addURLFilter("https://nostr.com", "https://bitcoin.org")

// Check for tag filters
if filter.hasTagFilter("t") {
    print("Filter includes hashtag criteria")
}
```

## Tag Validation

Ensure tag compliance:

```swift
// Validate individual tags
let tag = ["e", eventId]
if tag.isValid {
    event.addTag(tag)
}

// Validation rules:
// - "e", "p": Must have 64-character hex values
// - "a": Must follow kind:pubkey:d-tag format
// - "d", "t", "r": Must have a value
// - Empty tags are invalid
```

## Best Practices

1. **Use Tag Helpers**: Prefer type-safe helpers over manual array construction
2. **Validate User Input**: Always validate tags from external sources
3. **Preserve Thread Structure**: Use `createReply` for proper threading
4. **Handle Missing Data**: Use safe subscripts and optional properties
5. **Batch Operations**: Use bulk methods for multiple tag changes
6. **Deduplicate**: Remove duplicate tags before publishing
7. **Follow NIPs**: Ensure tag usage complies with relevant NIPs

## Common Patterns

### Hashtag Extraction
```swift
let hashtags = event.hashtags.map { "#\($0)" }.joined(separator: " ")
print("Topics: \(hashtags)")
```

### Thread Navigation
```swift
func getRootOfThread(event: NDKEvent) -> EventID? {
    return event.rootEventId ?? event.id
}
```

### Mention Detection
```swift
let isMentioned = event.mentionedPubkeys.contains(myPubkey)
```

### Reply Context
```swift
if let replyToId = event.replyToEventId {
    // Fetch and display the parent event
    let parent = await ndk.fetchEvent(replyToId)
}
```

## Migration from Raw Tags

Replace manual tag operations with helpers:

```swift
// Old way
event.tags.append(["e", eventId, "", "reply"])
event.tags.append(["p", pubkey])
event.tags.append(["t", hashtag.lowercased()])

// New way
event.tagReply(to: referencedEvent)
event.tag(user: NDKUser(pubkey: pubkey))
event.tagHashtag(hashtag)
```

## Performance Tips

1. **Use Specific Queries**: `event.hashtags` is faster than filtering all tags
2. **Cache Thread Roots**: Store `rootEventId` to avoid repeated lookups
3. **Batch Tag Updates**: Make multiple changes before deduplicating
4. **Validate Once**: Validate tags on creation, not on every access