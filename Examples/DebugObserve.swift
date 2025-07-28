#!/usr/bin/env swift

import Foundation
import NDKSwift

// Enable trace logging
NDKLogger.logLevel = .trace

print("=== Debugging NDKDataSource observe() ===\n")

// Create NDK
let ndk = NDK(relayUrls: ["wss://relay.primal.net"])

// Check dataRequirementManager
print("1. Checking dataRequirementManager existence...")
print("   dataRequirementManager: \(ndk.dataRequirementManager != nil ? "✓ exists" : "✗ nil")")

// Connect
print("\n2. Connecting to relay...")
await ndk.connect()
await ndk.waitForRelayConnections()
print("   ✓ Connected")

// Create filter
let filter = NDKFilter(kinds: [1])
print("\n3. Creating data source with filter...")
print("   Filter: kinds=\(filter.kinds ?? []), limit=\(filter.limit ?? 0)")

// Create data source
let dataSource = ndk.observe(filter: filter, cachePolicy: .networkOnly)
print("   ✓ Data source created")

// Give subscription time to setup
try await Task.sleep(nanoseconds: 1_000_000_000) // 1s

print("\n4. Waiting for events (5s timeout)...")

// Monitor for events
var receivedEvent = false
let timeout = Task {
    try await Task.sleep(nanoseconds: 5_000_000_000)
    if !receivedEvent {
        print("\n⏰ Timeout - no events received")
    }
}

// Try to get an event
for await event in dataSource.events {
    receivedEvent = true
    timeout.cancel()
    print("\n✅ EVENT RECEIVED via AsyncSequence!")
    print("   ID: \(event.id)")
    print("   Kind: \(event.kind)")
    print("   Content: \(String(event.content.prefix(50)))...")
    break
}

// Also check the @Published data property
print("\n5. Checking @Published data property...")
print("   Data count: \(dataSource.data.count)")
if !dataSource.data.isEmpty {
    print("   ✓ Data array has events")
} else {
    print("   ✗ Data array is empty")
}

print("\n=== Debug Complete ===")

await ndk.disconnect()
exit(receivedEvent ? 0 : 1)