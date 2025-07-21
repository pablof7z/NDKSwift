import Foundation
import NDKSwift

// Basic E2E test demonstrating event creation, signing, publishing, and subscribing
print("🚀 Starting Basic Event Flow E2E Test")
print("   This test validates the fundamental operations of NDKSwift")

// Create NDK instances
let publisherNDK = NDK(cache: MemoryCache())
let subscriberNDK = NDK(cache: MemoryCache())

// Create signer
let signer = try NDKPrivateKeySigner.generate()
let pubkey = try await signer.pubkey
publisherNDK.signer = signer

print("\n📝 Generated keypair")
print("   Public key: \(String(pubkey.prefix(16)))...")

// Add relays
let relayURLs = [
    "wss://relay.damus.io",
    "wss://relay.nostr.band",
    "wss://nos.lol"
]

print("\n🌐 Adding relays...")
for relay in relayURLs {
    await publisherNDK.addRelay(relay)
    await subscriberNDK.addRelay(relay)
    print("   Added: \(relay)")
}

// Connect
print("\n🔌 Connecting to relays...")
await publisherNDK.connect()
await subscriberNDK.connect()

// Wait for connections
let pubConnected = await publisherNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
let subConnected = await subscriberNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)

guard pubConnected > 0, subConnected > 0 else {
    print("❌ Failed to connect to relays")
    exit(1)
}

print("✅ Connected to \(pubConnected) relays for publisher")
print("✅ Connected to \(subConnected) relays for subscriber")

// Create a test event
let content = "Hello from NDKSwift E2E test at \(Date())"
print("\n📝 Creating event...")
let event = try await publisherNDK.event()
    .content(content)
    .kind(EventKind.textNote)
    .tag(["test", "e2e"])
    .tag(["client", "NDKSwift"])
    .build()

print("   Event ID: \(String(event.id.prefix(16)))...")
print("   Content: \(content)")
print("   Created at: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")

// Set up subscription before publishing
print("\n👂 Setting up subscription...")
let filter = NDKFilter(
    authors: [pubkey],
    kinds: [EventKind.textNote],
    limit: 10
)

let dataSource = subscriberNDK.observe(filter: filter)
var foundEvent = false
let startTime = Date()

// Start observing in background task
let observerTask = Task { @MainActor in
    print("   Subscription active, waiting for events...")
    var eventCount = 0
    for await receivedEvent in dataSource.events {
        eventCount += 1
        let elapsed = Date().timeIntervalSince(startTime)
        print("   📨 Received event #\(eventCount) at +\(String(format: "%.3f", elapsed))s: \(String(receivedEvent.id.prefix(16)))...")
        
        if receivedEvent.id == event.id {
            print("   ✅ Found our published event!")
            foundEvent = true
            break
        }
        
        // Limit iterations to prevent infinite loop
        if eventCount >= 20 || Date().timeIntervalSince(startTime) > 15.0 {
            print("   ⏱️ Timeout reached or max events processed")
            break
        }
    }
}

// Give subscription time to establish
try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

// Publish the event
print("\n📤 Publishing event...")
let publishStart = Date()
let publishedRelays = try await publisherNDK.publish(event)
let publishTime = Date().timeIntervalSince(publishStart)

print("   Published to \(publishedRelays.count) relays in \(String(format: "%.3f", publishTime))s")
for relay in publishedRelays {
    print("   ✅ \(relay)")
}

// Wait for the event to be received
print("\n⏳ Waiting for event to be received via subscription...")
let timeout = Date().addingTimeInterval(10.0)
while !foundEvent && Date() < timeout {
    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
}

// Cancel observer task
observerTask.cancel()

if foundEvent {
    print("\n🎉 SUCCESS: Event was published and received!")
} else {
    print("\n❌ FAILED: Event was not received within timeout")
}

// Test one-shot fetch
print("\n🔍 Testing one-shot event fetch...")
let fetchDataSource = subscriberNDK.observe(filter: filter, maxAge: 3600)
var fetchedEvents: [NDKEvent] = []

let fetchTimeout = Date().addingTimeInterval(2.0)
for await fetchedEvent in fetchDataSource.events {
    fetchedEvents.append(fetchedEvent)
    if fetchedEvents.count >= 5 || Date() > fetchTimeout {
        break
    }
}

print("   Fetched \(fetchedEvents.count) events")
let foundInFetch = fetchedEvents.contains { $0.id == event.id }
if foundInFetch {
    print("   ✅ Our event was in the fetched results")
} else {
    print("   ❌ Our event was NOT in the fetched results")
}

// Test fetching by ID
print("\n🔍 Testing fetch by event ID...")
let idFilter = NDKFilter(ids: [event.id])
let idDataSource = subscriberNDK.observe(filter: idFilter, maxAge: 3600)

var idFetchedEvent: NDKEvent?
let idTimeout = Date().addingTimeInterval(2.0)
for await fetchedEvent in idDataSource.events {
    if fetchedEvent.id == event.id {
        idFetchedEvent = fetchedEvent
        break
    }
    if Date() > idTimeout {
        break
    }
}

if let fetched = idFetchedEvent {
    print("   ✅ Successfully fetched event by ID")
    print("   Content matches: \(fetched.content == event.content)")
} else {
    print("   ❌ Failed to fetch event by ID")
}

// Cleanup
print("\n🧹 Disconnecting from relays...")
await publisherNDK.disconnect()
await subscriberNDK.disconnect()

let totalTime = Date().timeIntervalSince(startTime)
print("\n✅ Test completed in \(String(format: "%.3f", totalTime))s")

// Summary
print("\n📊 Test Summary:")
print("   - Event creation: ✅")
print("   - Event signing: ✅")
print("   - Publishing: \(publishedRelays.count > 0 ? "✅" : "❌")")
print("   - Real-time subscription: \(foundEvent ? "✅" : "❌")")
print("   - One-shot fetch: \(foundInFetch ? "✅" : "❌")")
print("   - Fetch by ID: \(idFetchedEvent != nil ? "✅" : "❌")")

exit(foundEvent && publishedRelays.count > 0 ? 0 : 1)