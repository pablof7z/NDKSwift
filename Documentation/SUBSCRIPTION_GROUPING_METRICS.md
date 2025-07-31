# Subscription Grouping Metrics

This document explains how to use the metrics collection feature for subscription grouping in NDKSwift.

## Overview

The metrics system tracks the effectiveness of subscription grouping, providing insights into:
- How many subscriptions are being grouped together
- How many REQ messages are saved through grouping
- Timing statistics for grouping delays
- Per-relay performance metrics

## Basic Usage

### Getting Metrics

```swift
// Get current metrics snapshot
let metrics = await ndk.getSubscriptionMetrics()

// Print human-readable summary
print(metrics.summary)

// Access specific metrics
print("Total subscriptions: \(metrics.totalSubscriptions)")
print("Grouping efficiency: \(metrics.groupingEfficiency * 100)%")
print("Message reduction: \(metrics.messageReduction * 100)%")
```

### Resetting Metrics

```swift
// Reset all metrics to zero
await ndk.resetSubscriptionMetrics()
```

## Available Metrics

### Core Metrics

- **totalSubscriptions**: Total number of subscriptions created
- **groupedSubscriptions**: Number of subscriptions that were grouped with others
- **nonGroupableSubscriptions**: Number of subscriptions with `groupable: false`
- **totalReqMessages**: Total REQ messages sent to relays
- **reqMessagesSaved**: Number of REQ messages saved through grouping

### Calculated Metrics

- **groupingEfficiency**: Percentage of subscriptions that were grouped (0.0 - 1.0)
- **messageReduction**: Percentage of messages saved through grouping (0.0 - 1.0)
- **averageGroupSize**: Average number of subscriptions per group

### Delay Statistics

```swift
metrics.delayStatistics.totalDelays        // Number of delays recorded
metrics.delayStatistics.averageActualDelay // Average actual delay in seconds
metrics.delayStatistics.atLeastCount       // Count of "at least" delays
metrics.delayStatistics.atMostCount        // Count of "at most" delays
```

### Per-Relay Metrics

```swift
// Get metrics for a specific relay
if let relayMetrics = metrics.relayMetrics["wss://relay.example.com"] {
    print("REQ messages: \(relayMetrics.totalReqMessages)")
    print("Average group size: \(relayMetrics.averageGroupSize)")
}
```

## Example: Monitoring Grouping Effectiveness

```swift
// Start monitoring
await ndk.resetSubscriptionMetrics()

// Create subscriptions with grouping
let filter = NDKFilter(kinds: [1], authors: ["alice", "bob"])
let sub1 = ndk.subscribe(filter: filter)
let sub2 = ndk.subscribe(filter: filter)
let sub3 = ndk.subscribe(filter: filter)

// Wait for grouping to occur
try await Task.sleep(nanoseconds: 200_000_000) // 0.2s

// Check results
let metrics = await ndk.getSubscriptionMetrics()

if metrics.groupingEfficiency > 0.5 {
    print("✅ Good grouping efficiency: \(metrics.groupingEfficiency * 100)%")
} else {
    print("⚠️ Low grouping efficiency: \(metrics.groupingEfficiency * 100)%")
}

print("Messages saved: \(metrics.reqMessagesSaved)")
print("Average group size: \(metrics.averageGroupSize)")
```

## Advanced Usage

### Custom Metrics Tracking

```swift
// Track metrics over time
var metricsHistory: [MetricsSnapshot] = []

// Periodic collection
Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
    Task {
        let snapshot = await ndk.getSubscriptionMetrics()
        metricsHistory.append(snapshot)
        
        // Analyze trends
        if metricsHistory.count > 2 {
            let recent = metricsHistory.suffix(2)
            let improvement = recent.last!.groupingEfficiency - recent.first!.groupingEfficiency
            print("Efficiency change: \(improvement * 100)%")
        }
    }
}
```

### Debugging Subscription Patterns

```swift
// Identify problematic subscription patterns
let metrics = await ndk.getSubscriptionMetrics()

// Check if grouping is effective
if metrics.totalSubscriptions > 100 && metrics.groupingEfficiency < 0.3 {
    print("⚠️ Low grouping efficiency detected!")
    print("Consider:")
    print("- Using consistent filters across subscriptions")
    print("- Enabling groupable on more subscriptions")
    print("- Adjusting grouping delays")
}

// Check message savings
let potentialMessages = metrics.totalReqMessages + metrics.reqMessagesSaved
let actualSavings = Double(metrics.reqMessagesSaved) / Double(potentialMessages)
print("Achieved \(actualSavings * 100)% message reduction")
```

## Performance Considerations

1. **Metrics Collection Overhead**: The metrics system has minimal overhead, using simple counters and averages.

2. **Memory Usage**: Metrics are stored in memory. Consider resetting periodically for long-running applications.

3. **Thread Safety**: All metrics operations are thread-safe through the actor model.

## Best Practices

1. **Reset Before Measurements**: Always reset metrics before taking specific measurements to ensure clean data.

2. **Wait for Grouping**: Allow time for grouping delays to execute before checking metrics.

3. **Monitor Trends**: Track metrics over time rather than relying on single snapshots.

4. **Set Targets**: Establish target efficiency levels based on your application's needs.

5. **Use for Optimization**: Use metrics to identify optimization opportunities in subscription patterns.

## Integration with Monitoring

```swift
// Export metrics for external monitoring
extension MetricsSnapshot {
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let data = [
            "totalSubscriptions": totalSubscriptions,
            "groupedSubscriptions": groupedSubscriptions,
            "groupingEfficiency": groupingEfficiency,
            "messageReduction": messageReduction,
            "averageGroupSize": averageGroupSize,
            "reqMessagesSaved": reqMessagesSaved
        ]
        
        if let jsonData = try? encoder.encode(data),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
}

// Send to monitoring service
let metrics = await ndk.getSubscriptionMetrics()
let jsonMetrics = metrics.toJSON()
// Send to your monitoring backend
```

## Summary

The metrics system provides valuable insights into subscription grouping effectiveness, helping you:
- Optimize subscription patterns
- Reduce network overhead
- Monitor application performance
- Debug grouping issues

Use these metrics to ensure your Nostr application is making efficient use of network resources through effective subscription grouping.