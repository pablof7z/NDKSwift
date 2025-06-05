# NDKSwift Subscription Tracking

NDKSwift provides comprehensive subscription tracking capabilities that allow developers to monitor and debug subscription behavior across relays. This feature helps answer questions like:

- How many subscriptions are currently active?
- How many unique events have been received?
- Which relays have executed a subscription and with what filters?
- How many events has each relay delivered?
- What is the performance of different relays?

## Overview

The subscription tracking system consists of several key components:

1. **NDKSubscriptionTracker** - The main tracking actor that collects and stores metrics
2. **Subscription Metrics** - Overall metrics for each subscription
3. **Relay-Level Metrics** - Detailed metrics for each relay handling a subscription
4. **Closed Subscription History** - Optional historical tracking of completed subscriptions
5. **Global Statistics** - System-wide subscription statistics

## Basic Usage

### Enabling Subscription Tracking

Subscription tracking is always enabled, but you can configure whether to track closed subscriptions:

```swift
// Enable tracking of closed subscriptions (useful for debugging)
let ndk = NDK(
    subscriptionTrackingConfig: NDK.SubscriptionTrackingConfig(
        trackClosedSubscriptions: true,
        maxClosedSubscriptions: 100
    )
)

// Or use default (no closed subscription tracking)
let ndk = NDK()
```

### Accessing the Tracker

The subscription tracker is available through the NDK instance:

```swift
let tracker = ndk.subscriptionTracker
```

## Querying Subscription Data

### Active Subscription Count

```swift
let count = await ndk.subscriptionTracker.activeSubscriptionCount()
print("Active subscriptions: \(count)")
```

### Total Unique Events

```swift
let uniqueEvents = await ndk.subscriptionTracker.totalUniqueEventsReceived()
print("Unique events received: \(uniqueEvents)")
```

### Subscription Details

Get detailed information about a specific subscription:

```swift
if let detail = await ndk.subscriptionTracker.getSubscriptionDetail(subscription.id) {
    print("Subscription ID: \(detail.subscriptionId)")
    print("Original filter: \(detail.originalFilter)")
    print("Total unique events: \(detail.metrics.totalUniqueEvents)")
    print("Total events (including duplicates): \(detail.metrics.totalEvents)")
    print("Active on \(detail.metrics.activeRelayCount) relays")
    print("Started: \(detail.metrics.startTime)")
    
    // Relay-specific information
    for (relayUrl, relayMetrics) in detail.relayMetrics {
        print("\nRelay: \(relayUrl)")
        print("  Events received: \(relayMetrics.eventsReceived)")
        print("  EOSE received: \(relayMetrics.eoseReceived)")
        print("  Applied filter: \(relayMetrics.appliedFilter)")
        
        if let timeToEose = relayMetrics.timeToEose {
            print("  Time to EOSE: \(timeToEose)s")
        }
    }
}
```

### All Active Subscriptions

```swift
let allActive = await ndk.subscriptionTracker.getAllActiveSubscriptions()
for detail in allActive {
    print("Subscription \(detail.subscriptionId): \(detail.metrics.totalUniqueEvents) events")
}
```

### Global Statistics

```swift
let stats = await ndk.subscriptionTracker.getStatistics()
print("Active subscriptions: \(stats.activeSubscriptions)")
print("Total subscriptions created: \(stats.totalSubscriptions)")
print("Total unique events: \(stats.totalUniqueEvents)")
print("Total events (with duplicates): \(stats.totalEvents)")
print("Average events per subscription: \(stats.averageEventsPerSubscription)")
print("Closed subscriptions tracked: \(stats.closedSubscriptionsTracked)")
```

## Relay-Level Tracking

The tracker provides detailed information about how each relay handles subscriptions:

### Get Relay Metrics for a Subscription

```swift
// Get metrics for a specific relay
if let metrics = await ndk.subscriptionTracker.getRelayMetrics(
    subscriptionId: subscription.id,
    relayUrl: "wss://relay.example.com"
) {
    print("Events from this relay: \(metrics.eventsReceived)")
    print("Filter sent to relay: \(metrics.appliedFilter)")
}

// Get all relay metrics for a subscription
if let allRelayMetrics = await ndk.subscriptionTracker.getAllRelayMetrics(
    subscriptionId: subscription.id
) {
    for (relayUrl, metrics) in allRelayMetrics {
        print("\(relayUrl): \(metrics.eventsReceived) events")
    }
}
```

