# Feed Navigation Redesign

## Summary

Replace the duplicate "Olas" header with a tappable feed selector dropdown. Remove the teal navigation bar title entirely. The bold "Olas" text becomes a menu that lets users switch between:

- **Following** - Posts from followed authors (current behavior)
- **Relay feeds** - Unfiltered posts from curated relays (fetched via NIP-11 for display names)

## Changes

### Remove
- Navigation bar title (`.navigationTitle("Olas")`)
- Toolbar item with teal "Olas" text

### Add
- `FeedMode` enum: `.following` | `.relay(url: String)`
- NIP-11 metadata fetcher for relay names
- Menu-based feed selector showing "Following ▾" or "[Relay Name] ▾"

### Curated Relays
- `wss://relay.divine.video`

## Files

1. **FeedView.swift** - Replace static title with Menu component
2. **FeedViewModel.swift** - Add feedMode, modify subscription logic
3. **RelayMetadata.swift** (new) - NIP-11 fetcher with caching
4. **FeedMode.swift** (new) - Enum for feed modes

## Behavior

- **Following mode**: Filter by authors user follows, use NDK's connected relays
- **Relay mode**: No author filter, connect to specific relay, show all kind:20 posts
- Switching modes: Clear posts, stop subscription, start new subscription with new filter/relay
