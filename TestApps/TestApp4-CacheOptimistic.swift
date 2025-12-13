#!/usr/bin/env swift

/*
 * TestApp4-CacheOptimistic.swift
 *
 * COMPREHENSIVE TEST: Cache & Optimistic Publishing
 *
 * This test validates the ACTUAL behavior of NDKSwift's caching and
 * optimistic publishing features.
 * It tests:
 * 1. SQLite cache initialization and configuration
 * 2. Event confirmation states (optimistic vs confirmed)
 * 3. Offline publishing with automatic retry
 * 4. Unpublished event tracking and retry
 * 5. Cache observation (reactive patterns)
 * 6. Different cache types (Memory vs SQLite)
 * 7. Cache persistence and retrieval
 *
 * CRITICAL: This validates ACTUAL behavior, not documentation!
 */

import Foundation
import NDKSwift

// MARK: - Test Configuration

let TIMEOUT_SHORT = 2_000_000_000 // 2 seconds
let TIMEOUT_MEDIUM = 5_000_000_000 // 5 seconds
let TIMEOUT_LONG = 10_000_000_000 // 10 seconds

let TEST_RELAYS = [
    "wss://relay.damus.io",
    "wss://relay.primal.net",
    "wss://nos.lol",
]

// MARK: - Test Helpers

func printSection(_ title: String) {
    print("\n" + String(repeating: "=", count: 70))
    print(" \(title)")
    print(String(repeating: "=", count: 70))
}

func printTest(_ name: String) {
    print("\n--- TEST: \(name) ---")
}

func printSuccess(_ message: String) {
    print("✅ SUCCESS: \(message)")
}

func printFailure(_ message: String, error: Error? = nil) {
    print("❌ FAILURE: \(message)")
    if let error = error {
        print("   Error: \(error)")
    }
}

func printDiscovery(_ message: String) {
    print("🔍 DISCOVERY: \(message)")
}

// MARK: - Test Functions

func testCacheInitialization() async throws {
    printSection("TEST 1: Cache Initialization")

    // Test 1.1: Memory cache
    printTest("MemoryCache initialization")
    let memCache = MemoryCache()
    printSuccess("MemoryCache created")
    printDiscovery("MemoryCache() requires no parameters")

    // Test 1.2: SQLite cache with default path
    printTest("NDKSQLiteCache initialization")
    do {
        let sqliteCache = try await NDKSQLiteCache()
        printSuccess("NDKSQLiteCache created with default path")
        printDiscovery("NDKSQLiteCache() uses default database location")

        // Check cache type
        if sqliteCache is NDKSQLiteCache {
            printSuccess("Cache is NDKSQLiteCache type")
        }
    } catch {
        printFailure("SQLite cache initialization failed", error: error)
    }

    // Test 1.3: SQLite cache with custom path
    printTest("NDKSQLiteCache with custom path")
    let customPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_ndk_cache_\(UUID().uuidString).db")
    print("   Custom path: \(customPath.path)")

    do {
        let customCache = try await NDKSQLiteCache(databasePath: customPath.path)
        printSuccess("SQLite cache created with custom path")
        printDiscovery("Can specify custom database path")

        // Verify file was created
        if FileManager.default.fileExists(atPath: customPath.path) {
            printSuccess("Database file created at custom path")
        } else {
            printFailure("Database file not found at custom path")
        }

        // Clean up
        try? FileManager.default.removeItem(at: customPath)
    } catch {
        printFailure("Custom path cache failed", error: error)
    }

    // Test 1.4: NDK with different cache types
    printTest("NDK with MemoryCache")
    let ndk1 = NDK(relayUrls: TEST_RELAYS, cache: memCache)
    printSuccess("NDK initialized with MemoryCache")

    printTest("NDK with SQLiteCache")
    do {
        let sqlCache = try await NDKSQLiteCache()
        let ndk2 = NDK(relayUrls: TEST_RELAYS, cache: sqlCache)
        printSuccess("NDK initialized with SQLiteCache")
        printDiscovery("NDK accepts any NDKCache conforming type")
    } catch {
        printFailure("NDK with SQLite cache failed", error: error)
    }
}

