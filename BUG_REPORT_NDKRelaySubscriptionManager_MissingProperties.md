# Bug Report: NDKRelaySubscriptionManager References Non-Existent Properties

## Issue
`NDKRelaySubscriptionManager` references properties on `InternalSubscription` that don't exist in the implementation.

## Location
- File: `/Sources/NDKSwift/Relay/NDKRelaySubscriptionManager.swift`
- Lines: 24, 39, 56-57

## Details

The following properties are referenced but don't exist on `InternalSubscription`:
1. `isGroupable` (line 24)
2. `groupableDelay` (line 56)
3. `groupableDelayType` (line 57)

### Code References

```swift
// Line 24
let isGroupable = await subscription.isGroupable

// Line 39
closeOnEose: subscription.closeOnEose  // This property exists

// Lines 56-57
let delay = await subscription.groupableDelay ?? 0.1
let delayType = await subscription.groupableDelayType ?? .atLeast
```

## Impact
This code will not compile if `NDKRelaySubscriptionManager` is used, as it references non-existent properties.

## Expected Properties
Based on usage, `InternalSubscription` should have:
- `var isGroupable: Bool`
- `var groupableDelay: TimeInterval?`
- `var groupableDelayType: NDKSubscriptionDelayType?`

## Current Implementation
`InternalSubscription` only has:
- `closeOnEose: Bool` (which is correctly used)
- No grouping-related properties

## Recommendation
Either:
1. Add the missing properties to `InternalSubscription`
2. Remove the grouping logic from `NDKRelaySubscriptionManager`
3. Move grouping configuration to a different location

This appears to be incomplete implementation where the subscription grouping feature was partially implemented.