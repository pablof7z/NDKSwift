# Relay Intelligence Layer Design

## Problem Statement

Relay selection in Nostr is nuanced. Different operations require different relays:
- Publishing needs the author's outbox + recipients' inboxes
- Fetching needs the author's outbox or relay hints
- DMs need specialized DM relays
- Discovery needs indexer relays

Currently, developers must understand these nuances to build reliable apps. NDKSwift should encode this intelligence so apps "just work" without developers thinking about relay selection.

## Design Goals

1. **Invisible by default** - Apps call `publish()` or `fetch()` and NDK handles relay selection
2. **Progressive execution** - Don't wait for complete relay discovery; act on what's known, expand as more is discovered
3. **Learning system** - NDK gets smarter over time by observing where users/events are found
4. **Composable** - Clear separation between intelligence (decision-making) and pool management (connections)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    App / Developer                       │
│              ndk.publish(event)                          │
│              ndk.fetch(filter)                           │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│               Relay Intelligence Layer                   │
│                                                          │
│   ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  │
│   │   Hint      │  │  NIP-65/51   │  │   Relay      │  │
│   │   Index     │  │    Cache     │  │   Health     │  │
│   └─────────────┘  └──────────────┘  └──────────────┘  │
│                                                          │
│         Returns: AsyncStream<RelayURL>                   │
│         (emits relays progressively as discovered)       │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    Pool Manager                          │
│                                                          │
│   - Manages connections (no decision-making)             │
│   - Connects on demand                                   │
│   - Usage-based eviction for non-persistent connections  │
│   - Core relays marked persistent (never evicted)        │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  Relay Connections                       │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. Relay Intelligence Layer

The brain of the system. Encodes all relay selection rules.

**Responsibilities:**
- Maintain hint index (learned observations)
- Cache NIP-65/51 relay lists
- Track relay health (success/failure rates)
- Answer "which relays for X?" queries

**Interface:**
```swift
protocol RelayIntelligence {
    func relaysForPublishing(_ event: NDKEvent) -> AsyncStream<RelayURL>
    func relaysForFetching(_ filter: NDKFilter) -> AsyncStream<RelayURL>
    func relaysForUser(_ pubkey: String, purpose: RelayPurpose) -> AsyncStream<RelayURL>
}

enum RelayPurpose {
    case inbox   // Where to send content TO this user
    case outbox  // Where to find content FROM this user
    case dm      // DM-specific relays
}
```

**Query Logic:**

| Query | Logic |
|-------|-------|
| Publishing an event | My outbox + recipients' inboxes (from p-tags) + hint relays from e-tags |
| Fetching a user's content | Their outbox (NIP-65 cache → indexer lookup → hints) |
| Fetching a specific event | Hints first → author's outbox → indexer → app relays |
| Listening for mentions | My inbox relays |
| Sending/receiving DMs | Both parties' DM relays (kind 10050) → fall back to inboxes |

**Progressive Resolution:**

The `AsyncStream<RelayURL>` return type is key:
- Emits known relays immediately (from cache, core pools)
- Emits discovered relays as they're found (from indexer queries)
- Closes when discovery is complete

Callers iterate and act on each relay as it's emitted. They don't wait for complete discovery.

### 2. Hint Index

The learning component. NDK gets smarter over time.

**Storage:**

| Key | Value | Source |
|-----|-------|--------|
| Pubkey → relays | "I've seen this user at these relays" | Event observations, NIP-19 decoding |
| EventID → relays | "I've seen this event at these relays" | Event observations, NIP-19 decoding |
| Address (kind:pubkey:d) → relays | "I've seen this replaceable event here" | Event observations, NIP-19 decoding |

**Learning triggers:**
1. NIP-19 decoding - `nevent1`, `nprofile1`, `naddr1` with relay hints
2. Event arrival - Event from relay X → record "author seen at X"
3. Successful fetch - Found event at relay X → record it
4. NIP-65 fetch - User's relay list → index those relays

**Characteristics:**
- Bounded size (LRU eviction)
- Thread-safe (actor)
- Optional persistence for faster cold start
- Future: recency weighting, confidence scores (not in initial implementation)

### 3. Pool Manager

Manages relay connections. No decision-making.

**Interface:**
```swift
protocol NDKPoolManager {
    func connections(for urls: Set<RelayURL>) async -> [NDKRelayConnection]
    func markUsed(_ urls: Set<RelayURL>)
    func markPersistent(_ urls: Set<RelayURL>)
    func removePersistent(_ urls: Set<RelayURL>)
}
```

**Behavior:**
- Connects on demand when relays are requested
- Tracks last-used timestamp per connection
- Evicts idle connections (except those marked persistent)
- Respects max connection limit (configurable, default ~20-30)
- Core relays marked persistent at app startup / user login

