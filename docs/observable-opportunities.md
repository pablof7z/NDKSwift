# Observable Pattern Opportunities in NDKSwift

## Executive Summary

This document analyzes NDKSwift to identify areas that could benefit from the same reactive `@Observable` pattern we implemented for user profiles. The profile implementation demonstrates that wrapping live-updating Nostr data in observable instances provides:

1. **Zero boilerplate** - Developers just access properties, no manual subscription management
2. **Automatic reactivity** - SwiftUI views re-render when data updates
3. **Instance caching** - Same data = same observable instance (efficient)
4. **Stream-based updates** - Data arrives progressively as relays respond

## What We Built: NDKProfile

The profile implementation shows the target pattern:

```swift
// Observable class with auto-updating properties
@Observable
@MainActor
public final class NDKProfile {
    public private(set) var metadata: NDKUserMetadata?
    public var displayName: String { /* derived */ }
    public var pictureURL: URL? { /* derived */ }
    // ... etc
}

// Accessed via cached property on NDKUser
let user = ndk.getUser(pubkey)
let profile = user.profile  // Returns cached NDKProfile instance
Text(profile.displayName)   // Auto-updates when metadata arrives
```

**Key characteristics:**
- Lives on MainActor (SwiftUI friendly)
- Caches instances (one per pubkey)
- Streams kind 0 metadata updates via internal subscription
- Provides computed properties for ergonomic access
- Auto-cancels subscription on deinit

---

## Opportunity 1: Observable Contact List / Follows

### What It Is
User's follow list (kind 3 contacts event), showing who a user follows.

### Current API
```swift
// Developers must manually fetch and track
let user = ndk.getUser(somePubkey)
let follows = try await user.follows()  // Returns Set<NDKUser>
let isFollowing = try await user.follows(otherUser)  // Bool check

// No reactive updates - must re-fetch to get changes
```

### Proposed Observable API
```swift
@Observable
@MainActor
public final class NDKContactList {
    public private(set) var follows: Set<PublicKey> = []
    public private(set) var lastUpdated: Date?

    // Convenience accessors
    public var count: Int { follows.count }
    public func contains(_ pubkey: PublicKey) -> Bool
    public func users(ndk: NDK) -> [NDKUser]  // Convert to NDKUser array
}

// Access pattern
extension NDKUser {
    @MainActor
    public var contactList: NDKContactList? {
        ndk.contactListCache.get(pubkey)
    }
}

// Usage in SwiftUI
let user = ndk.getUser(pubkey)
if let contacts = user.contactList {
    Text("Following \(contacts.count) people")
    ForEach(contacts.users(ndk: ndk)) { followedUser in
        Text(followedUser.profile?.displayName ?? "...")
    }
}
```

### Benefits
- **Real-time follow list updates** - App sees changes when user follows/unfollows
- **Efficient checks** - `contactList.contains(pubkey)` is O(1)
- **Automatic caching** - Same instance shared across all views
- **Reactive UI** - Follow counts/lists update automatically
- **Works with session data** - NDKSessionData already tracks current user's follows, this extends to any user

### Implementation Notes
- Stream kind 3 events for the pubkey
- Keep most recent event's p-tags as the follow set
- LRU cache similar to NDKProfileCache
- Could integrate with existing NDKSessionData for current user

---

## Opportunity 2: Observable Relay List

### What It Is
User's preferred relay list (NIP-65, kind 10002), specifying read/write relays.

### Current API
```swift
// Manual fetch required
let relayList = try await user.fetchRelayList()
let readRelays = relayList?.readRelays ?? []
let writeRelays = relayList?.writeRelays ?? []

// NDKRelayListManager exists but is @Observable at manager level, not per-user
```

