# Testing Subscription Grouping

This document explains how to use the testability features added for subscription grouping in NDKSwift.

## Overview

The testability improvements provide ways to inspect internal state and control execution timing, making it easier to write comprehensive tests for subscription grouping behavior.

## Inspection Methods

### NDKSubscriptionCoordinator.inspect()

Provides a snapshot of subscription state without requiring multiple async calls:

```swift
let subscription = NDKSubscriptionCoordinator(
    id: "test-sub",
    filters: [NDKFilter(kinds: [1])],
    relays: nil,
    ndk: ndk,
    isGroupable: true,
    groupableDelay: 0.5,
    groupableDelayType: .atLeast
)

// Get all state in one call
let state = await subscription.inspect()

// Access properties synchronously
XCTAssertTrue(state.isGroupable)
XCTAssertEqual(state.groupableDelay, 0.5)
XCTAssertEqual(state.groupableDelayType, .atLeast)
XCTAssertTrue(state.isActive)
XCTAssertEqual(state.activeRelays.count, 2)
```

## Debug Utilities (DEBUG builds only)

### View Grouping State

See which subscriptions are grouped together:

```swift
#if DEBUG
let groupingState = await manager.debugGroupingState()
// Returns: [fingerprint: [subscriptionIds]]
// Example: ["kinds:[1],authors:[alice]": ["sub1", "sub2"]]

for (fingerprint, subscriptionIds) in groupingState {
    print("Group \(fingerprint) contains: \(subscriptionIds.joined(separator: ", "))")
}
#endif
```

### Force Immediate Execution

Skip grouping delays for testing:

```swift
#if DEBUG
// Add subscriptions with long delays
await manager.addSubscription(sub1, filters: [filter])
await manager.addSubscription(sub2, filters: [filter])

// Force all pending groups to execute immediately
await manager.flushPendingGroups()
// REQ messages are sent without waiting for delays
#endif
```

### Inspect Specific Groups

Get detailed information about a subscription group:

```swift
#if DEBUG
let fingerprint = NDKFilterGrouping.filterFingerprint([filter], closeOnEose: false)
let groupInfo = await manager.debugInspectGroup(fingerprint: fingerprint)

if let info = groupInfo {
    print("Group: \(info.fingerprint)")
    print("  Groupable: \(info.isGroupable)")
    print("  Items: \(info.itemCount)")
    print("  Status: \(info.status)")
    print("  Subscription ID: \(info.subId ?? "none")")
}
#endif
```

## Example Test Cases

### Test Subscription Properties

```swift
func testSubscriptionConfiguration() async throws {
    let options = NDKSubscriptionOptions()
    options.groupable = false
    options.groupableDelay = 2.0
    options.groupableDelayType = .atMost
    
    let subscription = ndk.subscribe(
        filter: NDKFilter(kinds: [1]),
        options: options
    )
    
    // Verify configuration was applied
    let coordinator = // ... get internal coordinator
    let state = await coordinator.inspect()
    
    XCTAssertFalse(state.isGroupable)
    XCTAssertEqual(state.groupableDelay, 2.0)
    XCTAssertEqual(state.groupableDelayType, .atMost)
}
```

### Test Grouping Behavior

```swift
func testSubscriptionsGroupedCorrectly() async throws {
    let filter = NDKFilter(kinds: [1], authors: ["alice"])
    
    // Create multiple subscriptions with same filter
    let sub1 = ndk.subscribe(filter: filter)
    let sub2 = ndk.subscribe(filter: filter)
    let sub3 = ndk.subscribe(filter: filter)
    
    // Check grouping state
    #if DEBUG
    let groups = await relayManager.debugGroupingState()
    
    // Should have one group with three subscriptions
    XCTAssertEqual(groups.count, 1)
    let subscriptionIds = groups.values.first ?? []
    XCTAssertEqual(subscriptionIds.count, 3)
    #endif
}
```

### Test Non-Groupable Subscriptions

```swift
func testNonGroupableSubscriptionsStaySeparate() async throws {
    let filter = NDKFilter(kinds: [1])
    
    // Create non-groupable subscription
    let options = NDKSubscriptionOptions()
    options.groupable = false
    
    let sub1 = ndk.subscribe(filter: filter, options: options)
    let sub2 = ndk.subscribe(filter: filter, options: options)
    
    #if DEBUG
    // Each should be in its own group
    let groupCount = await relayManager.debugGroupCount()
    XCTAssertEqual(groupCount, 2)
    #endif
}
```

## Benefits

1. **Faster Tests**: Use `flushPendingGroups()` to skip delays
2. **Better Assertions**: Inspect internal state without complex async chains
3. **Debugging**: See exactly how subscriptions are grouped
4. **Maintainability**: Tests are less coupled to implementation details

## Best Practices

1. Use `#if DEBUG` for debug-only utilities
2. Prefer `inspect()` over multiple async property accesses
3. Use `flushPendingGroups()` to make tests deterministic
4. Test both groupable and non-groupable scenarios
5. Verify grouping behavior with different filters and options