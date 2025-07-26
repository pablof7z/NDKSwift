# Outbox Model Implementation

## Overview

The outbox model (NIP-65) is a relay discovery and selection system that helps clients find the optimal relays for communicating with specific users. This document describes the internal architecture and behavior of NDKSwift's outbox implementation.

## Core Principles

1. **User Control First**: The outbox model is **only activated when the user does not specify explicit relays**. When users provide specific relay URLs for publishing or subscribing, the system bypasses outbox logic entirely and uses the provided relays directly.

2. **Per-Author Scaling**: Instead of hard relay limits, the system scales relay connections based on the number of authors involved (2 relays per author by default).

3. **Connection Efficiency**: Already-connected relays are prioritized to minimize new connections and improve performance.

4. **Non-Blocking Operations**: All relay discovery and connection happens in the background without blocking publish or subscribe operations.

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
     - Selects 2 write relays per author (prioritizing already-connected relays)
     - Connects to selected relays if not already connected
     - Creates relay-specific subscriptions immediately
   - For unknown authors: 
     - Subscribes on fallback relays immediately (non-blocking)
     - Marks them for background discovery
   - **Relay Scaling**: Total relays scale with author count (2 × number of authors)
   - **Soft Limit**: Maximum 50 relays for fetching (can be exceeded for large author sets)

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

1. **Relay Selection Algorithm**:
   - **Base Set**: Always includes the app's explicitly configured relays (fallback relays)
   - **Author Relays**: Adds the author's write relays (or read relays if no write relays found)
   - **P-tag Handling**:
     - For events with <10 p-tags: Includes read relays of each tagged user (per NIP-65)
     - For events with ≥10 p-tags: Skips p-tagged users' relays to avoid relay spam
   - **Per-Author Scaling**: Selects 2 relays per involved author (configurable via `OutboxConstants.relaysPerAuthor`)
   - **Connection Priority**: Prioritizes already-connected relays over new connections
   - **Soft Limits**: Maximum 30 relays for publishing (can be exceeded based on author count)

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

## Building a Proper Outbox Implementation

### Key Design Principles

1. **Non-Blocking Everything**
   - Never wait for relay discovery before publishing or subscribing
   - Use fallback relays immediately while discovery happens in background
   - Treat relay discovery as an optimization, not a requirement

2. **Per-Author Relay Scaling**
   - Don't use hard limits on total relay count
   - Scale relay connections based on number of participants (2 relays per author)
   - This ensures proper coverage while avoiding connection explosion

3. **Connection Efficiency**
   - Always prioritize already-connected relays
   - Batch relay connections when possible
   - Reuse existing connections across multiple operations

4. **Intelligent Relay Selection**
   ```
   For Publishing:
   - Author's write relays (2)
   - Each p-tagged user's read relays (2 per user, if <10 p-tags)
   - Fallback to explicit/configured relays
   
   For Fetching:
   - Filter authors' write relays (2 per author)
   - Current user's read relays
   - P-tagged users' relays from filter
   ```

5. **Progressive Enhancement Pattern**
   ```swift
   // Example flow
   1. Start with known relays immediately
   2. Discover missing relay information in background
   3. Connect to newly discovered relays
   4. Enhance operation with better relay routing
   ```

### Implementation Best Practices

1. **Cache Management**
   - Cache relay lists (kind 10002) with reasonable TTL
   - Invalidate cache when users update their relay lists
   - Share cache across all operations for efficiency

2. **Connection Management**
   - Track relay connection state to avoid redundant connections
   - Implement connection pooling for frequently used relays
   - Handle relay disconnections gracefully with automatic reconnection

3. **Error Handling**
   - Treat relay discovery failures as non-fatal
   - Continue with fallback relays when discovery fails
   - Log discovery failures for debugging but don't surface to users

4. **Performance Optimization**
   - Limit relay discovery timeout (5 seconds recommended)
   - Batch multiple discovery requests together
   - Use relay ranking to prioritize reliable relays

### Common Pitfalls to Avoid

1. **Blocking on Discovery**
   - ❌ Waiting for relay lists before publishing
   - ✅ Publishing immediately to known relays

2. **Hard Relay Limits**
   - ❌ Maximum 10 relays regardless of participants
   - ✅ 2 relays per author, with soft maximum limits

3. **Ignoring Connected Relays**
   - ❌ Always connecting to "best" relays
   - ✅ Preferring already-connected relays

4. **Over-Publishing**
   - ❌ Publishing to all known relays for all p-tags
   - ✅ Limiting to <10 p-tags to avoid relay spam

### Testing Recommendations

1. **Test Scenarios**
   - User with no relay list
   - User with 50+ relays in their list
   - Events with 0, 5, 10, and 20 p-tags
   - Mixed scenarios with known and unknown users

2. **Performance Metrics**
   - Time to first publish/subscribe
   - Number of relay connections opened
   - Discovery completion time
   - Memory usage with large relay sets

3. **Edge Cases**
   - Relay discovery timeout
   - All relays are blocked/filtered
   - Relay list changes during operation
   - Network failures during discovery