# Critical Issue: NetworkOnly Cache Policy Still Delivers Cached Events

## Problem Description

The `CacheFirstTests.testNetworkOnlyPolicy` test is failing because the `networkOnly` cache policy is incorrectly delivering cached events. When using `CachePolicy.networkOnly`, the system should skip the cache entirely and only fetch from the network, but cached events are being delivered immediately.

## Symptoms

- Test failure: `CacheFirstTests.testNetworkOnlyPolicy`
- Expected: 0 cached events delivered
- Actual: 3 cached events delivered
- Error message: "NetworkOnly should not deliver cached events immediately"

## Root Cause Analysis

The issue appears to be in the NDKSubscriptionRequirement or NDKSubscriptionManager implementation:

1. When `cachePolicy` is set to `.networkOnly`, the system still sets up cache observation
2. The data requirement manager doesn't properly distinguish between cache policies when delivering events
3. The cache observation mechanism is likely being set up regardless of the cache policy

## Impact

- Applications using `networkOnly` policy receive stale cached data when they explicitly requested fresh network data
- This defeats the purpose of the `networkOnly` policy
- Could lead to bugs in applications that rely on always-fresh data (e.g., real-time features, authentication flows)

## Affected Code

- `Sources/NDKSwift/DataSource/NDKSubscriptionManager.swift` - registerRequirement method
- `NDKSubscriptionRequirement` class (location unclear, possibly internal to NDKSubscriptionManager)
- Cache observation setup in the data requirement flow

## Proposed Fix

The fix requires modifying the data requirement registration logic:

1. In `NDKSubscriptionManager.registerRequirement()`:
   - When `cachePolicy == .networkOnly`, skip cache observation setup entirely
   - Ensure `shouldFetchFromNetwork` is always true for networkOnly
   - Don't deliver any cached events to the event stream

2. In `NDKSubscriptionRequirement` (once located):
   - Add a check for cache policy before setting up cache observers
   - Skip cache delivery methods when policy is networkOnly

## Temporary Workaround

Until the bug is fixed, developers should:
1. Clear the cache before using networkOnly subscriptions if fresh data is critical
2. Use a combination of cache clearing and networkOnly policy
3. Be aware that networkOnly currently behaves like cacheWithNetwork

## Test Code Reference

The failing test is at:
- `Tests/NDKSwiftTests/Unit/DataSource/CacheFirstTests.swift:193-226`

## Priority

**HIGH** - This is a fundamental violation of the cache policy contract and affects data freshness guarantees.