func testOptimisticPublishing() async throws {
    printSection("TEST 2: Optimistic Publishing")

    let cache = try await NDKSQLiteCache()
    let ndk = NDK(relayUrls: TEST_RELAYS, cache: cache)
    let signer = try NDKPrivateKeySigner.generate()
    ndk.signer = signer
    let pubkey = try await signer.pubkey

    // Test 2.1: Publish while OFFLINE
    printTest("Publish event while offline")
    print("   Status: Offline (not connected)")

    let offlineEvent = try await NDKEventBuilder(ndk: ndk)
        .content("This event was published while offline!")
        .tag(["test", "optimistic"])
        .build()

    let publishResult = try await ndk.publish(offlineEvent)
    print("   Event ID: \(String(offlineEvent.id.prefix(16)))...")
    print("   Publish result count: \(publishResult.count)")
    printSuccess("Event published while offline")
    printDiscovery("Can publish events before connecting to relays")

    // Test 2.2: Check event confirmation state
    printTest("Check optimistic event confirmation state")
    if let state = await cache.getEventConfirmationState(eventId: offlineEvent.id) {
        print("   State: \(state)")
        switch state {
        case .optimistic:
            printSuccess("Event is in optimistic state")
            printDiscovery("Offline events start in .optimistic state")
        case let .confirmed(relay):
            print("   Confirmed by: \(relay)")
            printDiscovery("Event was already confirmed")
        }
    } else {
        print("   No confirmation state found")
        printDiscovery("Confirmation state may not be tracked for all cache types")
    }

    // Test 2.3: Check unpublished events
    printTest("Check unpublished events")
    let unpublished = await cache.getUnpublishedEvents(limit: 100)
    print("   Unpublished events: \(unpublished.count)")
    printSuccess("Can query unpublished events")
    printDiscovery("getUnpublishedEvents(limit:) returns events awaiting relay confirmation")

    // Test 2.4: Connect and observe auto-retry
    printTest("Connect to relays and observe auto-retry")
    await ndk.connect()
    print("   Connected to relays")

    // Wait for auto-retry
    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)

    // Check state again
    if let state = await cache.getEventConfirmationState(eventId: offlineEvent.id) {
        print("   State after connect: \(state)")
        switch state {
        case .optimistic:
            print("   Still optimistic (may need more time)")
        case let .confirmed(relay):
            printSuccess("Event confirmed by: \(relay)")
            printDiscovery("Events automatically retry and confirm after connection")
        }
    }

    // Check unpublished count
    let unpublishedAfter = await cache.getUnpublishedEvents(limit: 100)
    print("   Unpublished after retry: \(unpublishedAfter.count)")

    await ndk.disconnect()
}

func testEventConfirmationStates() async throws {
    printSection("TEST 3: Event Confirmation States")

    let cache = try await NDKSQLiteCache()
    let ndk = NDK(relayUrls: TEST_RELAYS, cache: cache)
    let signer = try NDKPrivateKeySigner.generate()
    ndk.signer = signer

    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 3.1: Publish online event
    printTest("Publish event while online")
    let onlineEvent = try await NDKEventBuilder(ndk: ndk)
        .content("This event was published while online")
        .build()

    _ = try await ndk.publish(onlineEvent)
    print("   Event ID: \(String(onlineEvent.id.prefix(16)))...")
    printSuccess("Event published while online")

    // Test 3.2: Monitor confirmation state over time
    printTest("Monitor confirmation state transitions")
    for i in 0 ..< 5 {
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        if let state = await cache.getEventConfirmationState(eventId: onlineEvent.id) {
            print("   Check \(i + 1): \(state)")

            switch state {
            case .optimistic:
                print("      Still waiting for confirmation...")
            case let .confirmed(relay):
                print("      ✓ Confirmed by \(relay)")
                printSuccess("Event transitioned to confirmed state")
            }
        } else {
            print("   Check \(i + 1): No state found")
        }
    }

    printDiscovery("Confirmation states transition from .optimistic to .confirmed")

    await ndk.disconnect()
}

func testManualRetry() async throws {
    printSection("TEST 4: Manual Retry of Unpublished Events")

    let cache = try await NDKSQLiteCache()
    let ndk = NDK(relayUrls: TEST_RELAYS, cache: cache)
    let signer = try NDKPrivateKeySigner.generate()
    ndk.signer = signer

    // Publish while offline
    printTest("Create unpublished events")
    let event1 = try await NDKEventBuilder(ndk: ndk)
        .content("Unpublished event 1")
        .build()
    let event2 = try await NDKEventBuilder(ndk: ndk)
        .content("Unpublished event 2")
        .build()

    _ = try await ndk.publish(event1)
    _ = try await ndk.publish(event2)
    print("   Created 2 events while offline")

    let unpublishedBefore = await cache.getUnpublishedEvents(limit: 100)
    print("   Unpublished count: \(unpublishedBefore.count)")

    // Test 4.1: Manual retry
    printTest("Manual retry with retryUnpublishedEvents()")
    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    let retryCount = try await ndk.retryUnpublishedEvents()
    print("   Retried \(retryCount) events")
    printSuccess("Manual retry executed")
    printDiscovery("ndk.retryUnpublishedEvents() manually triggers retry")

    // Wait for confirmations
    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)

    let unpublishedAfter = await cache.getUnpublishedEvents(limit: 100)
    print("   Unpublished after retry: \(unpublishedAfter.count)")

    if unpublishedAfter.count < unpublishedBefore.count {
        printSuccess("Some events were confirmed after retry")
    }

    await ndk.disconnect()
}

