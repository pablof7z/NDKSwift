#!/usr/bin/env swift

import Foundation
import NDKSwift

// Demo to verify tag aggregation is working

// Create mock relay pool that logs subscriptions
class LoggingRelayPool: NDKRelayPool {
    private var subscriptionCount = 0
    
    override func subscribe(
        filter: NDKFilter,
        subscriptionId: String,
        exclusiveRelays: Set<String>? = nil
    ) async -> NDKSubscription {
        subscriptionCount += 1
        print("\n📡 Subscription #\(subscriptionCount):")
        print("   ID: \(subscriptionId)")
        print("   Filter: \(filter)")
        if let tags = filter.tags {
            for (key, values) in tags {
                print("   Tag #\(key): \(values.count) values")
                if values.count <= 5 {
                    for value in values {
                        print("     - \(value)")
                    }
                } else {
                    print("     - \(values.prefix(3).joined(separator: ", "))... and \(values.count - 3) more")
                }
            }
        }
        
        return MockSubscription(pool: self, filter: filter, subscriptionId: subscriptionId)
    }
}

class MockSubscription: NDKSubscription {
    override func start() async {}
    override func stop() async {}
}

// Simple cache adapter
class MockCacheAdapter: NDKCacheAdapter {
    func save(event: NDKEvent) async throws {}
    func save(events: [NDKEvent]) async throws {}
    func fetchEvents(filter: NDKFilter, limit: Int?) async throws -> [NDKEvent] { [] }
    func deleteEvent(withId eventId: String) async throws {}
    func observe(filter: NDKFilter, cachePolicy: NDKCachePolicy, maxAge: TimeInterval?) async -> ObservationHandle {
        ObservationHandle { }
    }
    func fetchProfile(pubkey: String) async throws -> NDKUserProfile? { nil }
    func saveProfile(_ profile: NDKUserProfile, for pubkey: String) async throws {}
}

// Main demo
print("🚀 NDKSwift Tag Aggregation Demo")
print("================================\n")

let relayPool = LoggingRelayPool()
let cache = MockCacheAdapter()
let ndk = NDK(relayPool: relayPool, cacheAdapter: cache)

// Simulate multiple conversation status queries
let conversationIds = [
    "668283f1c6bf749fb59154693345345fece515d300be93d8dd0d8e5ae00e68b2",
    "8f3efc350f4b7a717653651ce791d8f846ff792dda494d36aa13a2cb15f0d0aa",
    "b9a35109a79eee73ec54cdfcc17f1963c18e3d396a8a1085edce80adc3a43610",
    "97fc659ae9a575443a11e50c90d6b8eebd39b0b80be7dc45e4dc83b066f84891",
    "ce87fc923a6d0d43f1c65c7c75cc25dce1598e10a92accd9190ab46c3ca6ddf2"
]

print("Creating \(conversationIds.count) separate observe calls...")
print("Each requests kind 1111 with a different #e tag value\n")

// Create multiple observe calls rapidly
var tasks: [Task<Void, Never>] = []

for (index, conversationId) in conversationIds.enumerated() {
    print("➡️  Creating observe #\(index + 1) for conversation: \(conversationId.prefix(8))...")
    
    let task = Task {
        let filter = NDKFilter(
            kinds: [1111],
            tags: ["e": [conversationId]]
        )
        
        let dataSource = ndk.observe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )
        
        // Start the subscription
        for await _ in dataSource.events {
            break // Just trigger the subscription
        }
    }
    tasks.append(task)
}

// Give aggregation window time to work
print("\n⏳ Waiting for aggregation window (100ms)...")
Thread.sleep(forTimeInterval: 0.15)

print("\n✅ Results:")
print("Without aggregation, we would see 5 separate subscriptions.")
print("With aggregation, filters with the same structure (kinds + tag keys) are combined!")

// Cancel tasks
for task in tasks {
    task.cancel()
}

print("\n🎉 Demo complete!")