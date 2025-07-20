# Declarative Data Access + Outbox Model Flow

## Example Scenario
App requests: `{ kinds: [1], authors: [pubkey1, pubkey2] }`
- pubkey1's outbox: relay1.com
- pubkey2's outbox: relay2.com

## Architecture Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                UI LAYER                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│  SwiftUI View                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ @StateObject private var feedData = NDKDataSource(                     │   │
│  │   filter: NDKFilter(kinds: [1], authors: [pubkey1, pubkey2])          │   │
│  │ )                                                                       │   │
│  │                                                                         │   │
│  │ List(feedData.data, id: \.id) { event in                              │   │
│  │   EventView(event: event)                                              │   │
│  │ }                                                                       │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                            │
│                                    │ 1. "I want this data"                      │
│                                    ▼                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                          DECLARATIVE DATA LAYER                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│  NDKDataSource                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ - @Published var data: [NDKEvent] = []                                 │   │
│  │ - @Published var isLoading: Bool = false                               │   │
│  │ - Automatic lifecycle management                                       │   │
│  │ - Reference counting for resource sharing                              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                            │
│                                    │ 2. "Manage this requirement"               │
│                                    ▼                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                       INTELLIGENT DATA COORDINATOR                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│  NDKDataManager (Actor)                                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ 3a. Check Cache First                                                  │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │ │ cache.queryEvents(filter) → [some events for pubkey1]          │   │   │
│  │ │ Missing: recent events from pubkey2                             │   │   │
│  │ └─────────────────────────────────────────────────────────────────┘   │   │
│  │                                                                         │   │
│  │ 3b. Determine Data Strategy                                             │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │ │ - Freshness required: within 5 minutes                         │   │   │
│  │ │ - Strategy: targeted relay fetching + subscription             │   │   │
│  │ │ - Resource sharing: check existing subscriptions               │   │   │
│  │ └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                            │
│                                    │ 4. "Where should I look for these authors?"│
│                                    ▼                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           OUTBOX INTELLIGENCE LAYER                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│  NDKOutboxResolver                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ 5. Resolve Author → Relay Mapping                                      │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │ │ Input: [pubkey1, pubkey2]                                       │   │   │
│  │ │                                                                 │   │   │
│  │ │ Query cache for kind:10002 (relay lists):                      │   │   │
│  │ │ - pubkey1 → ["wss://relay1.com", "wss://backup1.com"]          │   │   │
│  │ │ - pubkey2 → ["wss://relay2.com", "wss://backup2.com"]          │   │   │
│  │ │                                                                 │   │   │
│  │ │ Output: Smart relay routing plan                                │   │   │
│  │ └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                            │
│                                    │ 6. "Create targeted subscriptions"        │
│                                    ▼                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                         SUBSCRIPTION ORCHESTRATION                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│  NDKSubscriptionOrchestrator                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ 7. Create Optimized Subscription Plan                                  │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │ │ Subscription A: relay1.com                                      │   │   │
│  │ │ ┌─────────────────────────────────────────────────────────────┐ │   │   │
│  │ │ │ Filter: { kinds: [1], authors: [pubkey1] }                 │ │   │   │
│  │ │ │ Strategy: subscribe + backfill last 24h                    │ │   │   │
│  │ │ └─────────────────────────────────────────────────────────────┘ │   │   │
│  │ │                                                                 │   │   │
│  │ │ Subscription B: relay2.com                                      │   │   │
│  │ │ ┌─────────────────────────────────────────────────────────────┐ │   │   │
│  │ │ │ Filter: { kinds: [1], authors: [pubkey2] }                 │ │   │   │
│  │ │ │ Strategy: fetch recent only (user rarely posts)            │ │   │   │
│  │ │ └─────────────────────────────────────────────────────────────┘ │   │   │
│  │ └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                            │
│                                    │ 8. "Execute plan"                         │
│                                    ▼                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                            RELAY CONNECTION LAYER                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│  NDKRelayPool                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ 9. Manage Relay Connections                                             │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │ │ Connection Manager:                                             │   │   │
│  │ │ - Ensure relay1.com is connected                               │   │   │
│  │ │ - Ensure relay2.com is connected                               │   │   │
│  │ │ - Handle connection failures with fallbacks                    │   │   │
│  │ │ - Rate limiting and connection pooling                         │   │   │
│  │ └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                            │
│                                    │ 10. "Send targeted requests"              │
│                                    ▼                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              RELAY ENDPOINTS                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────────┐         ┌─────────────────────────────┐       │
│  │        relay1.com           │         │        relay2.com           │       │
│  │  ┌─────────────────────┐    │         │  ┌─────────────────────┐    │       │
│  │  │ REQ: subscription   │    │         │  │ REQ: one-shot fetch │    │       │
│  │  │ { kinds: [1],       │    │         │  │ { kinds: [1],       │    │       │
│  │  │   authors:[pubkey1] │    │         │  │   authors:[pubkey2],│    │       │
│  │  │   since: 24h ago }  │    │         │  │   since: 1h ago }   │    │       │
│  │  └─────────────────────┘    │         │  └─────────────────────┘    │       │
│  │            │                │         │            │                │       │
│  │            │ 11a. Events    │         │            │ 11b. Events    │       │
│  │            ▼                │         │            ▼                │       │
│  │  ┌─────────────────────┐    │         │  ┌─────────────────────┐    │       │
│  │  │ EVENT: note from    │    │         │  │ EVENT: note from    │    │       │
│  │  │ pubkey1 @ relay1    │    │         │  │ pubkey2 @ relay2    │    │       │
│  │  └─────────────────────┘    │         │  └─────────────────────┘    │       │
│  └─────────────────────────────┘         └─────────────────────────────┘       │
│                │                                       │                       │
│                │ 12a. Stream                          │ 12b. Batch             │
│                ▼                                       ▼                       │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                         INTELLIGENT CACHE + BROADCAST                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│  NDKSmartCache (Actor)                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ 13. Event Processing & Broadcasting                                     │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │ │ Events arrive from relays:                                      │   │   │
│  │ │ - pubkey1 events from relay1 → save to cache                  │   │   │
│  │ │ - pubkey2 events from relay2 → save to cache                  │   │   │
│  │ │                                                                 │   │   │
│  │ │ Cache observation triggers:                                     │   │   │
│  │ │ - Notify all DataSources watching this filter                  │   │   │
│  │ │ - Apply deduplication and ordering                             │   │   │
│  │ │ - Track data freshness and quality metrics                     │   │   │
│  │ └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                            │
│                                    │ 14. "Broadcast to observers"              │
│                                    ▼                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           REACTIVE UPDATE PROPAGATION                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│  Back to NDKDataSource                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ 15. Automatic UI Updates                                                │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐   │   │
│  │ │ @Published data updates automatically:                          │   │   │
│  │ │ - New events from pubkey1 (via relay1)                        │   │   │
│  │ │ - New events from pubkey2 (via relay2)                        │   │   │
│  │ │ - Merged, deduplicated, and sorted                             │   │   │
│  │ │ - SwiftUI recomposes view automatically                        │   │   │
│  │ └─────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                    │                                            │
│                                    │ 16. "Display updated data"                │
│                                    ▼                                            │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                                UI LAYER                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│  SwiftUI View (Updated Automatically)                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ List displays:                                                          │   │
│  │ - Note from pubkey1 (fetched from relay1)                             │   │
│  │ - Note from pubkey2 (fetched from relay2)                             │   │
│  │ - Sorted chronologically                                               │   │
│  │ - Updates live as new events arrive                                    │   │
│  │                                                                         │   │
│  │ No manual subscription management needed!                              │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Key Architectural Benefits

### 1. **Outbox Intelligence**
- System automatically routes requests to the right relays
- No more "spray and pray" to all relays  
- Dramatically reduces bandwidth and relay load

### 2. **Resource Optimization**
- Multiple UI components requesting same data share subscriptions
- Intelligent strategies per author (some need live subscriptions, others just periodic fetches)
- Automatic cleanup when UI components disappear

### 3. **Cache as Central Coordinator** 
- All data flows through cache with observation
- Deduplication across relay sources
- Consistent state across entire app

### 4. **Declarative Simplicity**
- UI just declares what data it needs
- All complexity hidden in smart middle layers
- Automatic lifecycle management

### 5. **Network Efficiency**
- Targeted requests based on outbox model
- Smart strategies (subscribe vs fetch) per use case
- Connection pooling and rate limiting

This architecture transforms Nostr apps from "subscription managers" to "data declarers" while making outbox routing completely transparent to developers.