## Closed Subscription History

When enabled, the tracker maintains a history of closed subscriptions:

```swift
let closedSubs = await ndk.subscriptionTracker.getClosedSubscriptions()
for closed in closedSubs {
    print("Subscription \(closed.subscriptionId)")
    print("  Filter: \(closed.filter)")
    print("  Relays: \(closed.relays.joined(separator: ", "))")
    print("  Unique events: \(closed.uniqueEventCount)")
    print("  Duration: \(closed.duration)s")
    print("  Events per second: \(closed.eventsPerSecond)")
}

// Clear history if needed
await ndk.subscriptionTracker.clearClosedSubscriptionHistory()
```

## Debugging and Export

### Export All Tracking Data

For debugging purposes, you can export all tracking data:

```swift
let trackingData = await ndk.subscriptionTracker.exportTrackingData()

// The exported data includes:
// - activeSubscriptions: Array of active subscription details
// - closedSubscriptions: Array of closed subscription summaries
// - statistics: Global statistics

// Save to file for analysis
let jsonData = try JSONSerialization.data(withJSONObject: trackingData)
try jsonData.write(to: URL(fileURLWithPath: "subscription-tracking.json"))
```

## Performance Considerations

The subscription tracking system is designed to have minimal performance impact:

1. **Async/Actor-based**: All tracking operations are performed asynchronously
2. **Cached Statistics**: Global statistics are cached and invalidated on changes
3. **Limited History**: Closed subscription history has a configurable maximum size
4. **Efficient Storage**: Uses in-memory storage with actor-based thread safety

## Use Cases

### Debugging Subscription Issues

```swift
// Create a subscription
let subscription = ndk.subscribe(filters: [NDKFilter(kinds: [1])])

// ... later, check why events aren't arriving ...

if let detail = await ndk.subscriptionTracker.getSubscriptionDetail(subscription.id) {
    print("Subscription active on \(detail.metrics.activeRelayCount) relays")
    
    for (relayUrl, metrics) in detail.relayMetrics {
        if metrics.eventsReceived == 0 {
            print("No events from \(relayUrl)")
            print("EOSE received: \(metrics.eoseReceived)")
        }
    }
}
```

### Monitoring Relay Performance

```swift
// Compare relay performance across all subscriptions
var relayStats: [String: (events: Int, subscriptions: Int)] = [:]

let allSubs = await ndk.subscriptionTracker.getAllActiveSubscriptions()
for sub in allSubs {
    for (relayUrl, metrics) in sub.relayMetrics {
        var stats = relayStats[relayUrl] ?? (events: 0, subscriptions: 0)
        stats.events += metrics.eventsReceived
        stats.subscriptions += 1
        relayStats[relayUrl] = stats
    }
}

// Print relay performance
for (relay, stats) in relayStats {
    let avgEvents = Double(stats.events) / Double(stats.subscriptions)
    print("\(relay): \(avgEvents) events/subscription")
}
```

### Subscription Lifecycle Monitoring

```swift
// Monitor a subscription's lifecycle
let subscription = ndk.subscribe(
    filters: [NDKFilter(kinds: [1])],
    options: NDKSubscriptionOptions(closeOnEose: true)
)

// Check initial state
if let detail = await ndk.subscriptionTracker.getSubscriptionDetail(subscription.id) {
    print("Started at: \(detail.metrics.startTime)")
}

// ... after EOSE ...

// Check closed subscription
let closed = await ndk.subscriptionTracker.getClosedSubscriptions()
if let closedSub = closed.first(where: { $0.subscriptionId == subscription.id }) {
    print("Ran for \(closedSub.duration) seconds")
    print("Received \(closedSub.uniqueEventCount) unique events")
    print("Rate: \(closedSub.eventsPerSecond) events/second")
}
```

## Best Practices

1. **Enable closed subscription tracking during development** to help debug issues
2. **Disable closed subscription tracking in production** unless needed for monitoring
3. **Use relay-level metrics** to identify poorly performing relays
4. **Export tracking data** when reporting issues or analyzing performance
5. **Monitor global statistics** to understand overall system behavior
6. **Clear closed subscription history** periodically if tracking is enabled long-term

## Thread Safety

All subscription tracking operations are thread-safe through the use of Swift actors. You can safely call tracking methods from any thread or async context.