**Core Relays** (marked persistent by intelligence layer or app):

| Pool | Source | When Set |
|------|--------|----------|
| Indexer | App configuration | App startup |
| App | App configuration | App startup |
| Inbox | Current user's NIP-65 read | User login |
| Outbox | Current user's NIP-65 write | User login |

All other relays go through the dynamic pool with usage-based lifecycle.

### 4. NIP-65/51 Cache

Caches user relay preferences fetched from the network.

**Cached relay list types:**

| Kind | Purpose |
|------|---------|
| 10002 | NIP-65 advertised relay list (inbox/outbox) |
| 10050 | DM relay list |
| 10007 | Search relays |
| 10086 | Indexer relays |
| 10006 | Blocked relays |

**Cache behavior:**
- Fetched via indexer relays when needed
- Cached with TTL (configurable)
- Entries indexed into hint index

## Execution Model

### Publishing

```
1. App calls ndk.publish(event)

2. Event saved to cache as "unpublished"

3. Intelligence layer returns AsyncStream<RelayURL>:
   - Immediately emits: my outbox relays (known)
   - Background: discovers recipients' inbox relays
   - Emits each as discovered

4. For each relay emitted:
   - Pool manager ensures connection
   - Publish event to relay
   - Track confirmation

5. When all required relays confirm → mark as published
```

**Key insight:** Publishing starts immediately on known relays. Discovery happens in parallel. No waiting.

### Subscribing

```
1. App calls ndk.subscribe(filter)

2. Intelligence layer returns AsyncStream<RelayURL>:
   - Immediately emits: relevant connected relays
   - Background: discovers additional relays if needed
   - Emits each as discovered

3. For each relay emitted:
   - Pool manager ensures connection
   - Start subscription on that relay

4. Subscription is "living":
   - Expands to new relays as they're discovered
   - If intelligence later determines "also need relay X" → add it
```

**Key insight:** Subscriptions start immediately. They grow as more relays become available.

### Fetching Specific Event

```
1. App calls ndk.fetchEvent(eventId, hints: [...])

2. Intelligence layer returns AsyncStream<RelayURL>:
   - First: relay hints from parameter
   - Then: hints from index
   - Then: author's outbox (if known)
   - Then: indexer relays
   - Then: app relays

3. Fetch attempts each relay in order
   - Return on first success
   - Record successful relay in hint index

4. If all fail → return nil
```

## Rules Encoded

### Publishing Rules

1. Always send to my outbox relays
2. If mentioning someone (p-tag with <10 recipients), send to their inbox
3. If replying to an event (e-tag), include hint relays from that tag
4. For profile metadata (kind 0) and relay lists (kind 10002), broadcast widely
5. For DMs (gift wrap), send to recipient's DM relays → inbox fallback

### Fetching Rules

1. For specific event: hints → author outbox → indexer → app relays
2. For user's content: their outbox relays
3. For mentions of me: my inbox relays
4. For DMs: my DM relays → inbox fallback

### Discovery Rules

1. Check NIP-65 cache first
2. Check hint index second
3. Query indexer relays for kind 10002
4. Fall back to app relays / bootstrap

### Fallback Chain

```
NIP-65 cache
    ↓ (miss)
Hint index
    ↓ (miss)
Indexer relays (fetch kind 10002)
    ↓ (miss)
App relays / bootstrap
```

## Configuration

```swift
struct NDKRelayConfig {
    // Indexer relays for discovery
    var indexerRelays: Set<RelayURL> = [
        "wss://purplepag.es",
        "wss://relay.nostr.band"
    ]

    // App's default relays
    var appRelays: Set<RelayURL> = []

    // Pool limits
    var maxConnections: Int = 30
    var idleTimeout: TimeInterval = 300 // 5 minutes

    // Cache settings
    var nip65CacheTTL: TimeInterval = 3600 // 1 hour
    var hintIndexMaxSize: Int = 10000
}
```

## Future Enhancements (Not in Initial Implementation)

1. **Hint confidence scoring** - Recent observations weighted higher
2. **Relay health scoring** - Prefer reliable relays
3. **Hint persistence** - Survive app restarts
4. **Proxy relay support** - Route all queries through proxy when configured
5. **Search relay integration** - Use kind 10007 for search operations

## Migration Path

NDKSwift already has:
- NIP-65 support in `NDKOutboxManager`
- Relay hints from NIP-19 in `NDKFetchedEvent`
- Relay selection in `NDKRelaySelector`
- Pool management in `NDKPool`

The migration:
1. Extract hint tracking into dedicated `HintIndex`
2. Unify relay selection logic into `RelayIntelligence`
3. Refactor pool to support persistent marking and usage-based eviction
4. Change publish/fetch interfaces to use progressive relay resolution
5. Update existing code to use new components
