# Subscription Grouping Improvements

This document outlines recommended improvements to the subscription grouping feature implemented in NDKSwift v0.12.

## Background

NDKSwift now includes relay-level subscription grouping that batches similar subscriptions to reduce network overhead. While the core functionality is complete, several improvements would enhance usability, testability, and observability.

## Recommendation 1: Public API for Grouping Configuration

### Current State
Subscription grouping is only configurable at the internal `NDKSubscriptionCoordinator` level. Users cannot customize grouping behavior through the public API.

### Proposed Solution

Add `NDKSubscriptionOptions` to the public API:

```swift
public struct NDKSubscriptionOptions {
    /// Whether this subscription can be grouped with others
    public var groupable: Bool = true
    
    /// Delay before executing grouped subscriptions (nil uses default)
    public var groupableDelay: TimeInterval? = nil
    
    /// Type of delay constraint
    public var groupableDelayType: NDKSubscriptionDelayType? = nil
    
    /// Whether to close the subscription on EOSE
    public var closeOnEose: Bool = false
    
    /// Cache usage policy
    public var cacheUsage: NDKSubscriptionCacheUsage = .cacheFirst
    
    public init() {}
}
```

Update public subscribe methods:

```swift
public extension NDK {
    /// Subscribe to events with custom options
    func subscribe(
        filter: NDKFilter,
        options: NDKSubscriptionOptions? = nil
    ) -> NDKSubscription<NDKEvent> {
        // Implementation passes options through to internal components
    }
    
    /// Subscribe to typed events with custom options
    func subscribe<T: NDKEventProtocol>(
        filter: NDKFilter,
        type: T.Type,
        options: NDKSubscriptionOptions? = nil
    ) -> NDKSubscription<T> {
        // Implementation
    }
}
```

### Usage Example

```swift
// Default behavior - groupable with 100ms delay
let subscription = ndk.subscribe(filter: filter)

// Custom non-groupable subscription for real-time updates
let realtimeOptions = NDKSubscriptionOptions()
realtimeOptions.groupable = false
let realtimeSub = ndk.subscribe(filter: filter, options: realtimeOptions)

// Subscription with longer grouping delay for background sync
let backgroundOptions = NDKSubscriptionOptions()
backgroundOptions.groupableDelay = 1.0  // 1 second
backgroundOptions.groupableDelayType = .atLeast
let backgroundSub = ndk.subscribe(filter: filter, options: backgroundOptions)
```

## Recommendation 2: Integration Tests for REQ Message Batching

### Current State
Unit tests verify component behavior but don't test actual REQ message batching at the network level.

### Proposed Solution

Create integration tests using `MockRelay` to verify batching behavior:

