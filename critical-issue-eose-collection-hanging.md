# Critical Issue: EOSECollectTests Hanging

## Problem
The `EOSECollectTests` hangs forever when running, even though it doesn't connect to any real relays. The test times out after 2 minutes.

## Root Cause Analysis
The issue is in the test's use of `NDKSubscription` with `closeOnEose: true`:

```swift
let dataSource = NDKSubscription(
    ndk: ndk,
    filter: filter,
    closeOnEose: true
)

var events: [NDKEvent] = []
for await event in dataSource.events {
    events.append(event)
}
```

When there are no relay connections:
1. The subscription starts but has no relays to subscribe to
2. No EOSE (End of Stored Events) message ever arrives
3. The AsyncSequence never completes
4. The for-await loop hangs forever waiting for events or completion

## Impact
- Any code using `closeOnEose` subscriptions without relay connections will hang
- This affects testing scenarios and edge cases where NDK is used without relays
- The subscription system doesn't handle the "no relays" case gracefully

## Recommendation
The subscription system needs to handle the no-relay case by either:
1. Immediately completing the AsyncSequence when no relays are available
2. Throwing an error when trying to create subscriptions without relays
3. Adding a timeout mechanism for EOSE collection

## Temporary Fix
The test remains in DisabledTests until the subscription system is fixed to handle no-relay scenarios gracefully.