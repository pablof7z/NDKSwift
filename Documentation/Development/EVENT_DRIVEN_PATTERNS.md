# Event-Driven Patterns in NDKSwift

This guide demonstrates best practices for event-driven development with NDKSwift, focusing on when to use subscriptions vs fetchEvents.

## Core Principle

**Prefer subscriptions over fetchEvents**. Nostr is designed as a real-time, event-driven protocol. Your code should reflect this by processing events as they arrive rather than waiting for complete datasets.

## Pattern Examples

### 1. Loading User Profiles (Reactive UI)

❌ **Anti-pattern: Sequential Fetching**
```swift
// DON'T: This creates N sequential subscriptions
@MainActor
class ProfileListViewModel: ObservableObject {
    @Published var profiles: [String: NDKUserProfile] = [:]
    
    func loadProfiles(pubkeys: [String]) async {
        for pubkey in pubkeys {
            // This blocks for each user!
            let events = try? await ndk.fetchEvents(
                NDKFilter(authors: [pubkey], kinds: [0])
            )
            if let profile = parseProfile(from: events?.first) {
                profiles[pubkey] = profile
            }
        }
    }
}
```

✅ **Good Pattern: Single Subscription**
```swift
@MainActor
class ProfileListViewModel: ObservableObject {
    @Published var profiles: [String: NDKUserProfile] = [:]
    private var subscription: NDKSubscription?
    
    func loadProfiles(pubkeys: [String]) {
        // Cancel previous subscription
        subscription?.cancel()
        
        // Single subscription for all profiles
        let filter = NDKFilter(authors: pubkeys, kinds: [0])
        subscription = ndk.subscribe(filters: [filter])
        
        Task {
            for try await event in subscription! {
                if let profile = parseProfile(from: event) {
                    await MainActor.run {
                        profiles[event.pubkey] = profile
                    }
                }
            }
        }
    }
}
```

### 2. Real-Time Note Feed

❌ **Anti-pattern: Polling with fetchEvents**
```swift
// DON'T: Polling approach
class NoteFeedViewModel {
    func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task {
                let events = try? await ndk.fetchEvents(
                    NDKFilter(kinds: [1], limit: 20)
                )
                self.updateFeed(with: events)
            }
        }
    }
}
```

✅ **Good Pattern: Continuous Subscription**
```swift
class NoteFeedViewModel: ObservableObject {
    @Published var notes: [NDKEvent] = []
    private var subscription: NDKSubscription?
    
    func startListening() {
        let filter = NDKFilter(kinds: [1], limit: 20)
        subscription = ndk.subscribe(filters: [filter])
        
        Task {
            for try await event in subscription! {
                await MainActor.run {
                    // Insert at beginning for newest first
                    notes.insert(event, at: 0)
                    // Trim to keep memory bounded
                    if notes.count > 100 {
                        notes.removeLast()
                    }
                }
            }
        }
    }
    
    func stopListening() {
        subscription?.cancel()
    }
}
```

### 3. Aggregating Data (Zaps Example)

✅ **Good Pattern: Progressive Updates**
```swift
struct ZapView: View {
    @State private var totalZaps: Int64 = 0
    @State private var zappers: Set<String> = []
    @State private var largestZap: ZapInfo?
    
    let event: NDKEvent
    
    var body: some View {
        VStack {
            Text("⚡ \(totalZaps) sats from \(zappers.count) zappers")
            if let largest = largestZap {
                Text("Largest: \(largest.amount) from \(largest.sender)")
            }
        }
        .task {
            await loadZaps()
        }
    }
    
    private func loadZaps() async {
        let zapStream = zapManager.subscribeToZaps(for: event)
        
        do {
            for try await zap in zapStream {
                totalZaps += zap.amount
                zappers.insert(zap.sender)
                
                if largestZap == nil || zap.amount > largestZap!.amount {
                    largestZap = zap
                }
            }
        } catch {
            print("Zap loading error: \(error)")
        }
    }
}
```