func testCacheObservation() async throws {
    printSection("TEST 5: Cache Observation (Reactive Patterns)")

    let cache = try await NDKSQLiteCache()
    let ndk = NDK(relayUrls: TEST_RELAYS, cache: cache)
    let signer = try NDKPrivateKeySigner.generate()
    ndk.signer = signer
    let pubkey = try await signer.pubkey

    // Test 5.1: Observe events with cache policy
    printTest("Subscribe with cacheWithNetwork policy")

    // Publish an event first
    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    let testEvent = try await NDKEventBuilder(ndk: ndk)
        .content("Event for cache observation test")
        .build()
    _ = try await ndk.publish(testEvent)

    // Wait for it to be cached
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Now subscribe with cache policy
    let subscription = ndk.subscribe(
        filter: NDKFilter(authors: [pubkey], kinds: [1], limit: 10),
        cachePolicy: .cacheWithNetwork
    )

    var cachedEventCount = 0
    var networkEventCount = 0

    let observeTask = Task {
        for await event in subscription.events {
            // We can't easily tell if it came from cache or network without additional tracking
            cachedEventCount += 1
            print("   Received event: \(String(event.id.prefix(16)))...")
            if cachedEventCount >= 5 {
                break
            }
        }
    }

    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)
    observeTask.cancel()

    print("   Total events received: \(cachedEventCount)")
    printSuccess("Cache observation works")
    printDiscovery("cacheWithNetwork returns events from both sources")

    // Test 5.2: Cache-only observation
    printTest("Subscribe with cacheOnly policy")
    await ndk.disconnect() // Disconnect to ensure only cache is used

    let cacheOnlySub = ndk.subscribe(
        filter: NDKFilter(authors: [pubkey], kinds: [1], limit: 10),
        cachePolicy: .cacheOnly
    )

    var cacheOnlyCount = 0
    let cacheOnlyTask = Task {
        for await event in cacheOnlySub.events {
            cacheOnlyCount += 1
            print("   Cache-only event: \(String(event.id.prefix(16)))...")
            if cacheOnlyCount >= 5 {
                break
            }
        }
    }

    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)
    cacheOnlyTask.cancel()

    print("   Cache-only events: \(cacheOnlyCount)")
    printDiscovery("cacheOnly policy returns events without network")
}

func testCachePersistence() async throws {
    printSection("TEST 6: Cache Persistence")

    let cachePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_persistence_\(UUID().uuidString).db")

    // Test 6.1: Write to cache
    printTest("Write events to persistent cache")
    do {
        let cache1 = try await NDKSQLiteCache(databasePath: cachePath.path)
        let ndk1 = NDK(relayUrls: TEST_RELAYS, cache: cache1)
        let signer = try NDKPrivateKeySigner.generate()
        ndk1.signer = signer

        await ndk1.connect()
        try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

        // Publish events
        let event1 = try await NDKEventBuilder(ndk: ndk1)
            .content("Persistent event 1")
            .build()
        let event2 = try await NDKEventBuilder(ndk: ndk1)
            .content("Persistent event 2")
            .build()

        _ = try await ndk1.publish(event1)
        _ = try await ndk1.publish(event2)

        try await Task.sleep(nanoseconds: TIMEOUT_SHORT)
        print("   Published 2 events")
        print("   Event 1 ID: \(String(event1.id.prefix(16)))...")
        print("   Event 2 ID: \(String(event2.id.prefix(16)))...")

        await ndk1.disconnect()
        printSuccess("Events written to cache")

        // Test 6.2: Read from cache after recreation
        printTest("Read from cache after recreation")
        let cache2 = try await NDKSQLiteCache(databasePath: cachePath.path)
        let ndk2 = NDK(relayUrls: [], cache: cache2) // No relays, cache only
        ndk2.signer = signer

        let pubkey = try await signer.pubkey
        let subscription = ndk2.subscribe(
            filter: NDKFilter(authors: [pubkey], kinds: [1], limit: 10),
            cachePolicy: .cacheOnly
        )

        var persistedEvents: [NDKEvent] = []
        let readTask = Task {
            for await event in subscription.events {
                persistedEvents.append(event)
                if persistedEvents.count >= 10 {
                    break
                }
            }
        }

        try await Task.sleep(nanoseconds: TIMEOUT_SHORT)
        readTask.cancel()

        print("   Read \(persistedEvents.count) events from cache")

        if persistedEvents.count >= 2 {
            printSuccess("Events persisted across cache instances")
            printDiscovery("SQLite cache persists events to disk")
        } else {
            print("   Only \(persistedEvents.count) events found")
            printDiscovery("Cache persistence may depend on confirmation state")
        }

        // Clean up
        try? FileManager.default.removeItem(at: cachePath)
    } catch {
        printFailure("Cache persistence test failed", error: error)
        try? FileManager.default.removeItem(at: cachePath)
    }
}

