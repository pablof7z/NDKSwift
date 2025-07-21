# NDKSwift Semantic Caching Implementation Plan

## Executive Summary

This document outlines the implementation plan for integrating semantic caching (ProfileCache and OutboxCache) into NDKSwift's declarative architecture refactoring. The goal is to create a unified system where developers declare data needs and the framework handles all optimization, caching, and routing intelligently.

**Key Principles:**
- NO backwards compatibility (unreleased library)
- Clean naming (no 'Enhanced' or 'New' prefixes)
- Semantic caching of computed results, not raw data
- Actor-based concurrency throughout
- Integrate incrementally, remove old code immediately

**Target Metrics:**
- 70% reduction in redundant relay requests
- <50ms event-to-UI latency
- 80% cache hit rate for profiles
- Zero manual subscription management

## Phase 1: Complete Cache Foundation (Week 1)

### Goal
Finish the reactive cache layer that both semantic caches will build upon.

### Tasks

#### 1.1 Extend NDKCache Protocol
```swift
protocol NDKCache {
    // Add observation capability
    func observeEvents(matching filter: NDKFilter, observer: CacheObserver) async -> ObservationHandle
    
    // Track relay sources for events
    func trackRelaySource(eventId: String, relay: String) async
    func getRelaySources(eventId: String) async -> Set<String>
    
    // Support maxAge queries
    func getLastFetchTime(for filter: NDKFilter) async -> Date?
    func recordFetchTime(for filter: NDKFilter) async
}
```

#### 1.2 SQLite Schema Updates
- Add `relay_sources` table: `(event_id TEXT, relay_url TEXT, received_at INTEGER)`
- Add `fetch_timestamps` table: `(filter_hash TEXT, fetched_at INTEGER)`
- Add compound indexes: `CREATE INDEX idx_events_kind_pubkey_created ON events(kind, pubkey, created_at)`
- Create Migration_v7_FetchTimestamps.swift

#### 1.3 Observer Implementation
- Modify `NDKSQLiteCache.processEvent` to notify matching observers
- Implement efficient filter matching using FilterSignature
- Handle weak references properly to avoid retain cycles
- Ensure thread-safe observer management

#### 1.4 Proactive Cache Invalidation
```swift
// Add to NDK
private func setupMetadataInvalidation() async {
    // Monitor current user's metadata changes
    let metadataFilter = NDKFilter(
        authors: [currentUser.pubkey],
        kinds: [0, 3, 10002, 10000],
        limit: 0  // Continuous subscription
    )
    
    let dataSource = NDKDataSource(
        ndk: self,
        filter: metadataFilter,
        maxAge: 0
    )
    
    for await event in dataSource.events {
        await cache.invalidateMetadata(for: event.pubkey, kind: event.kind)
    }
}
```

## Phase 2: Profile Cache Implementation (Week 2)

### Goal
Semantic caching for user profiles with reactive updates and LRU eviction.

### Tasks

#### 2.1 Create ProfileCache Actor
```swift
actor ProfileCache {
    private var cache: LRUCache<Pubkey, CachedProfile>
    private var observers: [Pubkey: Set<WeakObserver>]
    private let maxCacheSize = 5_000
    private let maxLRUSize = 1_000
    
    enum CachedProfile {
        case profile(NDKUserProfile, fetchedAt: Date)
        case noProfile(checkedAt: Date)
        case error(Error, occurredAt: Date)
    }
    
    func getProfile(for pubkey: Pubkey, maxAge: TimeInterval) async -> NDKUserProfile?
    func setProfile(for pubkey: Pubkey, profile: NDKUserProfile) async
    func setNoProfile(for pubkey: Pubkey) async
    func observeProfile(for pubkey: Pubkey) -> AsyncStream<NDKUserProfile?>
    func invalidate(pubkey: Pubkey) async
}
```

#### 2.2 ProfileDataSource Convenience Wrapper
```swift
@MainActor
public class ProfileDataSource: ObservableObject {
    @Published public private(set) var profile: NDKUserProfile?
    @Published public private(set) var isLoading: Bool = false
    
    public init(ndk: NDK, pubkey: Pubkey, maxAge: TimeInterval = 3600) {
        Task {
            // First, try cache
            if let cached = await ndk.profileCache.getProfile(for: pubkey, maxAge: maxAge) {
                self.profile = cached
            }
            
            // Then subscribe for updates
            let stream = await ndk.profileCache.observeProfile(for: pubkey)
            for await profile in stream {
                self.profile = profile
            }
        }
    }
}
```

