# Outbox Model Implementation

## Overview

The outbox model (NIP-65) is a relay discovery and selection system that helps clients find the optimal relays for communicating with specific users. This document describes the internal architecture and behavior of NDKSwift's outbox implementation.

## Core Principle

The outbox model is **only activated when the user does not specify explicit relays**. When users provide specific relay URLs for publishing or subscribing, the system bypasses outbox logic entirely and uses the provided relays directly.

## High-Level Flow

### Publishing Flow
1. **Immediate Action**: Event publishes to known relays without waiting
2. **Progressive Enhancement**: System discovers and connects to optimal relays in background
3. **Relay Management**: Automatically connects to relays as needed, manages connections

### Key Behaviors
- **Non-blocking**: Publishing never waits for relay discovery or new connections
- **Dynamic relay connections**: System connects to relays on-demand when needed
- **Progressive delivery**: Event reaches more relays as discovery completes
- **Fallback strategy**: Always uses app's configured relays as baseline

## Architecture Components

### 1. Relay Discovery

The system maintains a cache of relay preferences (kind 10002 events) for each user, which specify:
- **Read relays**: Where the user reads events from
- **Write relays**: Where the user publishes events to

When relay information is not cached, the system:
1. Uses fallback relays (the app's explicitly configured relays) immediately
2. Triggers background discovery to fetch relay lists from the network
3. Updates active operations when relay information is discovered

### 2. Subscription Handling

When creating a subscription without explicit relays:

1. **Initial Setup**:
   - The system checks which authors in the filter have known relay information
   - For authors with known relays: 
     - Connects to their write relays if not already connected
     - Creates relay-specific subscriptions immediately
   - For unknown authors: 
     - Subscribes on fallback relays immediately (non-blocking)
     - Marks them for background discovery

2. **Background Discovery**:
   - A background task fetches relay lists (kind 10002) for unknown authors
   - Discovery happens on dedicated "outbox relays" if configured, otherwise on all connected relays
   - This is completely non-blocking - the subscription receives events from fallback relays while discovery happens

3. **Dynamic Updates**:
   - When relay information is discovered:
     - System connects to the newly discovered write relays
     - Creates new DataRequirements for these relays
     - Attaches them to the same observers as the original subscription
   - Both the fallback and specific relay subscriptions remain active
   - Events flow from all sources - no events are missed during discovery

### 3. Publishing Handling

When publishing an event without explicit relays:

1. **Relay Selection**:
   - Always includes the app's explicitly configured relays (fallback relays)
   - Adds the author's write relays (or read relays if no write relays found)
   - For events with <10 p-tags: Also publishes to read relays of each tagged user
   - For events with ≥10 p-tags: Skips p-tagged users' relays to avoid spam
   - Applies ranking and filtering to limit total relay count

2. **Relay Connection**:
   - If selected relays are not currently connected, the system connects to them
   - Connection happens automatically before publishing
   - The relay pool manages these connections and keeps them alive as needed

3. **Initial Publish**:
   - Immediately publishes to all selected relays that are connected or can be connected
   - For p-tagged users without known relay information:
     - Publishes to fallback relays immediately (non-blocking)
     - Tracks which users need relay discovery

4. **Non-Blocking Discovery**:
   - If any p-tagged users lack relay information (NIP-65), spawns a background task
   - Subscribes to kind 10002 events on fallback relays to discover user relay lists
   - Waits up to 5 seconds for relay discovery
   - When relay lists are discovered:
     - Connects to the newly discovered read relays if not already connected
     - Publishes the event to these relays once connected
     - Does not re-publish to relays already used in the initial publish

## Key Design Decisions

### AsyncStream Communication

The system uses Swift's AsyncStream for relay discovery notifications rather than callbacks or notifications. This provides:
- Type-safe communication between components
- Natural integration with Swift concurrency
- Proper cancellation and cleanup

### No Persistent State for Publishing

Unlike subscriptions which can be long-lived, publishing is a one-time operation. The system:
- Does not maintain persistent state about pending publishes
- Uses simple timeout-based background tasks
- Accepts that some late discoveries might be missed

### Separation of Concerns

- **NDKOutboxTracker**: Manages relay information cache and emits discovery events
- **NDKDataRequirementManager**: Handles subscription updates when relays are discovered
- **NDKPublishingStrategy**: Manages publishing with background relay discovery
- **NDKRelaySelector**: Implements relay selection logic based on NIP-65 rules

## Failure Modes and Edge Cases

### Unknown Authors

When relay information cannot be found:
- Subscriptions continue using fallback relays indefinitely
- Publishing uses fallback relays and may miss optimal delivery
- The system tracks lookup attempts to avoid repeated failed discoveries

### Relay List Changes

When a user updates their relay list:
- New subscriptions will use the updated relays
- Existing subscriptions continue using the old relays
- Publishing always uses the most recent cached information

### Performance Considerations

- Relay discovery has a 5-second timeout for publishing
- Subscription updates create additional network connections
- The system limits discovery attempts to prevent infinite loops
- Cache entries have TTL to ensure eventual consistency

## Benefits of This Architecture

1. **Immediate Responsiveness**: Operations start immediately with fallback relays
2. **Progressive Enhancement**: Relay discovery improves routing without blocking
3. **Respect for User Intent**: Explicit relay specification bypasses all automatic behavior
4. **Resource Efficiency**: Shared discovery results across multiple operations
5. **Failure Tolerance**: Operations succeed even without relay discovery