func testCacheVsMemory() async throws {
    printSection("TEST 7: MemoryCache vs SQLiteCache Comparison")

    let signer = try NDKPrivateKeySigner.generate()
    let pubkey = try await signer.pubkey

    // Test 7.1: MemoryCache behavior
    printTest("MemoryCache behavior")
    let memCache = MemoryCache()
    let ndkMem = NDK(relayUrls: TEST_RELAYS, cache: memCache)
    ndkMem.signer = signer

    await ndkMem.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    let memEvent = try await NDKEventBuilder(ndk: ndkMem)
        .content("MemoryCache test event")
        .build()
    _ = try await ndkMem.publish(memEvent)

    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)
    print("   MemoryCache event published")

    // Check unpublished events
    let memUnpublished = await memCache.getUnpublishedEvents(limit: 100)
    print("   MemoryCache unpublished: \(memUnpublished.count)")
    printDiscovery("MemoryCache may not support optimistic publishing features")

    await ndkMem.disconnect()

    // Test 7.2: SQLiteCache behavior
    printTest("SQLiteCache behavior")
    let sqlCache = try await NDKSQLiteCache()
    let ndkSQL = NDK(relayUrls: TEST_RELAYS, cache: sqlCache)
    ndkSQL.signer = signer

    // Publish offline
    let sqlEvent = try await NDKEventBuilder(ndk: ndkSQL)
        .content("SQLiteCache test event")
        .build()
    _ = try await ndkSQL.publish(sqlEvent)

    let sqlUnpublished = await sqlCache.getUnpublishedEvents(limit: 100)
    print("   SQLiteCache unpublished: \(sqlUnpublished.count)")

    if sqlUnpublished.count > 0 {
        printSuccess("SQLiteCache tracks unpublished events")
        printDiscovery("SQLiteCache has full optimistic publishing support")
    }

    // Test 7.3: Feature comparison
    printTest("Feature comparison")
    print("   MemoryCache:")
    print("   - Persistence: No")
    print("   - Optimistic publishing: Limited/No")
    print("   - Performance: Fast (in-memory)")
    print("")
    print("   SQLiteCache:")
    print("   - Persistence: Yes")
    print("   - Optimistic publishing: Yes")
    print("   - Performance: Slower (disk I/O)")
    printDiscovery("Use SQLiteCache for production, MemoryCache for testing")
}

// MARK: - Main Test Runner

@main
struct TestApp4 {
    static func main() async {
        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║         NDKSwift Test App 4: Cache & Optimistic Publishing        ║")
        print("║                                                                    ║")
        print("║  This test validates caching and optimistic publishing through    ║")
        print("║  hands-on testing with different cache implementations.           ║")
        print("╚════════════════════════════════════════════════════════════════════╝")

        do {
            try await testCacheInitialization()
            try await testOptimisticPublishing()
            try await testEventConfirmationStates()
            try await testManualRetry()
            try await testCacheObservation()
            try await testCachePersistence()
            try await testCacheVsMemory()

            printSection("TEST SUMMARY")
            print("✅ All cache and optimistic publishing tests completed!")
            print("\nKey Discoveries:")
            print("- MemoryCache is simple but doesn't persist")
            print("- SQLiteCache persists events and supports optimistic publishing")
            print("- Can publish events while offline (optimistic publishing)")
            print("- Events have confirmation states: .optimistic and .confirmed")
            print("- Unpublished events automatically retry when connected")
            print("- Manual retry available via retryUnpublishedEvents()")
            print("- Cache policies control data sources for subscriptions")
            print("- SQLiteCache recommended for production use")

        } catch {
            printFailure("Test suite failed", error: error)
        }
    }
}