### 4. Monitoring for Updates

✅ **Good Pattern: Live Notifications**
```swift
class NotificationManager: ObservableObject {
    @Published var unreadCount: Int = 0
    @Published var latestNotifications: [NDKEvent] = []
    
    private var subscription: NDKSubscription?
    
    func startMonitoring(for userPubkey: String) {
        // Monitor mentions, reactions, zaps, etc.
        let filter = NDKFilter(
            kinds: [1, 7, 9735], // mentions, reactions, zaps
            tags: ["p": [userPubkey]],
            since: Timestamp.now
        )
        
        subscription = ndk.subscribe(filters: [filter])
        
        Task {
            for try await event in subscription! {
                await handleNotification(event)
            }
        }
    }
    
    @MainActor
    private func handleNotification(_ event: NDKEvent) {
        unreadCount += 1
        latestNotifications.insert(event, at: 0)
        
        // Keep only recent notifications
        if latestNotifications.count > 50 {
            latestNotifications.removeLast()
        }
        
        // Could also trigger local notifications here
    }
}
```

### 5. When fetchEvents IS Appropriate

✅ **Good Use: Pre-flight Checks**
```swift
// Checking relay configuration before publishing
func publishToOutbox(event: NDKEvent, for user: NDKUser) async throws {
    // Need relay list before we can publish
    let relayListFilter = NDKFilter(
        authors: [user.pubkey],
        kinds: [10002], // NIP-65 relay list
        limit: 1
    )
    
    // fetchEvents is appropriate here - we need the data before proceeding
    let relayListEvents = try await ndk.fetchEvents(relayListFilter)
    guard let relayList = relayListEvents.first else {
        throw PublishError.noRelayList
    }
    
    let writeRelays = parseWriteRelays(from: relayList)
    try await publishToRelays(event, relays: writeRelays)
}
```

✅ **Good Use: One-Time Lookups**
```swift
// Verifying a specific event exists
func verifyEventExists(id: String) async throws -> Bool {
    let filter = NDKFilter(ids: [id])
    let events = try await ndk.fetchEvents(filter)
    return !events.isEmpty
}
```

## Best Practices

### 1. Subscription Lifecycle Management

Always clean up subscriptions:
```swift
class ViewModel: ObservableObject {
    private var subscriptions: Set<NDKSubscription> = []
    
    func startSubscription() {
        let subscription = ndk.subscribe(filters: [filter])
        subscriptions.insert(subscription)
        // ...
    }
    
    deinit {
        // Cancel all subscriptions when view model is destroyed
        subscriptions.forEach { $0.cancel() }
    }
}
```

### 2. Error Handling in Streams

```swift
func processEventStream() async {
    let subscription = ndk.subscribe(filters: [filter])
    
    do {
        for try await event in subscription {
            processEvent(event)
        }
    } catch NDKError.subscriptionClosed {
        // Normal termination
    } catch {
        // Handle errors appropriately
        print("Stream error: \(error)")
        // Could retry, notify user, etc.
    }
}
```

### 3. Combining Multiple Filters

```swift
// Subscribe to multiple event types in one subscription
let filters = [
    NDKFilter(authors: [userPubkey], kinds: [0]), // Profile
    NDKFilter(authors: [userPubkey], kinds: [1], limit: 20), // Recent notes
    NDKFilter(kinds: [3], tags: ["p": [userPubkey]]) // Followers
]

let subscription = ndk.subscribe(filters: filters)

for try await event in subscription {
    switch event.kind {
    case 0:
        handleProfileUpdate(event)
    case 1:
        handleNewNote(event)
    case 3:
        handleFollowerUpdate(event)
    default:
        break
    }
}
```

## Summary

- **Default to subscriptions** for any UI that displays event data
- **Use fetchEvents sparingly** - only when you truly need all data before proceeding
- **Process events as they arrive** rather than waiting for complete datasets
- **Manage subscription lifecycles** properly to avoid memory leaks
- **Embrace the streaming nature** of Nostr for better UX and performance