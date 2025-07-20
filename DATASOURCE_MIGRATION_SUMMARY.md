# NDKDataSource Migration Summary

## Overview

Successfully migrated all internal data access to use the unified NDKDataSource API, eliminating the need for separate `internalFetchEvents` and `internalSubscribe` methods. This ensures all data access benefits from:

1. **Smart subscription aggregation** - Multiple components requesting the same data share subscriptions
2. **Cache integration** - Automatic cache freshness management with `maxAge` parameter
3. **Relay selection intelligence** - Proper relay routing and outbox model support
4. **Consistent data flow patterns** - Everything uses the same declarative API

## Key Changes

### 1. Removed Internal Fetch Methods
- ✅ Deleted `internalFetchEvents` and `internalFetchEvent` methods
- ✅ Deleted `InternalFetchUtilities.swift` helper file
- ✅ All fetching now uses NDKDataSource with appropriate `maxAge` values

### 2. Migrated Continuous Subscriptions
Instead of `internalSubscribe`, components now use NDKDataSource's `events` AsyncStream:

```swift
// OLD
let eventStream = await ndk.internalSubscribe(filter: filter)
for await event in eventStream { ... }

// NEW
let dataSource = NDKDataSource(
    ndk: ndk,
    filter: filter,
    maxAge: 0, // Always fresh for real-time monitoring
    cachePolicy: .cacheWithNetwork
)
for await event in await dataSource.events { ... }
```

### 3. Components Migrated

#### Production Code
- ✅ **NDKZapManager** - Real-time zap monitoring
- ✅ **NDKLightningZapProtocol** - Zap receipt waiting
- ✅ **NWCResponseHandler** - NWC response monitoring (3 instances)
- ✅ **NDKBunkerSigner** - Bunker communication
- ✅ **NDKFetchingStrategy** - Outbox model fetching
- ✅ **NIP60Wallet** - Wallet event monitoring
- ✅ **NDKUser** - Profile and relay list fetching
- ✅ **NDKContactList** - Contact list fetching
- ✅ **NDKRelayList** - Relay list fetching
- ✅ **NDKOutboxManager** - Outbox queries
- ✅ **NDKProfileManager** - Profile fetching
- ✅ **NDKPool** - Blocked relay monitoring
- ✅ **NDKOutboxTracker** - Relay discovery

#### Internal Methods Replaced
- ✅ `NDKPool.fetchEventInternal` → NDKDataSource
- ✅ `NDKProfileManager.fetchEventsInternal` → NDKDataSource
- ✅ `NDKOutboxTracker.fetchEventsInternal` → NDKDataSource

### 4. Deprecation Warnings Added
Added deprecation warnings to public fetch methods to guide users toward NDKDataSource:
- ✅ `fetchEvents()` - Deprecated with migration guidance
- ✅ `fetchEvent()` - Deprecated with migration guidance

## maxAge Configuration Guidelines

Based on the migration, here are the recommended `maxAge` values for different use cases:

| Use Case | maxAge | Rationale |
|----------|--------|-----------|
| Real-time monitoring (zaps, notifications) | 0 | Always need fresh data |
| Profile metadata | 3600 (1 hour) | Profiles change infrequently |
| Relay lists (NIP-65) | 86400 (24 hours) | Relay configurations rarely change |
| Contact lists | 600 (10 minutes) | Balance between freshness and efficiency |
| Payment methods | 300 (5 minutes) | Payment configs may change but not rapidly |
| Wallet events | 0 | Financial data must be real-time |

## Benefits Achieved

1. **Unified Data Flow**: All data access now goes through the same intelligent system
2. **Automatic Caching**: Components get appropriate caching based on their `maxAge` tolerance
3. **Smart Subscription Management**: The system automatically groups and manages subscriptions
4. **Better Performance**: Reduced redundant network requests through intelligent caching
5. **Maintainability**: Single point of optimization for all data access patterns

## Next Steps

1. Implement cache timestamp tracking in SQLite cache adapter
2. Add documentation for MainActor.run pattern for UI updates
3. Update test files to use NDKDataSource (lower priority)

The migration successfully eliminates the "internal" API pattern, ensuring all components benefit from the same intelligent data management system.