### Proposed Observable API
```swift
@Observable
@MainActor
public final class NDKRelayListData {
    public private(set) var readRelays: [RelayURL] = []
    public private(set) var writeRelays: [RelayURL] = []
    public private(set) var allRelays: [NDKRelayInfo] = []
    public private(set) var lastUpdated: Date?

    public func canRead(_ relay: RelayURL) -> Bool
    public func canWrite(_ relay: RelayURL) -> Bool
}

// Access pattern
extension NDKUser {
    @MainActor
    public var relayListData: NDKRelayListData? {
        ndk.relayListCache.get(pubkey)
    }
}

// Usage
let user = ndk.getUser(pubkey)
if let relays = user.relayListData {
    Text("Prefers \(relays.readRelays.count) read relays")
    ForEach(relays.allRelays) { relayInfo in
        RelayRow(relay: relayInfo)
    }
}
```

### Benefits
- **Outbox model support** - Easily show which relays to use for a user
- **Real-time updates** - See when users change relay preferences
- **Discovery UI** - Build relay exploration features
- **Simplified API** - Access relay data same way as profiles
- **Network efficiency** - Cached per-user, shared across features

### Implementation Notes
- Stream kind 10002 events
- Parse relay tags into read/write sets
- Cache instances per pubkey
- Works alongside global NDKRelayListManager (which manages current user's relay list)

---

## Opportunity 3: Observable Event Reactions/Stats

### What It Is
Aggregate statistics for an event: reaction count, zap total, repost count.

### Current API
```swift
// Developers must manually subscribe and aggregate
let event: NDKEvent = ...
let filter = NDKFilter(kinds: [EventKind.reaction], tags: ["e": [event.id]])
let subscription = ndk.subscribe(filter: filter)
var likeCount = 0
for await reaction in subscription.events {
    if reaction.content == "+" { likeCount += 1 }
}
// No built-in aggregation, no caching
```

### Proposed Observable API
```swift
@Observable
@MainActor
public final class NDKEventStats {
    public private(set) var reactionCounts: [String: Int] = [:]  // emoji -> count
    public private(set) var repostCount: Int = 0
    public private(set) var zapTotal: Int64 = 0  // Total sats zapped
    public private(set) var zapCount: Int = 0
    public private(set) var replyCount: Int = 0

    // Convenience
    public var likeCount: Int { reactionCounts["+"] ?? 0 }
    public var totalReactions: Int { reactionCounts.values.reduce(0, +) }
}

// Access pattern
extension NDKEvent {
    @MainActor
    public var stats: NDKEventStats? {
        // Would need NDK reference on events, or pass through context
        // OR: ndk.eventStatsCache.get(eventId)
    }
}

// Usage
Text("❤️ \(event.stats?.likeCount ?? 0)")
Text("⚡ \(event.stats?.zapTotal ?? 0) sats")
Text("🔄 \(event.stats?.repostCount ?? 0)")
```

### Benefits
- **Live reaction counts** - Likes, reposts update in real-time
- **Zap totals** - Show accumulated zap amounts
- **Reply threading** - Track conversation depth
- **Social proof** - Display engagement metrics
- **Efficient aggregation** - Calculate once, share everywhere

### Implementation Notes
- Subscribe to kinds 7 (reaction), 6/16 (repost), 9735 (zap receipt), 1 (replies with e-tag)
- Aggregate by event ID
- LRU cache to avoid memory bloat
- Could batch-load stats for feed items
- Challenge: Events don't have NDK reference - may need context passing

---

## Opportunity 4: Observable NIP-05 Verification Status

### What It Is
NIP-05 verification status for a user's claimed identifier.

### Current API
```swift
// Manual verification
let user = ndk.getUser(pubkey)
if let nip05 = user.profile?.metadata?.nip05 {
    let isVerified = try await user.verifyNIP05()
    // Must manually check, no caching, no reactive updates
}
```

### Proposed Observable API
```swift
@Observable
@MainActor
public final class NDKNIP05Status {
    public private(set) var identifier: String?
    public private(set) var isVerified: Bool = false
    public private(set) var isVerifying: Bool = false
    public private(set) var lastChecked: Date?
    public private(set) var nip46Relays: [String]?
}

// Access via profile or user
extension NDKProfile {
    public var nip05Status: NDKNIP05Status {
        // Returns cached status, triggers verification if stale
    }
}

// Usage
if let status = user.profile?.nip05Status {
    HStack {
        Text(status.identifier ?? "")
        if status.isVerified {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.blue)
        }
    }
}
```

### Benefits
- **Automatic verification** - Triggered on first access, cached after
- **Visual feedback** - Show verification badge reactively
- **Stale checking** - Re-verify after 24h automatically
- **NIP-46 support** - Expose signer relays for bunker connection
- **Trust indicators** - Build reputation features

### Implementation Notes
- Integrate with existing NIP05Manager
- Trigger verification on first access or after TTL
- Cache results per pubkey
- Could be part of NDKProfile or separate cache
- Leverage existing NIP05CacheEntry infrastructure

---

## Opportunity 5: Observable Mute List

### What It Is
User's mute list (kind 10000), showing muted pubkeys, threads, and keywords.

### Current API
```swift
// NDKSessionData has muteList for current user
// No API for viewing other users' mute lists reactively
let sessionData = ndk.sessionData
let isMuted = sessionData?.muteList.contains(somePubkey) ?? false
```

### Proposed Observable API
```swift
@Observable
@MainActor
public final class NDKMuteList {
    public private(set) var mutedPubkeys: Set<PublicKey> = []
    public private(set) var mutedThreads: Set<EventID> = []
    public private(set) var mutedWords: Set<String> = []
    public private(set) var mutedMints: Set<String> = []

    public func isMuted(pubkey: PublicKey) -> Bool
    public func isMuted(eventId: EventID) -> Bool
    public func isMuted(text: String) -> Bool  // Check for muted words
}

// Access pattern
extension NDKUser {
    @MainActor
    public var muteList: NDKMuteList? {
        ndk.muteListCache.get(pubkey)
    }
}

// Usage
if user.muteList?.isMuted(pubkey: somePubkey) == true {
    // Hide content
}
```

### Benefits
- **Content filtering** - Build sophisticated mute/block features
- **Privacy respect** - Honor user preferences
- **WoT integration** - Combine with web of trust scoring
- **Real-time updates** - Mute lists update live
- **Mint blacklisting** - Filter cashu mints

### Implementation Notes
- Stream kind 10000 events
- Parse both public tags and encrypted content
- May need decryption for private mute lists
- Cache per user
- Could integrate with NDKSessionData for current user

---

## Opportunity 6: Observable Zap Splits / Recipients

### What It Is
Zap split configuration from an event or user's metadata (NIP-57).

### Current API
```swift
// Must parse zap tags manually
let event: NDKEvent = ...
let zapTags = event.tags.filter { $0.first == "zap" }
// Parse splits, percentages manually
```

### Proposed Observable API
```swift
@Observable
@MainActor
public final class NDKZapSplits {
    public struct Split {
        let pubkey: PublicKey
        let relay: RelayURL?
        let weight: Int
        let percentage: Double
    }

    public private(set) var splits: [Split] = []
    public private(set) var primaryRecipient: RecipientZapInfo?

    public func recipientFor(amount: Int64) -> [PublicKey: Int64]  // Distribution map
}

// Access pattern
extension NDKEvent {
    @MainActor
    public var zapSplits: NDKZapSplits? {
        // Parse from event tags, cache by event ID
    }
}

// Usage
if let splits = event.zapSplits {
    Text("Zap split: \(splits.splits.count) recipients")
    ForEach(splits.splits) { split in
        Text("\(split.percentage)% to \(split.pubkey)")
    }
}
```

### Benefits
- **Payment transparency** - Show who gets paid
- **Multi-recipient zaps** - Support value splits
- **Creator monetization** - Display payment flows
- **Trust building** - Transparency in value distribution

### Implementation Notes
- Parse zap tags from events
- Calculate percentages from weights
- Cache per event ID
- Integrate with existing RecipientZapInfo and zap manager

---

## Opportunity 7: Observable Relay Connection Status

### What It Is
Real-time connection status and health metrics for relays.

### Current API
```swift
// Relay has stateStream but requires manual observation
let relay = ndk.pool.relays.first
Task {
    for await state in relay.stateStream {
        // Handle state changes
    }
}
```

### Proposed Observable API
```swift
@Observable
@MainActor
public final class NDKRelayStatus {
    public private(set) var connectionState: NDKRelayConnectionState = .disconnected
    public private(set) var stats: NDKRelayStats
    public private(set) var info: NDKRelayInformation?
    public private(set) var activeSubscriptions: [NDKRelaySubscriptionInfo] = []

    // Computed
    public var isConnected: Bool
    public var latency: TimeInterval?
    public var reliability: Double  // successfulConnections / connectionAttempts
}

// Access pattern
extension NDKRelay {
    @MainActor
    public var observableStatus: NDKRelayStatus {
        // Bridge existing stateStream to observable
    }
}

// Usage
ForEach(ndk.pool.relays) { relay in
    HStack {
        StatusIndicator(state: relay.observableStatus.connectionState)
        Text(relay.url)
        if let latency = relay.observableStatus.latency {
            Text("\(Int(latency * 1000))ms")
        }
    }
}
```

### Benefits
- **Health monitoring** - Build relay status dashboards
- **Connection debugging** - See why connections fail
- **Performance metrics** - Track latency, throughput
- **User transparency** - Show network status to users
- **Reliability scoring** - Make intelligent relay choices

### Implementation Notes
- Bridge existing NDKRelay.stateStream to @Observable
- Relay already has comprehensive state tracking
- Would be MainActor wrapper around existing actor-based state
- Could use AsyncStream -> Observation bridge pattern

---

## Opportunity 8: Observable Notification/Mention Feed

### What It Is
Aggregated notifications for the current user (mentions, replies, zaps, reactions).

### Current API
```swift
// Developers must manually build notification filters
let filter = NDKFilter(
    kinds: [1, 7, 9735],  // replies, reactions, zaps
    tags: ["p": [myPubkey]]
)
let sub = ndk.subscribe(filter: filter)
// Manual aggregation and sorting
```

### Proposed Observable API
```swift
@Observable
@MainActor
public final class NDKNotifications {
    public struct Notification: Identifiable {
        let id: String
        let type: NotificationType
        let event: NDKEvent
        let timestamp: Date
        var isRead: Bool
    }

    public enum NotificationType {
        case mention, reply, reaction, zap, repost, follow
    }

    public private(set) var notifications: [Notification] = []
    public private(set) var unreadCount: Int = 0

    public func markRead(_ id: String)
    public func markAllRead()
}

// Access pattern
extension NDK {
    @MainActor
    public var notifications: NDKNotifications? {
        guard let sessionData else { return nil }
        return notificationsCache.get(sessionData.pubkey)
    }
}

// Usage
if let notifications = ndk.notifications {
    Badge("\(notifications.unreadCount)")
    ForEach(notifications.notifications) { notification in
        NotificationRow(notification)
    }
}
```

### Benefits
- **Unified notification center** - All notification types in one place
- **Read/unread tracking** - Persistent read state
- **Real-time updates** - Notifications appear instantly
- **Type filtering** - Filter by notification type
- **Engagement** - Keep users engaged with timely updates

### Implementation Notes
- Subscribe to multiple kinds with p-tag filter for current user
- Aggregate and deduplicate events
- Sort by timestamp (descending)
- Store read state locally (UserDefaults or cache)
- Could batch-load recent notifications on startup
- Challenge: Needs current user context

---

## Implementation Priority

### Tier 1: High Impact, Low Complexity
1. **Observable Contact List** - Common use case, clear API
2. **Observable NIP-05 Status** - Integrates with existing profile system
3. **Observable Relay List** - Extends profile pattern naturally

### Tier 2: High Impact, Medium Complexity
4. **Observable Event Stats** - Requires aggregation, caching strategy
5. **Observable Notifications** - Needs read state management
6. **Observable Mute List** - May need decryption handling

### Tier 3: Specialized Use Cases
7. **Observable Relay Status** - Bridge existing AsyncStream
8. **Observable Zap Splits** - Parse-heavy, niche use case

---

## General Implementation Pattern

All opportunities would follow this structure:

```swift
// 1. Observable class on MainActor
@Observable
@MainActor
public final class NDKObservableX {
    public private(set) var data: DataType
    private weak var ndk: NDK?
    private let cancellation = CancellationHandle()

    init(identifier: String, ndk: NDK) {
        self.ndk = ndk
        startObservation()
    }

    deinit {
        cancellation.cancel()
    }

    private func startObservation() {
        Task {
            let filter = NDKFilter(/* appropriate filter */)
            let subscription = ndk.subscribe(filter: filter)

            for await event in subscription.events {
                guard !cancellation.isCancelled else { break }
                // Update data
            }
        }
    }
}

// 2. LRU Cache
@MainActor
public final class NDKObservableXCache {
    private var cache: [String: NDKObservableX] = [:]
    // LRU eviction logic...
}

// 3. Access point
extension NDKUser {  // or NDKEvent, NDK, etc.
    @MainActor
    public var observableX: NDKObservableX? {
        ndk.observableXCache.get(identifier)
    }
}
```

---

## Design Considerations

### When to Use Observable Pattern

**Good candidates:**
- Data that changes over time
- Data accessed repeatedly across the app
- Data that benefits from caching
- Data that maps to a single identifier (pubkey, event ID)
- Data that naturally fits SwiftUI's reactive model

**Poor candidates:**
- One-time fetches (use async/await directly)
- Highly dynamic filters (use NDKSubscription)
- Complex aggregations requiring custom logic
- Data without clear cache key

### Memory Management

All observable caches should:
- Use LRU eviction (similar to NDKProfileCache)
- Set reasonable max sizes (100-500 instances)
- Cancel subscriptions on deinit
- Use weak NDK references to avoid retain cycles

### SwiftUI Integration

The observable pattern excels in SwiftUI:
```swift
struct UserCard: View {
    let user: NDKUser

    var body: some View {
        VStack {
            // Profile data - auto-updates
            AsyncImage(url: user.profile?.pictureURL)
            Text(user.profile?.displayName ?? "...")

            // Follow count - auto-updates
            if let contacts = user.contactList {
                Text("\(contacts.count) following")
            }

            // Relay preferences - auto-updates
            if let relays = user.relayListData {
                Text("\(relays.readRelays.count) relays")
            }

            // Verification - auto-updates
            if user.profile?.nip05Status.isVerified == true {
                Image(systemName: "checkmark.seal.fill")
            }
        }
        // Zero boilerplate - it all just works
    }
}
```

---

## Conclusion

The observable pattern we implemented for profiles can be extended to many other Nostr data types. The highest-value opportunities are:

1. **Contact lists** - Essential for social features
2. **Relay lists** - Critical for outbox model
3. **Event statistics** - Drive engagement metrics
4. **Notifications** - Keep users engaged
5. **NIP-05 verification** - Build trust

Each follows the same pattern: wrap live-updating Nostr data in a cached, observable instance that developers can access with zero boilerplate. This makes NDKSwift feel "magical" - data just appears and updates automatically.

The key is identifying data that is:
- **Frequently accessed** (benefits from caching)
- **Keyed by identifier** (pubkey, event ID, etc.)
- **Changes over time** (benefits from subscriptions)
- **Simple to represent** (clear API surface)

By applying this pattern systematically, we can make NDKSwift dramatically more ergonomic while maintaining its powerful low-level capabilities.
