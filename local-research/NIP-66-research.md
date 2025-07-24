# NIP-66 Research: Relay Discovery and Monitoring

## Overview

NIP-66 (Relay Discovery and Liveness Monitoring) is a protocol specification for discovering and monitoring Nostr relays in a decentralized manner. It defines a system where independent monitors publish relay health and capability information as Nostr events.

## Key Concepts

### Event Types

1. **Kind 30166: Relay Discovery Event**
   - Addressable event (NIP-33) that signals a relay's online status
   - Contains relay metadata, round-trip times, and capabilities
   - Published when a monitor determines a relay is online

2. **Kind 10166: Monitor Announcement Event**
   - Replaceable event declaring a monitor's intent and frequency
   - Specifies what checks the monitor performs
   - Helps clients identify reliable monitors

### Architecture Components

- **Relay Operator**: Someone who operates a relay
- **Monitor**: A pubkey that monitors relays and publishes 30166 events regularly
- **Ad-hoc Monitor**: A pubkey that monitors relays irregularly
- **Monitor Service**: A group/individual monitoring relays using one or more Monitors
- **Check**: Specific data points tested by a monitor (websocket, NIP-11, DNS, etc.)

## Practical Implementation: nostr-watch

The primary implementation is **nostr-watch** by sandwichfarm:
- TypeScript implementation for monitoring, auditing, and validating relays
- Provides NIP-66 aggregation control flow utilities
- Includes extensible libraries for checking relay liveness
- Supports websocket, geodata, SSL, NIP-11, and DNS checks

## Real-World Usage Patterns

### For Clients

1. **Relay Discovery**
   ```typescript
   // Filter 30166 events from trusted monitors
   const filter = {
     kinds: [30166],
     authors: [trustedMonitorPubkey],
     since: Math.floor(Date.now() / 1000) - 3600 // Last hour
   };
   ```

2. **Use Cases**
   - Geographic relay discovery (find relays near user)
   - NIP support filtering (find relays supporting specific features)
   - Accessibility search (free vs paid relays, auth requirements)
   - Real-time status monitoring in relay lists

3. **Fallback Strategy**
   - Clients should have fallbacks when NIP-66 events aren't available
   - Can use traditional relay lists or hardcoded relays

### For Monitors

1. **Publishing Frequency**
   - Monitors declare check frequency in 10166 events
   - Typically check relays every hour (3600 seconds)
   - Publish 30166 events immediately when checks complete

2. **Data Collection**
   - Round-trip times (open/read/write operations)
   - NIP-11 information document
   - Supported NIPs
   - Payment/auth requirements
   - Geographic location

## Integration with NDK

While NDK doesn't currently implement NIP-66 directly, it could benefit from:

1. **Enhanced Relay Selection**
   - Use NIP-66 data for intelligent relay routing
   - Select relays based on capabilities and performance
   - Avoid dead or unreliable relays

2. **Dynamic Relay Pool Management**
   - Update relay pools based on liveness data
   - Prioritize relays with better round-trip times
   - Filter relays by required NIPs support

3. **Geographic Optimization**
   - Select relays closer to users
   - Implement region-based relay pools

## Example Implementation Pattern

```typescript
class RelayDiscoveryClient {
  async discoverRelays(options: {
    supportedNips?: number[];
    requiresFreeAccess?: boolean;
    maxRtt?: number;
    geohash?: string;
  }) {
    // Subscribe to 30166 events from trusted monitors
    const filter = {
      kinds: [30166],
      authors: this.trustedMonitors,
      since: this.getRecentTimestamp(),
      // Filter by tags based on options
      "#N": options.supportedNips?.map(String),
      "#R": options.requiresFreeAccess ? ["!payment"] : undefined,
      "#g": options.geohash ? [options.geohash] : undefined
    };
    
    const events = await this.ndk.fetchEvents(filter);
    
    // Parse and filter by RTT if specified
    return events
      .map(event => this.parseRelayInfo(event))
      .filter(relay => !options.maxRtt || relay.rtt < options.maxRtt);
  }
}
```

## Benefits Over Traditional Approaches

1. **Decentralized Discovery**
   - No central authority controlling relay lists
   - Multiple monitors provide competitive/honest data
   - Web-of-trust for monitor reliability

2. **Real-Time Health Data**
   - Up-to-date liveness information
   - Performance metrics (RTT)
   - Capability detection

3. **Reduced Client Complexity**
   - Clients don't need to probe relays themselves
   - Reduces spam/load on relays
   - Unified implementation pattern

## Security Considerations

- Monitors may publish erroneous data (intentionally or not)
- Clients should use web-of-trust to identify reliable monitors
- Multiple monitors provide data redundancy
- Defensive programming needed to handle bad data

## Future Considerations for NDKSwift

1. **NIP-66 Consumer**
   - Subscribe to relay discovery events
   - Parse and cache relay metadata
   - Use for intelligent relay selection

2. **Monitor Implementation**
   - Optionally act as a monitor
   - Publish relay health data
   - Contribute to the ecosystem

3. **Integration Points**
   - Enhance NDKRelayPool with discovery data
   - Add relay capability filtering
   - Implement geographic relay selection