```swift
@MainActor
final class SubscriptionGroupingIntegrationTests: XCTestCase {
    
    func testMultipleSubscriptionsCreateSingleREQ() async throws {
        // Setup
        let mockRelay = MockRelay(url: "wss://test.relay")
        let ndk = NDK()
        await ndk.pool.addRelay(mockRelay)
        
        // Track sent messages
        var sentMessages: [String] = []
        mockRelay.onSend = { message in
            sentMessages.append(message)
        }
        
        // Create multiple subscriptions with same filter
        let filter = NDKFilter(kinds: [1], authors: ["alice"])
        let sub1 = ndk.subscribe(filter: filter)
        let sub2 = ndk.subscribe(filter: filter)
        let sub3 = ndk.subscribe(filter: filter)
        
        // Wait for grouping delay
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Verify only one REQ was sent
        let reqMessages = sentMessages.filter { $0.starts(with: "[\"REQ\"") }
        XCTAssertEqual(reqMessages.count, 1, "Should batch into single REQ")
        
        // Verify the REQ contains the correct filter
        let reqData = try JSONDecoder().decode([[String: Any]].self, from: reqMessages[0])
        XCTAssertEqual(reqData[0]["kinds"] as? [Int], [1])
        XCTAssertEqual(reqData[0]["authors"] as? [String], ["alice"])
    }
    
    func testGroupingDelayTiming() async throws {
        let mockRelay = MockRelay(url: "wss://test.relay")
        let ndk = NDK()
        await ndk.pool.addRelay(mockRelay)
        
        var reqTimestamp: Date?
        mockRelay.onSend = { message in
            if message.starts(with: "[\"REQ\"") {
                reqTimestamp = Date()
            }
        }
        
        let startTime = Date()
        let filter = NDKFilter(kinds: [1])
        
        // Create subscription with custom delay
        let options = NDKSubscriptionOptions()
        options.groupableDelay = 0.5 // 500ms
        options.groupableDelayType = .atLeast
        
        _ = ndk.subscribe(filter: filter, options: options)
        
        // Wait for execution
        try await Task.sleep(nanoseconds: 600_000_000) // 600ms
        
        // Verify delay was respected
        XCTAssertNotNil(reqTimestamp)
        let actualDelay = reqTimestamp!.timeIntervalSince(startTime)
        XCTAssertGreaterThanOrEqual(actualDelay, 0.5, "Should wait at least 500ms")
    }
    
    func testNonGroupableSubscriptionsExecuteImmediately() async throws {
        let mockRelay = MockRelay(url: "wss://test.relay")
        let ndk = NDK()
        await ndk.pool.addRelay(mockRelay)
        
        var reqCount = 0
        mockRelay.onSend = { message in
            if message.starts(with: "[\"REQ\"") {
                reqCount += 1
            }
        }
        
        let filter = NDKFilter(kinds: [1])
        let options = NDKSubscriptionOptions()
        options.groupable = false
        
        // Create non-groupable subscriptions
        _ = ndk.subscribe(filter: filter, options: options)
        _ = ndk.subscribe(filter: filter, options: options)
        
        // Should execute immediately without waiting
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        XCTAssertEqual(reqCount, 2, "Non-groupable subscriptions should not batch")
    }
}
```

### Additional Test Scenarios

1. **Filter Merging Verification**: Test that filters are correctly merged when grouped
2. **Multi-Relay Grouping**: Verify each relay groups subscriptions independently
3. **Dynamic Subscription Addition**: Test adding subscriptions to existing groups
4. **Group Lifecycle**: Test group cleanup when all subscriptions close

## Recommendation 3: Metrics Collection for Grouping Effectiveness

### Current State
No visibility into how effective subscription grouping is in practice.

### Proposed Solution

Add metrics collection to track grouping performance:

```swift
public struct NDKSubscriptionGroupingMetrics {
    /// Total number of subscriptions created
    public var totalSubscriptions: Int = 0
    
    /// Number of subscriptions that were grouped
    public var groupedSubscriptions: Int = 0
    
    /// Number of REQ messages sent
    public var reqMessagesSent: Int = 0
    
    /// Number of REQ messages saved by grouping
    public var reqMessagesSaved: Int = 0
    
    /// Average delay introduced by grouping
    public var averageGroupingDelay: TimeInterval = 0
    
    /// Distribution of group sizes
    public var groupSizeDistribution: [Int: Int] = [:] // size -> count
    
    /// Grouping efficiency percentage
    public var efficiency: Double {
        guard totalSubscriptions > 0 else { return 0 }
        return Double(reqMessagesSaved) / Double(totalSubscriptions) * 100
    }
}

public extension NDK {
    /// Get current subscription grouping metrics
    var subscriptionGroupingMetrics: NDKSubscriptionGroupingMetrics {
        get async {
            await pool.aggregateGroupingMetrics()
        }
    }
    
    /// Reset grouping metrics
    func resetGroupingMetrics() async {
        await pool.resetGroupingMetrics()
    }
}
```

### Implementation in NDKRelaySubscriptionManager

```swift
extension NDKRelaySubscriptionManager {
    func collectMetrics() -> NDKSubscriptionGroupingMetrics {
        var metrics = NDKSubscriptionGroupingMetrics()
        
        for group in subscriptionGroups.values {
            let groupSize = group.itemCount
            if groupSize > 1 {
                metrics.groupedSubscriptions += groupSize
                metrics.reqMessagesSaved += groupSize - 1
            }
            metrics.groupSizeDistribution[groupSize, default: 0] += 1
        }
        
        metrics.totalSubscriptions = totalSubscriptionsCreated
        metrics.reqMessagesSent = totalREQsSent
        
        return metrics
    }
}
```

