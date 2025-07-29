# Session Data Management

NDKSwift provides a powerful session data management system that allows apps to:
- Declare fundamental data requirements (follow lists, web-of-trust)
- Know when session data is ready with observable states
- Use reactive filters that automatically update when dependencies change
- Efficiently swap subscriptions to minimize re-downloading events

## Quick Start

```swift
// Start a session with data requirements
let sessionData = try await ndk.startSession(
    signer: signer,
    config: NDKSessionConfiguration(
        dataRequirements: [.followList],
        preloadStrategy: .progressive
    )
)

// Create a reactive filter that updates with follow list changes
let feedFilter = ReactiveFilter(
    dependencies: [.followList],
    builder: { sessionData in
        NDKFilter(
            authors: Array(sessionData.followList),
            kinds: [EventKind.textNote],
            limit: 100
        )
    }
)

// Observe events with automatic updates
for await event in ndk.observe(feedFilter) {
    // Handle events - subscription automatically updates when follows change
}
```

## Core Concepts

### Session Data Types

Session data represents fundamental information needed by most Nostr applications:

```swift
public enum SessionData: Hashable {
    case followList              // User's follow list (kind:3)
    case webOfTrust(depth: Int)  // Web of trust scoring
    case muteList               // Muted users (kind:10000)
    case blockedRelays          // Blocked relays (kind:10006)
    case relayList              // Preferred relays (kind:10002)
}
```

### Session Configuration

Configure how session data is loaded:

```swift
public struct NDKSessionConfiguration {
    let dataRequirements: Set<SessionData>
    let preloadStrategy: PreloadStrategy
    
    public enum PreloadStrategy {
        case blocking    // Wait for all data before returning
        case progressive // Return immediately, load in background
        case lazy       // Don't load until needed
    }
}
```

### Data States

Session data uses observable states to track loading progress:

```swift
public enum DataState<T> {
    case loading                         // Initial loading
    case ready(T, fromCache: Bool)      // Data available
    case updating(current: T, changes: T) // Updating with changes
    case error(Error)                   // Loading failed
}
```

## Reactive Filters

Reactive filters automatically update subscriptions when their dependencies change:

```swift
public struct ReactiveFilter {
    let dependencies: Set<SessionData>
    let builder: (NDKSessionData) -> NDKFilter
    let wotConfig: WOTConfiguration?
}
```

### Creating Reactive Filters

```swift
// Filter for posts from follows
let followFeed = ReactiveFilter(
    dependencies: [.followList],
    builder: { sessionData in
        NDKFilter(
            authors: Array(sessionData.followList),
            kinds: [EventKind.textNote],
            limit: 50
        )
    }
)

// Filter with Web of Trust spam filtering
let trustedFeed = ReactiveFilter(
    dependencies: [.followList, .webOfTrust(depth: 2)],
    builder: { sessionData in
        NDKFilter(
            kinds: [EventKind.textNote],
            limit: 100
        )
    },
    wotConfig: WOTConfiguration(
        minimumScore: 2,
        includeDirectFollows: true
    )
)
```

## Session Data API

### Starting a Session

```swift
// Basic session with follow list
let sessionData = try await ndk.startSession(
    signer: signer,
    config: NDKSessionConfiguration(
        dataRequirements: [.followList],
        preloadStrategy: .progressive
    )
)

// Session with multiple requirements
let sessionData = try await ndk.startSession(
    signer: signer,
    config: NDKSessionConfiguration(
        dataRequirements: [.followList, .webOfTrust(depth: 2)],
        preloadStrategy: .blocking // Wait for all data
    )
)
```

### Observing Session State

The `NDKSessionData` class is `@Observable`, allowing SwiftUI views to react to changes:

```swift
@Observable
public class NDKSessionData {
    public let pubkey: String
    public private(set) var followListState: DataState<Set<String>>
    public var followList: Set<String> { followListState.data ?? [] }
    public private(set) var isReady: Bool
    
    // Web of Trust scores (lazy-loaded)
    public var webOfTrust: [String: Int]
}
```

### Using in SwiftUI

```swift
struct FeedView: View {
    @State private var sessionData: NDKSessionData?
    
    var body: some View {
        Group {
            switch sessionData?.followListState {
            case .loading:
                ProgressView("Loading follows...")
            case .ready(let follows, let fromCache):
                Text("Following \(follows.count) users")
                if fromCache {
                    Text("(from cache)")
                }
            case .updating(let current, _):
                Text("Updating... (\(current.count) follows)")
            case .error(let error):
                Text("Error: \(error.localizedDescription)")
            case nil:
                Text("Not logged in")
            }
        }
    }
}
```

## Observing Events

### Continuous Observation

Use `observe()` for real-time event streams:

```swift
// Create reactive filter
let filter = ReactiveFilter(
    dependencies: [.followList],
    builder: { sessionData in
        NDKFilter(
            authors: Array(sessionData.followList),
            kinds: [EventKind.textNote]
        )
    }
)

// Observe events
for await event in ndk.observe(filter) {
    print("New event from \(event.pubkey)")
}
```

### One-Time Fetch

To collect events once, use `observe()` with a collection pattern:

```swift
var events: [NDKEvent] = []
for await event in ndk.observe(filter: filter).events {
    events.append(event)
    // Break after collecting enough events or a timeout
}
print("Collected \(events.count) events")
```

## Subscription Management

### Automatic Updates

When follow lists change, subscriptions are automatically updated using efficient "bridge subscriptions":

1. New follows are detected via event ID changes
2. A temporary subscription fetches recent posts from new follows
3. The main subscription is seamlessly swapped
4. Minimal events are missed during the transition

