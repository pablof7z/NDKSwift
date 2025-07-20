# NDKSwift Declarative Refactoring - Step 2

## Overview

The declarative architecture refactoring has been successfully implemented, but critical fundamental features are missing. This document outlines the essential enhancements needed to make the implementation production-ready.

## Critical Missing Features

### 1. Smart Filter Aggregation (FUNDAMENTAL)

**Current State**: Basic filter merging that can create inefficient subscriptions
**Problem**: Naive aggregation can request `(kind:1 OR kind:2) AND (author:A OR author:B)` when we actually want `(kind:1 AND author:A) OR (kind:2 AND author:B)`

**Required Implementation**:
```swift
// Enhanced filter aggregation that detects incompatible filters
extension NDKDataRequirementManager {
    private func aggregateFilters(_ filters: [NDKFilter]) -> [NDKFilter] {
        // Group filters by compatibility
        let groups = groupCompatibleFilters(filters)
        
        // Each group becomes a separate aggregated filter
        return groups.map { mergeCompatibleFilters($0) }
    }
    
    private func groupCompatibleFilters(_ filters: [NDKFilter]) -> [[NDKFilter]] {
        // Filters are compatible if they:
        // 1. Have overlapping kinds OR no kind restrictions
        // 2. Have overlapping authors OR no author restrictions
        // 3. Have compatible tag filters
        // Otherwise, keep them separate
    }
}
```

### 2. Relay Source Tracking (FUNDAMENTAL)

**Current State**: Events are processed without tracking which relay provided them
**Problem**: Applications (especially NIP60 wallets) NEED to know where events were found

**Required Implementation**:
```swift
// Update NDKCache protocol
protocol NDKCache {
    // Add relay tracking to processEvent
    func processEvent(_ event: NDKEvent, from relay: RelayURL, subscriptionId: String) async throws
    
    // New method to query relay sources
    func getRelaySources(for eventId: String) async -> Set<RelayURL>
}

// Update NDKSQLiteCache
extension NDKSQLiteCache {
    // Add relay_sources table
    /*
    CREATE TABLE IF NOT EXISTS relay_sources (
        event_id TEXT NOT NULL,
        relay_url TEXT NOT NULL,
        first_seen INTEGER NOT NULL,
        PRIMARY KEY (event_id, relay_url)
    );
    */
    
    private func trackRelaySource(eventId: String, relay: RelayURL) async throws {
        // Store relay source in database
    }
}
```

### 3. Weak Observer Pattern for Cache

**Current State**: Direct observer references could cause retain cycles
**Problem**: Memory leaks if observers aren't explicitly removed

**Required Implementation**:
```swift
struct WeakObserver: Hashable {
    weak var observer: CacheObserver?
    let id: UUID
    
    static func == (lhs: WeakObserver, rhs: WeakObserver) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Update cache to use WeakObserver and auto-cleanup
private func cleanupNilObservers() {
    for (signature, observers) in observers {
        let activeObservers = observers.filter { $0.observer != nil }
        if activeObservers.isEmpty {
            observers.removeValue(forKey: signature)
        } else {
            observers[signature] = activeObservers
        }
    }
}
```

## Implementation Plan

### Phase 1: Relay Source Tracking (2-3 hours)
1. Update `NDKCache` protocol with relay tracking methods
2. Add relay_sources table to SQLite schema
3. Update `processEvent` throughout to pass relay information
4. Implement `getRelaySources` query method
5. Update `InternalSubscriptionManager` to properly track relay sources

### Phase 2: Smart Filter Aggregation (3-4 hours)
1. Implement filter compatibility detection
2. Create `groupCompatibleFilters` algorithm
3. Update `aggregateFilters` to return array of filters
4. Modify `flushPendingRequirements` to handle multiple aggregated filters
5. Update `DataRequirement` to handle filter arrays

### Phase 3: Weak Observer Pattern (1-2 hours)
1. Create `WeakObserver` struct
2. Update cache observer storage
3. Implement automatic cleanup on access
4. Add periodic cleanup task if needed

### Phase 4: Integration & Testing (2-3 hours)
1. Ensure NIP60 wallet can query relay sources
2. Verify filter aggregation produces optimal subscriptions
3. Test memory management with weak observers
4. Update examples to demonstrate relay source tracking

## Success Criteria

1. **Filter Aggregation**: Incompatible filters create separate subscriptions automatically
2. **Relay Tracking**: Every event in cache has associated relay source information
3. **Memory Safety**: No retain cycles in cache observation
4. **Performance**: Aggregation reduces redundant network requests by >50% in typical usage
5. **NIP60 Support**: Wallet implementation can determine relay availability for funds

## API Changes

### For Users
```swift
// New API to get relay sources
let relaySources = await ndk.cache.getRelaySources(for: event.id)

// Filter aggregation happens automatically - no API change
let dataSource = NDKDataSource(ndk: ndk, filter: complexFilter)
```

### Internal Changes
- `processEvent` gains relay parameter throughout
- `NDKDataRequirementManager` may create multiple subscriptions per flush
- Cache observers automatically cleaned up

## Non-Goals

- Complex aggregation algorithms (keep it simple but correct)
- Relay performance metrics (just source tracking)
- Query optimization beyond basic compatibility grouping

## Timeline

Estimated total: 8-12 hours of focused development

This is not an enhancement - these are FUNDAMENTAL features required for NDKSwift to function correctly in production applications.