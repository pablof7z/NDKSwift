# Offline Demo TUI: Unpublished Events Display

## Summary

Enhance the OfflineDemo TUI to show unpublished events with per-relay status and integrate real-time publishing notifications into the activity log.

## Requirements

1. **Unpublished Events Section** - New section showing each unpublished event with per-relay status
2. **Activity Log Enhancement** - Show per-relay publish notifications in real-time
3. **Event-Based Updates** - Replace polling with reactive streams

## Design

### TUI Layout: Unpublished Events Section

```
╠══════════════════════════════════════════════════════════════════════════════╣
║ UNPUBLISHED EVENTS                                                           ║
║──────────────────────────────────────────────────────────────────────────────║
║  abc12345 k:1                                                                ║
║    ✓ relay.damus.io                                                          ║
║    ✓ nos.lol                                                                 ║
║    ⏳ purplepag.es                                                            ║
║    ✗ relay.nostr.band (timeout)                                              ║
║  def67890 k:1111                                                             ║
║    ⏳ relay.damus.io                                                          ║
║    ⏳ nos.lol                                                                 ║
╠══════════════════════════════════════════════════════════════════════════════╣
```

**Legend:**
- `✓` green = published successfully
- `⏳` yellow = pending (waiting to publish)
- `✗` red = failed (with reason in parens)

### Data Model Changes

**TUI State:**
```swift
// Replace unpublishedCount with full records
struct UnpublishedEventRecord {
    let eventId: String
    let kind: Int
    var relayStates: [String: RelayPublishState] // relay URL -> state
}

enum RelayPublishState {
    case pending
    case published
    case failed(reason: String)
}

actor TUIState {
    var unpublishedEvents: [String: UnpublishedEventRecord] = [:] // eventId -> record
}
```

### Event-Based Updates (No Polling)

**UnpublishedStore Changes:**
```swift
enum UnpublishedChange {
    case eventAdded(eventId: String, kind: Int, targetRelays: [String])
    case relayPublished(eventId: String, relay: String)
    case relayFailed(eventId: String, relay: String, reason: String)
    case eventRemoved(eventId: String)
}

// Add AsyncStream
let changes: AsyncStream<UnpublishedChange>
```

**TUI Consumption:**
```swift
// Replace polling task with:
Task {
    for await change in await cache.unpublishedChanges {
        await handleUnpublishedChange(change)
        await refreshUI()
    }
}

// Also listen to publish events from NDK:
Task {
    for await publishEvent in await ndk.pool.publishEvents {
        await tuiState.log("Event \(publishEvent.eventId.prefix(8)) → \(publishEvent.relayUrl) \(publishEvent.success ? "✓" : "✗")")
        await refreshUI()
    }
}
```

### Activity Log Format

Per-relay publish notifications:
```
12:34:56 Event abc12345 → relay.damus.io ✓
12:34:56 Event abc12345 → nos.lol ✓
12:34:57 Event abc12345 → purplepag.es ✗ (timeout)
```

## Implementation Tasks

1. [x] Add per-relay publish notifications to NDK (`NDKPool.publishEvents`)
2. [x] Add `UnpublishedChange` AsyncStream to `UnpublishedStore`
3. [x] Expand TUI state to store unpublished event details with per-relay status
4. [x] Add UNPUBLISHED EVENTS section to TUI renderer
5. [x] Hook activity log into `ndk.pool.publishEvents`
6. [x] Replace polling with reactive stream consumption
7. [ ] Test the TUI with unpublished events display

## NDK Changes (Complete)

- Added `NDKRelayPublishEvent` struct in `NDKPool.swift`
- Added `publishEvents` AsyncStream to `NDKPool`
- Added `emitPublishEvent()` method
- Modified `NDKEventManager` to emit on publish success/failure
- Extended to `publishQueuedEvents()` and `retryAuthenticatedEvents()`