#### 2.3 Integration with NDKProfileManager
- Replace existing fetchProfile logic with ProfileCache
- Remove old caching code immediately
- Ensure profile updates trigger observer notifications
- Add profile-specific transform to NDKDataSource

#### 2.4 Profile Transformers
```swift
extension NDKDataSource where T == NDKUserProfile {
    convenience init(ndk: NDK, pubkey: Pubkey, maxAge: TimeInterval = 3600) {
        self.init(
            ndk: ndk,
            filter: NDKFilter(authors: [pubkey], kinds: [0], limit: 1),
            maxAge: maxAge,
            transform: { event in
                try? NDKUserProfile.parse(from: event)
            }
        )
    }
}
```

## Phase 3: Outbox Cache Implementation (Week 3)

### Goal
Intelligent relay routing with cached preferences and automatic invalidation.

### Tasks

#### 3.1 Create OutboxCache Actor
```swift
actor OutboxCache {
    private var cache: [Pubkey: RelayPreferences] = [:]
    private let defaultMaxAge: TimeInterval = 3600
    
    struct RelayPreferences {
        let writeRelays: [RelayURL]
        let readRelays: [RelayURL]
        let computedAt: Date
        let source: RelayListSource
    }
    
    enum RelayListSource {
        case explicit(eventId: String)  // From kind:10002
        case implicit                   // Inferred from posting history
        case default                    // Fallback relays
    }
    
    func getRelayPreferences(for pubkey: Pubkey, maxAge: TimeInterval) async -> RelayPreferences
    func setRelayPreferences(for pubkey: Pubkey, preferences: RelayPreferences) async
    func invalidate(pubkey: Pubkey) async
    func invalidateAll() async
}
```

#### 3.2 Integration with NDKOutboxResolver
```swift
extension NDKOutboxResolver {
    func relaysFor(pubkey: Pubkey, maxAge: TimeInterval = 3600) async -> [RelayURL] {
        // 1. Check cache first
        if let cached = await outboxCache.getRelayPreferences(for: pubkey, maxAge: maxAge) {
            return cached.writeRelays
        }
        
        // 2. Not in cache or too old - fetch kind:10002
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: NDKFilter(authors: [pubkey], kinds: [10002]),
            maxAge: maxAge
        )
        
        let relayListEvent = await dataSource.events.first { _ in true }
        
        // 3. Compute and cache preferences
        let preferences = relayListEvent != nil 
            ? parseRelayList(from: relayListEvent!)
            : RelayPreferences.default
            
        await outboxCache.setRelayPreferences(for: pubkey, preferences: preferences)
        
        return preferences.writeRelays
    }
}
```

#### 3.3 Relay List Monitoring
```swift
actor RelayListMonitor {
    private let ndk: NDK
    private let outboxCache: OutboxCache
    
    func start() async {
        // Monitor all relay list updates
        let relayListSource = NDKDataSource(
            ndk: ndk,
            filter: NDKFilter(kinds: [10002]),
            maxAge: 0  // Live updates
        )
        
        for await event in relayListSource.events {
            // Invalidate cache for this author
            await outboxCache.invalidate(pubkey: event.pubkey)
        }
    }
}
```

#### 3.4 Update DataRequirementManager
- Integrate OutboxCache for relay routing decisions
- Use cached preferences in subscription planning
- Implement fallback strategies for missing relay lists

## Debug & Error Handling Enhancements

### NDKDebugManager
```swift
public actor NDKDebugManager {
    func explainExecution<T>(for dataSource: NDKDataSource<T>) async -> String {
        // Return human-readable execution plan
        """
        Requirement for kinds:[1], authors:[alice, bob]
        - Grouped with 3 other requirements
        - Resolved to target relay.alice.com for Alice
        - Resolved to target relay.bob.com for Bob  
        - Created new subscription sub-xyz on relay.alice.com
        - Reused existing subscription sub-abc on relay.bob.com
        """
    }
}
```

