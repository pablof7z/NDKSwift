# Bug Report: NostrMessage EVENT Serialization Missing Subscription ID

## Summary
The `NostrMessage.serialize()` method does not include the subscription ID when serializing EVENT messages, even though the subscription ID is stored in the message and the parser expects it.

## Location
File: `/Sources/NDKSwift/Relay/NostrMessage.swift`
Lines: 184-187

## Current Behavior
When serializing an EVENT message with a subscription ID:
```swift
case let .event(_, event):
    array.append("EVENT")
    let eventDict = try JSONCoding.encodeToDictionary(event)
    array.append(eventDict)
```

The subscription ID is ignored (note the underscore `_` in the pattern match).

## Expected Behavior
When an EVENT message has a subscription ID, it should be included in the serialized output:
```swift
case let .event(subscriptionId, event):
    array.append("EVENT")
    if let subscriptionId = subscriptionId {
        array.append(subscriptionId)
    }
    let eventDict = try JSONCoding.encodeToDictionary(event)
    array.append(eventDict)
```

## Impact
- Round-trip serialization/deserialization of EVENT messages with subscription IDs fails
- EVENT messages sent to relays may be missing subscription IDs when they should have them
- This could affect relay subscription management and event routing

## Test Case
The bug was discovered through the unit test `testRoundTripEvent()` in `NostrMessageTests.swift`, which creates an EVENT message with a subscription ID, serializes it, then deserializes it, expecting the subscription ID to be preserved.

## Recommendation
Fix the serialization method to include the subscription ID when present. This maintains compatibility with the Nostr protocol specification where EVENT messages can optionally include a subscription ID.