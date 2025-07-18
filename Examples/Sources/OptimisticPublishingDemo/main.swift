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
let cache = NDKSQLiteCache()
let ndk = NDK(
    relayUrls: [
        "wss://relay.damus.io",
        "wss://relay.primal.net",
        "wss://nos.lol"
    ],
    cache: cache
)

// Generate a test signer
let signer = try NDKPrivateKeySigner.generate()
ndk.signer = signer

print("📱 User pubkey: \(signer.publicKey.hex)")

// Configure optimistic publishing (enabled by default)
ndk.optimisticPublishingConfig = NDKOptimisticPublishingConfig(
    enabled: true,
    cacheUnpublishedEvents: true,
    dispatchToSubscriptions: true
)

// Start a subscription BEFORE connecting
// This will receive optimistic events immediately
print("\n📡 Starting subscription (before connecting)...")
let subscription = ndk.subscribe(filters: [
    NDKFilter(
        authors: [signer.publicKey.hex],
        kinds: [1],
        limit: 10
    )
])

// Monitor events in background
Task {
    print("👀 Monitoring for events...")
    for await event in subscription {
        let statusIcon = switch event.source {
        case .optimistic: "⏳"
        case .relay: "✅"
        case .cache: "💾"
        }
        
        print("\n\(statusIcon) Event received from \(event.source):")
        print("   Content: \(event.content)")
        print("   ID: \(event.id)")
        
        // Check confirmation state
        if let state = await cache.getEventConfirmationState(eventId: event.id) {
            switch state {
            case .optimistic:
                print("   Status: Waiting to send...")
            case .partial(let confirmed, let pending):
                print("   Status: Sent to \(confirmed.count) relays, pending on \(pending.count)")
            case .confirmed:
                print("   Status: Fully confirmed ✓")
            }
        }
    }
}

// Small delay to ensure subscription is ready
try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

// Publish BEFORE connecting (simulating offline state)
print("\n🔌 Publishing while offline...")
let offlineEvent = NDKEvent(
    content: "This was published while offline! 📴",
    tags: [["client", "ndk-swift-demo"]]
)

try await ndk.publish(offlineEvent)
print("✅ Offline event published (appears immediately in subscription!)")

// Check unpublished events
let unpublished1 = try await cache.getUnpublishedEvents(limit: 10)
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
let onlineEvent = NDKEvent(
    content: "This was published while online! 🌐",
    tags: [["client", "ndk-swift-demo"]]
)

try await ndk.publish(onlineEvent)

// Monitor confirmation states
print("\n📊 Monitoring event confirmation states...")
for i in 0..<5 {
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
    let unpublished = try await cache.getUnpublishedEvents(limit: 100)
    if !unpublished.isEmpty {
        print("Still unpublished: \(unpublished.count) events")
    }
}

// Demonstrate manual retry
print("\n🔄 Manually retrying unpublished events...")
try await ndk.retryUnpublishedEvents()

// Final check
try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
let finalUnpublished = try await cache.getUnpublishedEvents(limit: 100)
print("\n✅ Final unpublished count: \(finalUnpublished.count)")

// Demonstrate subscription options
print("\n🎯 Testing subscription with skipOptimisticEvents...")

// Create subscription that skips optimistic events
var strictOptions = NDKSubscriptionOptions()
strictOptions.skipOptimisticEvents = true

let strictSubscription = ndk.subscribe(
    filters: [NDKFilter(authors: [signer.publicKey.hex], kinds: [1])],
    options: strictOptions
)

// Disconnect to simulate offline again
await ndk.disconnect()
print("🔌 Disconnected from relays")

// Monitor strict subscription
Task {
    print("👀 Monitoring strict subscription (no optimistic events)...")
    for await event in strictSubscription {
        print("   Strict sub received: \(event.content) from \(event.source)")
    }
}

// Publish while offline
let testEvent = NDKEvent(
    content: "Testing strict subscription - you won't see this immediately! 🚫",
    tags: []
)
try await ndk.publish(testEvent)
print("📤 Published test event (won't appear in strict subscription)")

try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

print("\n✅ Demo complete!")
print("\nKey takeaways:")
print("- Events published while offline appear immediately in local subscriptions")
print("- Events are automatically retried when relays reconnect")
print("- Confirmation states let you show accurate UI feedback")
print("- Subscriptions can opt-out of optimistic events if needed")

exit(0)

func describeState(_ state: EventConfirmationState) -> String {
    switch state {
    case .optimistic:
        return "⏳ Optimistic (waiting to send)"
    case .partial(let confirmed, let pending):
        return "📤 Partial (sent to \(confirmed.count), pending on \(pending.count))"
    case .confirmed:
        return "✅ Confirmed (all relays)"
    }
}

// Helper to describe event source
extension NDKEventSource: CustomStringConvertible {
    public var description: String {
        switch self {
        case .optimistic:
            return "optimistic"
        case .relay(let relay):
            return "relay(\(relay.url))"
        case .cache:
            return "cache"
        }
    }
}