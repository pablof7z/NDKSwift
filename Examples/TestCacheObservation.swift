#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test script to verify cache observation works with the new AsyncThrowingStream API

print("🧪 Testing NDKSwift Cache Observation")
print("=====================================\n")

// Create NDK instance with SQLite cache
let ndk = NDK(explicitRelayURLs: ["wss://relay.primal.net"], cacheType: .sqlite)

// Test author's pubkey
let testAuthor = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"  // jack

print("📱 Creating cache-only subscription...")
let cacheFilter = NDKFilter(kinds: [1])
let cacheDataSource = ndk.observe(
    filter: cacheFilter,
    cachePolicy: .cacheOnly,
    subscriptionId: "cache-test"
)

// Track cache events
var cacheEventCount = 0
let cacheTask = Task {
    print("   ✅ Cache subscription started")
    for await event in cacheDataSource.events {
        cacheEventCount += 1
        print("   📦 Cache event #\(cacheEventCount): \(event.content.prefix(50))...")
    }
    print("   🔚 Cache subscription ended")
}

// Give cache subscription time to set up
try await Task.sleep(nanoseconds: 100_000_000) // 100ms

print("\n📡 Creating network subscription...")
let networkFilter = NDKFilter(
    authors: [testAuthor],
    kinds: [1],
    limit: 5
)
let networkDataSource = ndk.observe(
    filter: networkFilter,
    cachePolicy: .cacheWithNetwork,
    subscriptionId: "network-test"
)

// Collect network events
var networkEvents: [NDKEvent] = []
let networkTask = Task {
    print("   ✅ Network subscription started")
    for await event in networkDataSource.events {
        networkEvents.append(event)
        print("   🌐 Network event: \(event.content.prefix(50))...")
        
        if networkEvents.count >= 3 {
            break
        }
    }
    print("   🔚 Collected \(networkEvents.count) network events")
}

// Wait for network events
try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

// Check if cache subscription received the events
print("\n📊 Results:")
print("   Network events collected: \(networkEvents.count)")
print("   Cache events received: \(cacheEventCount)")

if cacheEventCount > 0 {
    print("\n✅ SUCCESS: Cache-only subscription received \(cacheEventCount) events!")
    print("   This confirms the reactive cache observation is working.")
} else {
    print("\n❌ FAILURE: Cache-only subscription received no events.")
    print("   The reactive cache observation may not be working correctly.")
}

// Clean up
cacheTask.cancel()
networkTask.cancel()
cacheDataSource.cancel()
networkDataSource.cancel()

print("\n🏁 Test completed")