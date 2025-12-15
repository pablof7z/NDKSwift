import Foundation
import NDKSwift

// Optimistic Publishing & Offline Support Demo
// This example demonstrates:
// 1. Publishing events while offline
// 2. Immediate appearance in local subscriptions
// 3. Automatic retry when connectivity is restored
// 4. Event confirmation state tracking

print("🚀 NDKSwift Optimistic Publishing Demo")
print("=====================================\n")

// Create NDK with SQLite cache (required for offline support)
let cache = try await NDKSQLiteCache()
let ndk = NDK(
    relayUrls: [
        "wss://relay.damus.io",
        "wss://relay.primal.net",
        "wss://nos.lol",
    ],
    cache: cache
)

// Generate a test signer
let signer = try NDKPrivateKeySigner.generate()
ndk.signer = signer

let pubkey = try await signer.pubkey
print("📱 User pubkey: \(pubkey)")

// Optimistic publishing is now always enabled - no configuration needed!

// Start observing BEFORE connecting
// This will receive optimistic events immediately
print("\n📡 Starting observer (before connecting)...")
let dataSource = ndk.subscribe(
    filter: NDKFilter(
        authors: [pubkey],
        kinds: [1],
        limit: 10
    ),
    cachePolicy: .cacheWithNetwork
)

// Monitor events in background
Task {
    print("👀 Monitoring for events...")
    for await event in dataSource.events {
        print("\n📬 Event received:")
        print("   Content: \(event.content)")
        print("   ID: \(event.id)")

        // Check confirmation state
        if let state = await cache.getEventConfirmationState(eventId: event.id) {
            switch state {
            case .optimistic:
                print("   Status: ⏳ Waiting to send...")
            case let .confirmed(fromRelay):
                print("   Status: ✅ Confirmed by \(fromRelay)")
            }
        }
    }
}

// Small delay to ensure subscription is ready
try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

// Publish BEFORE connecting (simulating offline state)
print("\n🔌 Publishing while offline...")
let offlineEvent = try await NDKEventBuilder(ndk: ndk)
    .content("This was published while offline! 📴")
    .tag(["client", "ndk-swift-demo"])
    .build()

_ = try await ndk.publish(offlineEvent)
print("✅ Offline event published (appears immediately in subscription!)")

// Check unpublished events
let unpublished1 = await cache.getUnpublishedEvents(limit: 10)
print("\n📦 Unpublished events in cache: \(unpublished1.count)")

// Wait a bit to see the optimistic event
try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

// Now connect to relays
print("\n🔌 Connecting to relays...")
await ndk.connect()

// Wait for connection
try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

print("✅ Connected! Unpublished events will retry automatically.")

// Publish another event while online
print("\n📤 Publishing while online...")
let onlineEvent = try await NDKEventBuilder(ndk: ndk)
    .content("This was published while online! 🌐")
    .tag(["client", "ndk-swift-demo"])
    .build()

_ = try await ndk.publish(onlineEvent)

// Monitor confirmation states
print("\n📊 Monitoring event confirmation states...")
for i in 0 ..< 5 {
    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

    print("\n--- Check \(i + 1) ---")

    // Check offline event
    if let state = await cache.getEventConfirmationState(eventId: offlineEvent.id) {
        print("Offline event: \(describeState(state))")
    }

    // Check online event
    if let state = await cache.getEventConfirmationState(eventId: onlineEvent.id) {
        print("Online event: \(describeState(state))")
    }

    // Check unpublished count
    let unpublished = await cache.getUnpublishedEvents(limit: 100)
    if !unpublished.isEmpty {
        print("Still unpublished: \(unpublished.count) events")
    }
}

// Demonstrate manual retry
print("\n🔄 Manually retrying unpublished events...")
let retryCount = try await ndk.retryUnpublishedEvents()
print("Retried \(retryCount) events")

// Final check
try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
let finalUnpublished = await cache.getUnpublishedEvents(limit: 100)
print("\n✅ Final unpublished count: \(finalUnpublished.count)")

// Demonstrate network-only observation
print("\n🎯 Testing observer with network-only cache policy...")

// Create observer that only shows network events
let strictDataSource = ndk.subscribe(
    filter: NDKFilter(authors: [pubkey], kinds: [1]),
    cachePolicy: .networkOnly
)

// Disconnect to simulate offline again
await ndk.disconnect()
print("🔌 Disconnected from relays")

// Monitor strict observer
Task {
    print("👀 Monitoring network-only observer (no cached/optimistic events)...")
    for await event in strictDataSource.events {
        print("   Network-only observer received: \(event.content)")
    }
}

// Publish while offline
let testEvent = try await NDKEventBuilder(ndk: ndk)
    .content("Testing strict subscription - you won't see this immediately! 🚫")
    .build()
_ = try await ndk.publish(testEvent)
print("📤 Published test event (won't appear in network-only observer)")

try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

print("\n✅ Demo complete!")
print("\nKey takeaways:")
print("- Events published while offline appear immediately in local subscriptions")
print("- Events are automatically retried when relays reconnect")
print("- Confirmation states let you show accurate UI feedback")
print("- Observers can use network-only cache policy to skip cached/optimistic events")

exit(0)

func describeState(_ state: EventConfirmationState) -> String {
    switch state {
    case .optimistic:
        return "⏳ Optimistic (waiting to send)"
    case let .confirmed(fromRelay):
        return "✅ Confirmed (from \(fromRelay))"
    }
}