### Usage Example

```swift
// Monitor grouping effectiveness
let metrics = await ndk.subscriptionGroupingMetrics

print("Subscription Grouping Statistics:")
print("  Total subscriptions: \(metrics.totalSubscriptions)")
print("  Grouped subscriptions: \(metrics.groupedSubscriptions)")
print("  REQ messages saved: \(metrics.reqMessagesSaved)")
print("  Efficiency: \(String(format: "%.1f%%", metrics.efficiency))")
print("  Average delay: \(String(format: "%.0fms", metrics.averageGroupingDelay * 1000))")

// Log group size distribution
for (size, count) in metrics.groupSizeDistribution.sorted(by: { $0.key < $1.key }) {
    print("  Groups of size \(size): \(count)")
}
```

### Dashboard Integration

Apps could display these metrics in a debug dashboard:
- Real-time efficiency percentage
- Graph of REQ messages saved over time
- Distribution of group sizes
- Average delay impact

## Recommendation 5: Improved Testability with Async Getters

### Current State
Actor isolation prevents direct property access in tests, limiting test coverage.

### Proposed Solution

Add async getters or inspection methods for testing:

```swift
public extension NDKSubscriptionCoordinator {
    /// Testing interface for inspecting subscription state
    struct InspectionData {
        public let id: String
        public let isGroupable: Bool
        public let groupableDelay: TimeInterval?
        public let groupableDelayType: NDKSubscriptionDelayType?
        public let isActive: Bool
        public let activeRelays: Set<String>
    }
    
    /// Get inspection data for testing
    func inspect() async -> InspectionData {
        InspectionData(
            id: id,
            isGroupable: isGroupable,
            groupableDelay: groupableDelay,
            groupableDelayType: groupableDelayType,
            isActive: isActive,
            activeRelays: activeRelays
        )
    }
}

// Alternative: Make specific properties nonisolated where safe
extension NDKSubscriptionCoordinator {
    nonisolated var subscriptionId: String { id }
    nonisolated var isGroupableSubscription: Bool { isGroupable }
}
```

### Updated Tests

```swift
func testSubscriptionGroupingProperties() async {
    let sub = createSubscription(
        id: "test",
        filters: [filter],
        isGroupable: true,
        groupableDelay: 0.5,
        groupableDelayType: .atLeast
    )
    
    // Now we can verify properties
    let data = await sub.inspect()
    XCTAssertTrue(data.isGroupable)
    XCTAssertEqual(data.groupableDelay, 0.5)
    XCTAssertEqual(data.groupableDelayType, .atLeast)
}
```

### Testing Utilities

Add test-specific extensions:

```swift
#if DEBUG
public extension NDKRelaySubscriptionManager {
    /// Get current grouping state for testing
    func debugGroupingState() async -> [String: [String]] {
        var state: [String: [String]] = [:]
        for (fingerprint, group) in subscriptionGroups {
            state[fingerprint] = await group.subscriptionIds()
        }
        return state
    }
    
    /// Force immediate execution of all pending groups (for testing)
    func flushPendingGroups() async {
        for group in subscriptionGroups.values {
            await group.executeNow()
        }
    }
}
#endif
```

## Implementation Priority

1. **Public API** (High) - Enables users to control grouping behavior
2. **Integration Tests** (High) - Ensures the feature works correctly
3. **Testability** (Medium) - Improves maintainability
4. **Metrics** (Medium) - Provides visibility but not critical for functionality

## Timeline

- Phase 1 (1-2 days): Implement public API and update documentation
- Phase 2 (2-3 days): Create comprehensive integration tests
- Phase 3 (1 day): Add inspection methods for better testability
- Phase 4 (2-3 days): Implement metrics collection and reporting

## Conclusion

These improvements will make the subscription grouping feature more useful, testable, and observable. The public API enables developers to optimize for their specific use cases, while metrics provide insights into real-world effectiveness. Better testability ensures the feature remains reliable as the codebase evolves.