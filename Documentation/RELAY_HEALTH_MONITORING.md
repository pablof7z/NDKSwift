# NIP-60 Relay Health Monitoring in NDKSwift

## Overview

NDKSwift implements relay health monitoring for NIP-60 Cashu wallets to ensure wallet state consistency across multiple relays. This feature helps detect and repair relay inconsistencies by tracking which wallet events each relay has.

## How It Works

### Event Source Tracking

The relay health monitoring system leverages NDKSwift's built-in `NDKEventTracker` to record which relays have which events:

1. **During Event Processing**: Every event received from a relay is automatically tracked:
   ```swift
   // In NDK.processEvent
   await eventTracker.markSeen(eventId: event.id, relay: relay.url)
   ```

2. **During Wallet Load**: The wallet queries the event tracker to build its relay health state:
   ```swift
   // In loadTokenEvents
   let seenOnRelays = await ndk.eventTracker.getSeenOnRelays(eventId: event.id)
   for relayUrl in seenOnRelays {
       recordEventFromRelay(event.id, from: relayUrl)
   }
   ```

### Health Calculation

Relay health is calculated by comparing what each relay has versus what it should have:

```swift
public func getRelayHealth() async -> [RelayHealth] {
    let canonicalEvents = calculateCanonicalEventSet()
    
    return walletRelays.map { relay in
        let knownEvents = relayEventSets[relay.url] ?? Set()
        let missing = canonicalEvents.subtracting(knownEvents)
        let extra = knownEvents.intersection(deletedTokenEventIds)
        
        return RelayHealth(
            relay: relay,
            knownEvents: knownEvents.count,
            missingEvents: Array(missing),
            extraEvents: Array(extra),
            isHealthy: missing.isEmpty && extra.isEmpty
        )
    }
}
```

### Real-time Monitoring

For ongoing relay health tracking, use the real-time monitoring feature:

```swift
// Start monitoring new wallet events
let subscription = try await wallet.startRealtimeMonitoring()

// The subscription will automatically track relay sources for new events
// and update the relay health state in real-time
```

## Usage Example

```swift
// Load wallet
let wallet = NDKCashuWallet(ndk: ndk)
try await wallet.load()

// Check relay health
let health = await wallet.getRelayHealth()

for relayHealth in health {
    if !relayHealth.isHealthy {
        print("Relay \(relayHealth.relay.url) has issues:")
        print("  Missing events: \(relayHealth.missingEvents.count)")
        print("  Extra events: \(relayHealth.extraEvents.count)")
        
        // Repair the relay
        try await wallet.repairRelay(
            relayHealth.relay,
            missingEventIds: relayHealth.missingEvents
        )
    }
}

// Start real-time monitoring
let subscription = try await wallet.startRealtimeMonitoring()
```

## RelayHealth Structure

```swift
public struct RelayHealth: Sendable {
    public let relay: NDKRelay
    public let knownEvents: Int
    public let missingEvents: [String]  // Events wallet has but relay doesn't
    public let extraEvents: [String]     // Deleted events relay still has
    public let isHealthy: Bool
}
```

## Key Implementation Details

1. **Event Source Tracking**: Uses `NDKEventTracker` to record which relays have seen each event
2. **Subscription-based Loading**: Uses `subscribe()` instead of `fetchEvents()` to ensure relay tracking
3. **Canonical Event Set**: Current wallet state minus deleted events
4. **Automatic Repair**: Can republish missing events to unhealthy relays

## Comparison with NDK TypeScript

Both implementations track relay health, but with different approaches:

- **NDKSwift**: Uses centralized `NDKEventTracker` for all relay source tracking
- **NDK TypeScript**: Tracks via `event:dup` handler and `onRelays` property

The Swift implementation's centralized approach provides cleaner separation of concerns and avoids the need for duplicate event callbacks.