### Manual Filter Updates

For advanced use cases, you can manually update filters:

```swift
let dataSource = NDKDataSource<NDKEvent>(ndk: ndk, filter: initialFilter)

// Later, update the filter
await dataSource.updateFilter(newFilter)
```

## Mute Lists and Blocked Relays

### Automatic Mute Filtering

Events from muted pubkeys are automatically filtered out when using reactive filters:

```swift
// Mute list is loaded automatically with session data
let sessionData = try await ndk.startSession(
    signer: signer,
    config: NDKSessionConfiguration(
        dataRequirements: [.followList, .muteList]
    )
)

// Events from muted pubkeys are automatically filtered
for await event in ndk.observe(feedFilter) {
    // This event is guaranteed not to be from a muted pubkey
}
```

### Manual Mute Checking

For custom filtering logic:

```swift
// Check if a pubkey is muted (O(1) lookup)
if sessionData.isMuted(pubkey) {
    // Skip this content
}

// Access the full mute list
let mutedPubkeys = sessionData.muteList  // Set<String>
```

### Blocked Relays

Relays in your blocked list are automatically excluded from outbox operations:

```swift
// Load blocked relays with session
let sessionData = try await ndk.startSession(
    signer: signer,
    config: NDKSessionConfiguration(
        dataRequirements: [.followList, .blockedRelays]
    )
)

// Check if a relay is blocked (O(1) lookup)
if sessionData.isRelayBlocked("wss://bad-relay.com") {
    // Skip this relay
}

// Access the full blocked relay list
let blockedRelays = sessionData.blockedRelays  // Set<String>
```

### Combined Example

```swift
// Load all protective lists
let sessionData = try await ndk.startSession(
    signer: signer,
    config: NDKSessionConfiguration(
        dataRequirements: [.followList, .muteList, .blockedRelays],
        preloadStrategy: .progressive
    )
)

// Create a filter with automatic mute filtering
let protectedFeed = ReactiveFilter(
    dependencies: [.followList],
    builder: { sessionData in
        NDKFilter(
            authors: Array(sessionData.followList),
            kinds: [EventKind.textNote]
        )
    }
)

// Events are automatically filtered
for await event in ndk.observe(protectedFeed) {
    // This event:
    // - Is from someone you follow
    // - Is NOT from a muted pubkey
    // - Was NOT fetched from blocked relays
}
```

## Web of Trust (WOT)

Web of Trust provides spam filtering based on social graph distance:

```swift
public struct WOTConfiguration {
    let minimumScore: Int           // Minimum WOT score to pass filter
    let includeDirectFollows: Bool  // Always include direct follows
}

// Check if a pubkey passes WOT filter
let passes = sessionData.passesWOTFilter(pubkey, config: wotConfig)
```

### WOT Scoring

- Direct follows: Maximum score (Int.max)
- Follows of follows: Score based on how many of your follows also follow them
- Updates every 24 hours automatically
- Lazy-loaded on first access

## Best Practices

1. **Declare Requirements Early**: Specify all data requirements when starting the session
2. **Use Progressive Loading**: For better UX, use `.progressive` strategy to show cached data immediately
3. **Leverage Reactive Filters**: Let the system handle subscription updates automatically
4. **Monitor State Changes**: Use the observable states to show loading indicators
5. **Handle Errors Gracefully**: Always handle the `.error` state in your UI

## Example: Complete Feed Implementation

```swift
class FeedViewModel: ObservableObject {
    @Published var events: [NDKEvent] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private var ndk: NDK
    private var sessionData: NDKSessionData?
    private var observationTask: Task<Void, Never>?
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    func startSession(signer: NDKSigner) async {
        do {
            // Start session with follow list
            sessionData = try await ndk.startSession(
                signer: signer,
                config: NDKSessionConfiguration(
                    dataRequirements: [.followList],
                    preloadStrategy: .progressive
                )
            )
            
            // Start observing feed
            await observeFeed()
        } catch {
            self.error = error
        }
    }
    
    private func observeFeed() async {
        // Cancel previous observation
        observationTask?.cancel()
        
        // Create reactive filter
        let filter = ReactiveFilter(
            dependencies: [.followList],
            builder: { sessionData in
                NDKFilter(
                    authors: Array(sessionData.followList),
                    kinds: [EventKind.textNote],
                    limit: 50
                )
            }
        )
        
        // Start new observation
        observationTask = Task {
            isLoading = true
            
            for await event in ndk.observe(filter) {
                await MainActor.run {
                    events.append(event)
                    isLoading = false
                }
            }
        }
    }
    
    func cleanup() {
        observationTask?.cancel()
    }
}
```

## Migration Guide

If you're migrating from manual subscription management:

### Before (Manual)
```swift
// Manually fetch follow list
let followEvent = try await ndk.fetchEvent(
    NDKFilter(authors: [pubkey], kinds: [EventKind.contacts])
)
let follows = parseFollows(followEvent)

// Manually create subscription
let sub = ndk.subscribe(
    NDKFilter(authors: follows, kinds: [EventKind.textNote])
)

// Manually handle updates
// ... complex update logic ...
```

### After (Reactive)
```swift
// Declare requirements and observe
let sessionData = try await ndk.startSession(
    signer: signer,
    config: NDKSessionConfiguration(
        dataRequirements: [.followList],
        preloadStrategy: .progressive
    )
)

let filter = ReactiveFilter(
    dependencies: [.followList],
    builder: { sessionData in
        NDKFilter(
            authors: Array(sessionData.followList),
            kinds: [EventKind.textNote]
        )
    }
)

// Automatic updates!
for await event in ndk.observe(filter) {
    // Handle events
}
```