### NDKState Observable
```swift
@MainActor
public final class NDKState: ObservableObject {
    @Published public private(set) var connectedRelays: Int = 0
    @Published public private(set) var totalRelays: Int = 0
    @Published public private(set) var activeSubscriptions: Int = 0
    @Published public private(set) var pendingRequirements: Int = 0
    @Published public private(set) var cacheHitRate: Double = 0.0
}
```

### Enhanced Error Handling
```swift
// Update NDKDataSource
@Published public private(set) var errors: [Error] = []

// Add specific error types
public enum DataSourceError: Error {
    case requirementFailed(reasons: [Error])
    case noViableRelaysFound  
    case cachePolicyPreventedNetworkRequest
    case profileParsingFailed(Error)
    case relayListInvalid(Error)
}
```

## Phase 4: System Integration (Week 4)

### Goal
Remove all legacy code and ensure only declarative API remains.

### Tasks
1. Delete old subscription methods from NDK
2. Remove callback-based APIs entirely
3. Update all internal components to use DataSource
4. Ensure no references to old patterns remain

## Phase 5: Testing & Validation (Week 5)

### Test Suites

#### Cache Correctness Tests
```swift
func testProfileCacheHitRate() async {
    // Setup
    let cache = ProfileCache()
    let pubkey = "test-pubkey"
    let profile = NDKUserProfile(name: "Test User")
    
    // Prime cache
    await cache.setProfile(for: pubkey, profile: profile)
    
    // Test hit with fresh maxAge
    let hit1 = await cache.getProfile(for: pubkey, maxAge: 3600)
    XCTAssertNotNil(hit1)
    
    // Test miss with expired maxAge
    let hit2 = await cache.getProfile(for: pubkey, maxAge: 0)
    XCTAssertNil(hit2)
}
```

#### Performance Benchmarks
```swift
func testSubscriptionGroupingEfficiency() async {
    // Create 50 profile requests
    let requests = (0..<50).map { i in
        NDKDataSource(filter: NDKFilter(kinds: [0], authors: ["pubkey\(i)"]))
    }
    
    // Wait for grouping
    try await Task.sleep(nanoseconds: 150_000_000)
    
    // Verify grouping happened
    let activeSubscriptions = await ndk.state.activeSubscriptions
    XCTAssertLessThan(activeSubscriptions, 5)  // Should be grouped
}
```

## Phase 6: Documentation & Polish (Week 6)

### Documentation Updates
1. Architecture diagrams with cache layers
2. Data flow examples
3. Performance tuning guide
4. SwiftUI preview examples

### SwiftUI Preview Support
```swift
extension NDKDataSource {
    static func preview<T>(data: [T]) -> NDKDataSource<T> {
        // Return mock data source for SwiftUI previews
        let source = NDKDataSource<T>(...)
        source.data = data
        return source
    }
}
```

## Risk Mitigation

### Performance Monitoring
- Continuous benchmarking during development
- Profile with Instruments regularly
- Set up performance regression tests

### Memory Management
- Implement LRU eviction for all caches
- Monitor memory usage in long-running tests
- Add memory pressure handling

### Debugging Support
- Comprehensive logging at key points
- Export debug reports for issue investigation
- Clear error messages with actionable hints

## Success Criteria

### Technical Metrics
- ✅ 70% reduction in redundant relay requests
- ✅ <50ms event-to-UI latency  
- ✅ Zero memory leaks in 24-hour test
- ✅ 80%+ cache hit rate for profiles
- ✅ <100MB memory footprint for 10k events

### Developer Experience
- ✅ 1-line data source declaration
- ✅ No manual lifecycle management
- ✅ Clear, actionable error messages
- ✅ Intuitive debugging tools
- ✅ Excellent SwiftUI integration

## Timeline Summary

- **Week 1**: Cache Foundation (observability, relay tracking, invalidation)
- **Week 2**: Profile Cache (semantic caching, LRU, integration)
- **Week 3**: Outbox Cache (relay routing, monitoring, optimization)
- **Week 4**: System Integration (remove legacy, unify APIs)
- **Week 5**: Testing & Validation (correctness, performance, memory)
- **Week 6**: Documentation & Polish (guides, examples, release prep)

## Next Steps

1. Begin Phase 1 implementation immediately
2. Set up performance benchmarking infrastructure
3. Create test harness for cache behavior
4. Start documenting as we build