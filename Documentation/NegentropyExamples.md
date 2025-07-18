# Negentropy Integration Examples

This document provides practical examples for integrating Negentropy into your Nostr applications using NDKSwift.

## Table of Contents

1. [Basic Client Sync](#basic-client-sync)
2. [Mobile App Integration](#mobile-app-integration)
3. [Background Sync](#background-sync)
4. [Multi-Relay Sync](#multi-relay-sync)
5. [Error Handling Patterns](#error-handling-patterns)
6. [Performance Optimization](#performance-optimization)
7. [Custom Storage Implementation](#custom-storage-implementation)

## Basic Client Sync

### Simple Profile and Posts Sync

```swift
import NDKSwift

class BasicSyncExample {
    private let ndk: NDK
    private let cache: NDKSQLiteCache
    
    init() {
        self.cache = NDKSQLiteCache(path: "user_data.db")
        self.ndk = NDK()
        self.ndk.cache = cache
    }
    
    func syncUserData(pubkey: String) async throws {
        // Add relay that supports NIP-77
        try await ndk.addRelay("wss://relay.damus.io")
        
        // Sync user's profile and metadata
        let profileFilter = NDKFilter(
            authors: [pubkey],
            kinds: [0, 3] // metadata and follows
        )
        
        print("Syncing profile data...")
        let profileResult = try await ndk.syncEvents(filter: profileFilter)
        print("Profile sync: +\(profileResult.receivedEvents.count) events")
        
        // Sync recent posts
        let postsFilter = NDKFilter(
            authors: [pubkey],
            kinds: [1], // text notes
            since: Timestamp(Date().timeIntervalSince1970 - 86400 * 7) // last week
        )
        
        print("Syncing posts...")
        let postsResult = try await ndk.syncEvents(filter: postsFilter)
        print("Posts sync: +\(postsResult.receivedEvents.count) events")
        
        // Sync interactions (reactions, reposts)
        let interactionsFilter = NDKFilter(
            authors: [pubkey],
            kinds: [6, 7], // reposts and reactions
            since: Timestamp(Date().timeIntervalSince1970 - 86400 * 3) // last 3 days
        )
        
        print("Syncing interactions...")
        let interactionsResult = try await ndk.syncEvents(filter: interactionsFilter)
        print("Interactions sync: +\(interactionsResult.receivedEvents.count) events")
        
        print("Total events synced: \(profileResult.receivedEvents.count + postsResult.receivedEvents.count + interactionsResult.receivedEvents.count)")
    }
}

// Usage
let syncExample = BasicSyncExample()
try await syncExample.syncUserData(pubkey: "your_pubkey_here")
```

### Timeline Sync with Follows

```swift
class TimelineSyncExample {
    private let ndk: NDK
    
    func syncTimeline(userPubkey: String) async throws {
        // First, get the user's follow list
        let followsFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [3] // follow lists
        )
        
        let followEvents = try await ndk.fetchEvents(followsFilter)
        let followedPubkeys = extractFollowedPubkeys(from: followEvents)
        
        // Sync recent posts from followed users
        let timelineFilter = NDKFilter(
            authors: Array(followedPubkeys.prefix(500)), // Limit to 500 follows
            kinds: [1], // text notes
            since: Timestamp(Date().timeIntervalSince1970 - 86400) // last 24 hours
        )
        
        let result = try await ndk.syncEvents(filter: timelineFilter)
        print("Timeline sync: +\(result.receivedEvents.count) events from \(followedPubkeys.count) followed users")
    }
    
    private func extractFollowedPubkeys(from events: [NDKEvent]) -> Set<String> {
        var pubkeys = Set<String>()
        
        for event in events {
            for tag in event.tags {
                if tag.count >= 2 && tag[0] == "p" {
                    pubkeys.insert(tag[1])
                }
            }
        }
        
        return pubkeys
    }
}
```

## Mobile App Integration

### iOS App with Network-Aware Sync

```swift
import Network
import NDKSwift

class MobileNegentropyManager: ObservableObject {
    @Published var syncProgress: SyncProgress = .idle
    @Published var networkStatus: NetworkStatus = .unknown
    
    private let ndk: NDK
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        self.ndk = NDK()
        self.ndk.cache = NDKSQLiteCache(path: "mobile_cache.db")
        setupNetworkMonitoring()
    }
    
    func startSync(for pubkey: String) async {
        await MainActor.run {
            syncProgress = .syncing(stage: "Initializing...", progress: 0.0)
        }
        
        do {
            // Adaptive sync strategy based on network
            switch networkStatus {
            case .cellular:
                try await performCellularSync(pubkey: pubkey)
            case .wifi:
                try await performWiFiSync(pubkey: pubkey)
            case .unknown:
                try await performConservativeSync(pubkey: pubkey)
            }
            
            await MainActor.run {
                syncProgress = .completed(eventsReceived: 0) // Update with actual count
            }
        } catch {
            await MainActor.run {
                syncProgress = .failed(error)
            }
        }
    }
    
    private func performCellularSync(pubkey: String) async throws {
        // Conservative settings for cellular
        let frameSize = 30_000 // 30KB chunks
        let timeWindow = 86400 * 3 // 3 days max
        
        await MainActor.run {
            syncProgress = .syncing(stage: "Cellular sync - Profile", progress: 0.1)
        }
        
        // Profile data first (essential)
        let profileFilter = NDKFilter(authors: [pubkey], kinds: [0, 3])
        _ = try await syncWithSettings(filter: profileFilter, frameSize: frameSize)
        
        await MainActor.run {
            syncProgress = .syncing(stage: "Cellular sync - Recent posts", progress: 0.5)
        }
        
        // Recent posts only
        let recentFilter = NDKFilter(
            authors: [pubkey],
            kinds: [1],
            since: Timestamp(Date().timeIntervalSince1970 - Double(timeWindow))
        )
        _ = try await syncWithSettings(filter: recentFilter, frameSize: frameSize)
        
        await MainActor.run {
            syncProgress = .syncing(stage: "Cellular sync - Complete", progress: 1.0)
        }
    }
    
    private func performWiFiSync(pubkey: String) async throws {
        // Aggressive settings for WiFi
        let frameSize = 100_000 // 100KB chunks
        
        let syncTasks = [
            ("Profile & Metadata", NDKFilter(authors: [pubkey], kinds: [0, 3]), 0.2),
            ("Text Notes", NDKFilter(authors: [pubkey], kinds: [1]), 0.6),
            ("Interactions", NDKFilter(authors: [pubkey], kinds: [6, 7, 9]), 0.9),
            ("Lists & DMs", NDKFilter(authors: [pubkey], kinds: [30000, 30001, 4]), 1.0)
        ]
        
        for (stage, filter, progress) in syncTasks {
            await MainActor.run {
                syncProgress = .syncing(stage: "WiFi sync - \(stage)", progress: progress)
            }
            
            _ = try await syncWithSettings(filter: filter, frameSize: frameSize)
        }
    }
    
    private func performConservativeSync(pubkey: String) async throws {
        // Very conservative for unknown networks
        let frameSize = 20_000 // 20KB chunks
        
        await MainActor.run {
            syncProgress = .syncing(stage: "Conservative sync - Essentials", progress: 0.5)
        }
        
        // Only essential data
        let essentialFilter = NDKFilter(
            authors: [pubkey],
            kinds: [0, 3], // Just profile and follows
            limit: 10 // Very limited
        )
        
        _ = try await syncWithSettings(filter: essentialFilter, frameSize: frameSize)
        
        await MainActor.run {
            syncProgress = .syncing(stage: "Conservative sync - Complete", progress: 1.0)
        }
    }
    
    private func syncWithSettings(filter: NDKFilter, frameSize: Int) async throws -> SyncResult {
        let storage = NDKCacheNegentropyStorage(cache: ndk.cache!)
        let reconciler = NegentropyReconciler(storage: storage, frameSizeLimit: frameSize)
        
        // Custom sync with timeout
        return try await withTimeout(30.0) {
            try await ndk.syncEvents(filter: filter)
        }
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                if path.isExpensive {
                    self?.networkStatus = .cellular
                } else if path.status == .satisfied {
                    self?.networkStatus = .wifi
                } else {
                    self?.networkStatus = .unknown
                }
            }
        }
        monitor.start(queue: queue)
    }
}

enum SyncProgress {
    case idle
    case syncing(stage: String, progress: Double)
    case completed(eventsReceived: Int)
    case failed(Error)
}

enum NetworkStatus {
    case cellular, wifi, unknown
}

// Usage in SwiftUI
struct ContentView: View {
    @StateObject private var syncManager = MobileNegentropyManager()
    
    var body: some View {
        VStack {
            switch syncManager.syncProgress {
            case .idle:
                Button("Start Sync") {
                    Task {
                        await syncManager.startSync(for: "your_pubkey")
                    }
                }
            case .syncing(let stage, let progress):
                VStack {
                    ProgressView(value: progress)
                    Text(stage)
                }
            case .completed(let count):
                Text("Sync completed: \(count) events")
            case .failed(let error):
                Text("Sync failed: \(error.localizedDescription)")
            }
        }
    }
}
```

## Background Sync

### Scheduled Background Sync

```swift
import BackgroundTasks

class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    private let ndk = NDK()
    
    private init() {
        ndk.cache = NDKSQLiteCache(path: "background_cache.db")
    }
    
    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: "com.yourapp.negentropy-sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        try? BGTaskScheduler.shared.submit(request)
    }
    
    func handleBackgroundSync(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                let success = try await performQuickSync()
                task.setTaskCompleted(success: success)
            } catch {
                task.setTaskCompleted(success: false)
            }
            
            // Schedule next sync
            scheduleBackgroundSync()
        }
    }
    
    private func performQuickSync() async throws -> Bool {
        // Get current user
        guard let currentUser = getCurrentUser() else { return false }
        
        // Quick sync of essential data only
        let essentialFilter = NDKFilter(
            authors: [currentUser.pubkey],
            kinds: [1, 6, 7], // notes, reposts, reactions
            since: Timestamp(Date().timeIntervalSince1970 - 3600) // last hour
        )
        
        // Use very small frame size for background
        let storage = NDKCacheNegentropyStorage(cache: ndk.cache!)
        let reconciler = NegentropyReconciler(storage: storage, frameSizeLimit: 10_000)
        
        let result = try await ndk.syncEvents(filter: essentialFilter)
        
        // Store sync metrics
        UserDefaults.standard.set(result.receivedEvents.count, forKey: "lastBackgroundSyncCount")
        UserDefaults.standard.set(Date(), forKey: "lastBackgroundSyncDate")
        
        return true
    }
    
    private func getCurrentUser() -> (pubkey: String)? {
        // Return current user info from your app state
        return nil
    }
}

// In your AppDelegate or App struct:
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.yourapp.negentropy-sync", using: nil) { task in
        BackgroundSyncManager.shared.handleBackgroundSync(task: task as! BGAppRefreshTask)
    }
    return true
}
```

## Multi-Relay Sync

### Parallel Sync Across Multiple Relays

```swift
class MultiRelaySyncManager {
    private let ndk: NDK
    private let relayUrls = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.snort.social",
        "wss://relay.primal.net"
    ]
    
    init() {
        self.ndk = NDK()
        self.ndk.cache = NDKSQLiteCache(path: "multi_relay_cache.db")
    }
    
    func syncAcrossRelays(filter: NDKFilter) async throws -> MultiRelaySyncResult {
        // Add all relays
        for url in relayUrls {
            try await ndk.addRelay(url)
        }
        
        // Perform parallel sync across relays
        let results = try await withThrowingTaskGroup(of: RelaySyncResult.self) { group in
            var results: [RelaySyncResult] = []
            
            for relay in ndk.relayPool.relays {
                group.addTask {
                    try await self.syncWithRelay(relay: relay, filter: filter)
                }
            }
            
            for try await result in group {
                results.append(result)
            }
            
            return results
        }
        
        return MultiRelaySyncResult(relayResults: results)
    }
    
    private func syncWithRelay(relay: NDKRelay, filter: NDKFilter) async throws -> RelaySyncResult {
        let startTime = Date()
        
        do {
            // Check if relay supports NIP-77
            guard await relay.supportsNegentropy() else {
                return RelaySyncResult(
                    relayUrl: relay.url,
                    success: false,
                    eventsReceived: 0,
                    duration: 0,
                    error: "Relay doesn't support NIP-77"
                )
            }
            
            // Perform Negentropy sync
            let result = try await ndk.syncEvents(filter: filter, relay: relay)
            
            return RelaySyncResult(
                relayUrl: relay.url,
                success: true,
                eventsReceived: result.receivedEvents.count,
                duration: Date().timeIntervalSince(startTime),
                error: nil
            )
            
        } catch {
            return RelaySyncResult(
                relayUrl: relay.url,
                success: false,
                eventsReceived: 0,
                duration: Date().timeIntervalSince(startTime),
                error: error.localizedDescription
            )
        }
    }
}

struct RelaySyncResult {
    let relayUrl: String
    let success: Bool
    let eventsReceived: Int
    let duration: TimeInterval
    let error: String?
}

struct MultiRelaySyncResult {
    let relayResults: [RelaySyncResult]
    
    var totalEventsReceived: Int {
        relayResults.reduce(0) { $0 + $1.eventsReceived }
    }
    
    var successfulRelays: [RelaySyncResult] {
        relayResults.filter { $0.success }
    }
    
    var failedRelays: [RelaySyncResult] {
        relayResults.filter { !$0.success }
    }
    
    var averageDuration: TimeInterval {
        let totalDuration = relayResults.reduce(0) { $0 + $1.duration }
        return totalDuration / Double(relayResults.count)
    }
}
```

## Error Handling Patterns

### Robust Error Handling with Fallbacks

```swift
class RobustSyncManager {
    private let ndk: NDK
    
    func robustSync(filter: NDKFilter, maxRetries: Int = 3) async throws -> [NDKEvent] {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                return try await attemptSync(filter: filter, attempt: attempt)
            } catch let error as NIP77Error {
                lastError = error
                
                switch error {
                case .unsupportedByRelay:
                    // Try traditional sync immediately
                    return try await fallbackToTraditionalSync(filter: filter)
                    
                case .timeout:
                    if attempt < maxRetries {
                        // Wait before retry with exponential backoff
                        let delay = TimeInterval(pow(2.0, Double(attempt)))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    
                case .invalidMessage, .syncFailed, .relayError:
                    // These might be transient, retry
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        continue
                    }
                }
            } catch let error as NegentropyError {
                lastError = error
                
                switch error {
                case .protocolError:
                    // Protocol errors are usually not recoverable
                    throw error
                    
                case .decodingError, .encodingError:
                    // These might be transient
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        continue
                    }
                    
                case .invalidItemId, .invalidBounds, .frameSizeExceeded:
                    // These indicate implementation issues
                    throw error
                }
            } catch {
                lastError = error
                
                // Network or other errors - retry with backoff
                if attempt < maxRetries {
                    let delay = TimeInterval(pow(2.0, Double(attempt)))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
            }
        }
        
        // All retries failed, try fallback
        do {
            return try await fallbackToTraditionalSync(filter: filter)
        } catch {
            // Both Negentropy and traditional failed
            throw SyncError.allMethodsFailed(
                negentropyError: lastError,
                traditionalError: error
            )
        }
    }
    
    private func attemptSync(filter: NDKFilter, attempt: Int) async throws -> [NDKEvent] {
        // Adjust strategy based on attempt
        let frameSize = attempt == 1 ? 60_000 : 30_000 // Smaller frames on retry
        let timeout: TimeInterval = Double(attempt * 30) // Longer timeout on retry
        
        let storage = NDKCacheNegentropyStorage(cache: ndk.cache!)
        let reconciler = NegentropyReconciler(storage: storage, frameSizeLimit: frameSize)
        
        return try await withTimeout(timeout) {
            let result = try await ndk.syncEvents(filter: filter)
            return result.receivedEvents
        }
    }
    
    private func fallbackToTraditionalSync(filter: NDKFilter) async throws -> [NDKEvent] {
        print("Falling back to traditional sync...")
        return try await ndk.fetchEvents(filter)
    }
}

enum SyncError: LocalizedError {
    case allMethodsFailed(negentropyError: Error?, traditionalError: Error)
    
    var errorDescription: String? {
        switch self {
        case .allMethodsFailed(let negError, let tradError):
            return "Both Negentropy (\(negError?.localizedDescription ?? "unknown")) and traditional (\(tradError.localizedDescription)) sync failed"
        }
    }
}

// Utility for timeout
func withTimeout<T>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw SyncError.timeout
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

extension SyncError {
    static let timeout = NSError(domain: "SyncError", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
}
```

## Performance Optimization

### Batch Processing and Caching Strategies

```swift
class OptimizedSyncManager {
    private let ndk: NDK
    private let batchSize = 100
    private let cache: NDKSQLiteCache
    
    init() {
        self.cache = NDKSQLiteCache(path: "optimized_cache.db")
        self.ndk = NDK()
        self.ndk.cache = cache
        
        // Optimize cache for Negentropy queries
        Task {
            try await optimizeCache()
        }
    }
    
    private func optimizeCache() async throws {
        // Create indexes for efficient timestamp-based queries
        try await cache.createIndex(
            name: "idx_events_timestamp_id",
            table: "events",
            columns: ["created_at", "id"]
        )
        
        try await cache.createIndex(
            name: "idx_events_author_kind_timestamp",
            table: "events", 
            columns: ["pubkey", "kind", "created_at"]
        )
    }
    
    func efficientSync(filters: [NDKFilter]) async throws -> BatchSyncResult {
        var totalEvents = 0
        var totalDuration: TimeInterval = 0
        let startTime = Date()
        
        // Process filters in batches to avoid overwhelming the system
        for batch in filters.chunked(into: 3) {
            let batchStart = Date()
            
            // Parallel sync within batch
            let batchResults = try await withThrowingTaskGroup(of: [NDKEvent].self) { group in
                var results: [NDKEvent] = []
                
                for filter in batch {
                    group.addTask {
                        try await self.syncSingleFilter(filter)
                    }
                }
                
                for try await events in group {
                    results.append(contentsOf: events)
                }
                
                return results
            }
            
            // Process results in smaller chunks to avoid UI blocking
            try await processEventsInBatches(batchResults)
            
            totalEvents += batchResults.count
            totalDuration += Date().timeIntervalSince(batchStart)
            
            // Brief pause between batches to allow UI updates
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        return BatchSyncResult(
            totalEvents: totalEvents,
            totalDuration: Date().timeIntervalSince(startTime),
            averageEventsPerSecond: Double(totalEvents) / totalDuration
        )
    }
    
    private func syncSingleFilter(_ filter: NDKFilter) async throws -> [NDKEvent] {
        // Use optimized storage with pre-warmed cache
        let storage = OptimizedNegentropyStorage(cache: cache)
        let reconciler = NegentropyReconciler(
            storage: storage,
            frameSizeLimit: 80_000 // Optimized frame size
        )
        
        let result = try await ndk.syncEvents(filter: filter)
        return result.receivedEvents
    }
    
    private func processEventsInBatches(_ events: [NDKEvent]) async throws {
        for batch in events.chunked(into: batchSize) {
            // Process batch atomically
            try await cache.transaction {
                for event in batch {
                    try await processEvent(event)
                }
            }
            
            // Yield to other tasks
            await Task.yield()
        }
    }
    
    private func processEvent(_ event: NDKEvent) async throws {
        // Custom event processing logic
        // e.g., extract mentions, update counters, etc.
    }
}

// Optimized storage implementation
class OptimizedNegentropyStorage: NegentropyStorage {
    private let cache: NDKSQLiteCache
    private var cachedItems: [NegentropyItem]?
    
    init(cache: NDKSQLiteCache) {
        self.cache = cache
    }
    
    func getItems(in range: NegentropyRange) async throws -> [NegentropyItem] {
        // Use cached items if available and valid
        if let cached = cachedItems, range.isFullRange {
            return cached
        }
        
        // Optimized database query
        let items = try await cache.getNegentropyItems(in: range)
        
        // Cache full ranges for reuse
        if range.isFullRange {
            cachedItems = items
        }
        
        return items
    }
    
    // Implement other required methods...
}

struct BatchSyncResult {
    let totalEvents: Int
    let totalDuration: TimeInterval
    let averageEventsPerSecond: Double
    
    var efficiency: String {
        return String(format: "%.1f events/sec", averageEventsPerSecond)
    }
}

// Utility extensions
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension NegentropyRange {
    var isFullRange: Bool {
        return lower == nil && upper == nil
    }
}
```

## Custom Storage Implementation

### File-Based Storage for Specific Use Cases

```swift
import Foundation

class FileBasedNegentropyStorage: NegentropyStorage {
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(directoryPath: String) throws {
        self.storageURL = URL(fileURLWithPath: directoryPath)
        
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
    }
    
    func getItems(in range: NegentropyRange) async throws -> [NegentropyItem] {
        let itemsFile = storageURL.appendingPathComponent("items.json")
        
        guard FileManager.default.fileExists(atPath: itemsFile.path) else {
            return []
        }
        
        let data = try Data(contentsOf: itemsFile)
        let allItems = try decoder.decode([StoredItem].self, from: data)
        
        // Filter items by range
        let filteredItems = allItems.compactMap { stored -> NegentropyItem? in
            let item = NegentropyItem(
                id: Data(hex: stored.id)!,
                timestamp: stored.timestamp
            )
            
            return range.contains(item) ? item : nil
        }
        
        return filteredItems.sorted()
    }
    
    func saveItem(_ item: NegentropyItem) async throws {
        let itemsFile = storageURL.appendingPathComponent("items.json")
        
        var existingItems: [StoredItem] = []
        
        if FileManager.default.fileExists(atPath: itemsFile.path) {
            let data = try Data(contentsOf: itemsFile)
            existingItems = try decoder.decode([StoredItem].self, from: data)
        }
        
        let newItem = StoredItem(
            id: item.id.hexString,
            timestamp: item.timestamp
        )
        
        // Add if not exists
        if !existingItems.contains(where: { $0.id == newItem.id }) {
            existingItems.append(newItem)
            existingItems.sort { $0.timestamp < $1.timestamp }
            
            let data = try encoder.encode(existingItems)
            try data.write(to: itemsFile)
        }
    }
    
    func removeItem(id: Data) async throws {
        let itemsFile = storageURL.appendingPathComponent("items.json")
        
        guard FileManager.default.fileExists(atPath: itemsFile.path) else {
            return
        }
        
        let data = try Data(contentsOf: itemsFile)
        var items = try decoder.decode([StoredItem].self, from: data)
        
        let hexId = id.hexString
        items.removeAll { $0.id == hexId }
        
        let updatedData = try encoder.encode(items)
        try updatedData.write(to: itemsFile)
    }
}

private struct StoredItem: Codable {
    let id: String
    let timestamp: UInt64
}

// Usage example
class CustomStorageExample {
    private let storage: FileBasedNegentropyStorage
    
    init() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storagePath = documentsPath.appendingPathComponent("negentropy_storage").path
        
        self.storage = try FileBasedNegentropyStorage(directoryPath: storagePath)
    }
    
    func performCustomSync(filter: NDKFilter) async throws {
        let reconciler = NegentropyReconciler(
            storage: storage,
            frameSizeLimit: 50_000
        )
        
        // Custom sync logic using file-based storage
        let initMessage = try await reconciler.initiate()
        // ... rest of sync logic
    }
}
```

These examples demonstrate various real-world integration patterns for Negentropy in NDKSwift applications. Each example focuses on specific use cases and provides practical, production-ready code that you can adapt for your specific needs.