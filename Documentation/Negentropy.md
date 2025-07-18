# Negentropy Set Reconciliation in NDKSwift

## Overview

Negentropy is a set reconciliation protocol that efficiently synchronizes data sets between two parties by identifying and exchanging only the differences. NDKSwift implements Negentropy for efficient Nostr event synchronization, following [NIP-77](https://github.com/nostr-protocol/nips/blob/master/77.md).

## When to Use Negentropy

### ✅ **Ideal Use Cases:**

1. **Client-Relay Synchronization**
   - Sync your local cache with relay data
   - Resume interrupted syncs efficiently
   - Catch up on missed events during offline periods

2. **Large Event Sets**
   - When you need to sync thousands of events
   - Better than traditional REQ/EOSE for bulk operations
   - Reduces bandwidth and improves sync speed

3. **Bandwidth-Constrained Environments**
   - Mobile networks with data limits
   - Satellite connections
   - Any scenario where efficiency matters

4. **Resumable Syncs**
   - Handle network interruptions gracefully
   - Continue sync from where it left off
   - No need to re-download already synced events

### ❌ **When NOT to Use Negentropy:**

1. **Small Event Sets** (< 100 events)
   - Traditional REQ queries are simpler and faster
   - Negentropy overhead not worth it for small sets

2. **Real-time Subscriptions**
   - Use regular NDKSubscription for live updates
   - Negentropy is for bulk synchronization, not streaming

3. **One-off Queries**
   - When you only need specific events once
   - Use `ndk.fetchEvents()` for simple queries

4. **Relay Doesn't Support NIP-77**
   - Check relay capabilities first
   - Fall back to traditional sync methods

## Basic Usage

### 1. Simple Sync with Relay

```swift
import NDKSwift

// Setup NDK with cache
let ndk = NDK()
let cache = MemoryCache() // or NDKSQLiteCache for persistence
ndk.cache = cache

// Add relay that supports NIP-77
try await ndk.addRelay("wss://relay.example.com")

// Define what you want to sync
let filter = NDKFilter(
    authors: ["your_pubkey_here"],
    kinds: [1, 6, 7], // text notes, reposts, reactions
    since: Timestamp(Date().timeIntervalSince1970 - 86400) // last 24 hours
)

// Perform Negentropy sync
do {
    let syncResult = try await ndk.syncEvents(filter: filter)
    print("Sync completed:")
    print("- Received \(syncResult.receivedEvents.count) new events")
    print("- Sent \(syncResult.sentEvents.count) events to relay")
    print("- Total round trips: \(syncResult.roundTrips)")
} catch {
    print("Sync failed: \(error)")
    // Fall back to traditional sync if needed
    let events = try await ndk.fetchEvents(filter)
}
```

### 2. Manual Reconciliation

```swift
// Setup storage adapter for your cache
let storage = NDKCacheNegentropyStorage(cache: cache)

// Create reconciler
let reconciler = NegentropyReconciler(
    storage: storage,
    frameSizeLimit: 60_000 // 60KB frames for mobile networks
)

// Initiate reconciliation
let initialMessage = try await reconciler.initiate()

// Send to relay via NIP-77 NEG-OPEN message
let negOpen = NIP77Message.open(
    subscriptionId: "sync-\(UUID().uuidString)",
    filter: filter,
    initialMessage: initialMessage
)

// Continue reconciliation based on relay responses...
```

### 3. Large Dataset Sync with Progress

```swift
class SyncManager {
    private let ndk: NDK
    private let progressCallback: (SyncProgress) -> Void
    
    init(ndk: NDK, progress: @escaping (SyncProgress) -> Void) {
        self.ndk = ndk
        self.progressCallback = progress
    }
    
    func syncUserData(pubkey: String) async throws {
        let filters = [
            // Profile and metadata
            NDKFilter(authors: [pubkey], kinds: [0, 3]),
            
            // Posts and interactions
            NDKFilter(authors: [pubkey], kinds: [1, 6, 7]),
            
            // Lists and follows
            NDKFilter(authors: [pubkey], kinds: [30000, 30001, 10000])
        ]
        
        for (index, filter) in filters.enumerated() {
            progressCallback(SyncProgress(
                stage: "Syncing \(filterDescription(filter))",
                progress: Double(index) / Double(filters.count)
            ))
            
            let result = try await ndk.syncEvents(filter: filter)
            
            progressCallback(SyncProgress(
                stage: "Completed \(filterDescription(filter))",
                progress: Double(index + 1) / Double(filters.count),
                eventsReceived: result.receivedEvents.count
            ))
        }
    }
}

struct SyncProgress {
    let stage: String
    let progress: Double
    let eventsReceived: Int = 0
}
```

## Advanced Usage

### 1. Custom Storage Implementation

```swift
// Implement NegentropyStorage for custom data sources
class CustomNegentropyStorage: NegentropyStorage {
    private let database: YourDatabase
    
    func getItems(in range: NegentropyRange) async throws -> [NegentropyItem] {
        // Query your database for events in the specified range
        let events = try await database.events(
            timestampRange: range.timestampRange,
            idRange: range.idRange
        )
        
        return events.map { event in
            NegentropyItem(
                id: Data(hex: event.id)!,
                timestamp: UInt64(event.createdAt)
            )
        }
    }
    
    // Implement other required methods...
}
```

### 2. Error Handling and Fallbacks

```swift
func robustSync(filter: NDKFilter) async throws -> [NDKEvent] {
    // Try Negentropy first
    if await relay.supportsNIP77() {
        do {
            let result = try await ndk.syncEvents(filter: filter)
            return result.receivedEvents
        } catch NIP77Error.unsupportedByRelay {
            print("Relay doesn't support NIP-77, falling back...")
        } catch NIP77Error.timeout {
            print("Negentropy timeout, falling back...")
        }
    }
    
    // Fall back to traditional sync
    return try await ndk.fetchEvents(filter)
}
```

### 3. Optimized Mobile Sync

```swift
class MobileSyncStrategy {
    private let ndk: NDK
    private let networkMonitor: NetworkMonitor
    
    func syncWithAdaptiveStrategy(filter: NDKFilter) async throws {
        let frameSize = networkMonitor.isOnCellular ? 30_000 : 100_000
        let timeout = networkMonitor.isOnCellular ? 30.0 : 60.0
        
        let reconciler = NegentropyReconciler(
            storage: NDKCacheNegentropyStorage(cache: ndk.cache!),
            frameSizeLimit: frameSize
        )
        
        // Use smaller chunks on cellular
        if networkMonitor.isOnCellular {
            // Split large syncs into smaller time windows
            let timeWindows = splitIntoTimeWindows(filter, windowSize: 86400) // 1 day
            
            for window in timeWindows {
                try await syncWindow(window, reconciler: reconciler, timeout: timeout)
                
                // Pause between chunks to avoid overwhelming cellular connection
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        } else {
            // Full sync on WiFi
            try await performFullSync(filter, reconciler: reconciler, timeout: timeout)
        }
    }
}
```

## Performance Considerations

### 1. Frame Size Limits

```swift
// Conservative for mobile/satellite
let mobileReconciler = NegentropyReconciler(
    storage: storage,
    frameSizeLimit: 30_000 // 30KB
)

// Aggressive for high-bandwidth connections
let desktopReconciler = NegentropyReconciler(
    storage: storage,
    frameSizeLimit: 500_000 // 500KB
)
```

### 2. Cache Optimization

```swift
// Use persistent cache for better performance
let cache = NDKSQLiteCache(path: "negentropy_cache.db")

// Ensure proper indexing for timestamp-based queries
try await cache.createIndexes()

// Pre-populate cache with known events for better efficiency
for event in knownEvents {
    try await cache.saveEvent(event)
}
```

### 3. Batch Operations

```swift
// Process received events in batches
let batchSize = 100
let receivedEvents = syncResult.receivedEvents

for batch in receivedEvents.chunked(into: batchSize) {
    // Process batch atomically
    try await database.transaction {
        for event in batch {
            try await processEvent(event)
        }
    }
    
    // Update UI periodically
    await MainActor.run {
        updateProgress(processed: processedCount, total: receivedEvents.count)
    }
}
```

## NIP-77 Protocol Details

### Message Types

1. **NEG-OPEN** - Start reconciliation
   ```json
   ["NEG-OPEN", "<sub_id>", <filter>, "<negentropy_msg>"]
   ```

2. **NEG-MSG** - Continue reconciliation
   ```json
   ["NEG-MSG", "<sub_id>", "<negentropy_msg>"]
   ```

3. **NEG-CLOSE** - End reconciliation
   ```json
   ["NEG-CLOSE", "<sub_id>"]
   ```

4. **NEG-ERR** - Error occurred
   ```json
   ["NEG-ERR", "<sub_id>", "<error_message>"]
   ```

### Protocol Flow

1. Client sends NEG-OPEN with filter and initial Negentropy message
2. Relay responds with NEG-MSG containing reconciliation data
3. Exchange continues until both sides have identified differences
4. Missing events are sent as regular EVENT messages
5. Reconciliation ends with NEG-CLOSE

## Best Practices

### 1. Always Check Relay Support

```swift
extension NDKRelay {
    func supportsNegentropy() async -> Bool {
        // Check NIP-11 relay information document
        guard let info = try? await fetchRelayInfo() else { return false }
        return info.supportedNIPs?.contains(77) == true
    }
}
```

### 2. Implement Graceful Degradation

```swift
// Always have a fallback strategy
func syncEvents(filter: NDKFilter) async throws -> [NDKEvent] {
    if await relay.supportsNegentropy() {
        return try await syncWithNegentropy(filter)
    } else {
        return try await syncTraditional(filter)
    }
}
```

### 3. Monitor Performance

```swift
struct SyncMetrics {
    let duration: TimeInterval
    let bytesTransferred: Int
    let eventsReceived: Int
    let roundTrips: Int
    let efficiency: Double // events per byte
}

func measureSync() async throws -> SyncMetrics {
    let start = Date()
    let result = try await ndk.syncEvents(filter: filter)
    let duration = Date().timeIntervalSince(start)
    
    return SyncMetrics(
        duration: duration,
        bytesTransferred: result.bytesTransferred,
        eventsReceived: result.receivedEvents.count,
        roundTrips: result.roundTrips,
        efficiency: Double(result.receivedEvents.count) / Double(result.bytesTransferred)
    )
}
```

### 4. Handle Network Interruptions

```swift
class ResumableSync {
    private var syncState: SyncState?
    
    func resumableSync(filter: NDKFilter) async throws {
        defer { syncState = nil }
        
        do {
            syncState = SyncState(filter: filter, startTime: Date())
            let result = try await ndk.syncEvents(filter: filter)
            // Success - clear state
        } catch {
            // Save state for resume
            syncState?.lastError = error
            throw error
        }
    }
    
    func canResume() -> Bool {
        return syncState != nil
    }
}
```

## Troubleshooting

### Common Issues

1. **Relay doesn't support NIP-77**
   - Check relay documentation
   - Use `relay.supportsNegentropy()` check
   - Implement fallback to traditional sync

2. **Sync timeouts**
   - Reduce frame size limits
   - Split large syncs into smaller time windows
   - Check network connectivity

3. **High memory usage**
   - Use persistent cache instead of memory cache
   - Process events in smaller batches
   - Implement proper cleanup

4. **Poor performance**
   - Ensure cache has proper indexes
   - Use appropriate frame sizes for connection
   - Monitor and optimize filter specificity

### Debug Tools

```swift
// Enable detailed logging
NDKLogger.level = .debug

// Monitor Negentropy protocol messages
ndk.onNegentropyMessage = { message in
    print("Negentropy: \(message)")
}

// Track sync progress
ndk.onSyncProgress = { progress in
    print("Sync: \(progress.stage) - \(progress.percentage)%")
}
```

## Migration Guide

### From Traditional Sync

```swift
// Old approach
let events = try await ndk.fetchEvents(NDKFilter(kinds: [1], limit: 1000))

// New approach with Negentropy
let result = try await ndk.syncEvents(filter: NDKFilter(kinds: [1]))
// No limit needed - gets all matching events efficiently
```

### Gradual Adoption

1. Start with small, non-critical syncs
2. Monitor performance and reliability
3. Gradually expand to larger sync operations
4. Keep traditional sync as fallback
5. Eventually make Negentropy the default

## Conclusion

Negentropy provides significant efficiency improvements for Nostr event synchronization, especially for large datasets and bandwidth-constrained environments. By following these guidelines and best practices, you can implement robust, efficient synchronization in your Nostr applications.

For implementation details, see the source code in `Sources/NDKSwift/Negentropy/` and examples in `Sources/NegentropyDemo/`.