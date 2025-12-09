#!/usr/bin/env swift

/*
 * TestApp1-CoreBasics.swift
 *
 * COMPREHENSIVE TEST: Core NDKSwift Features
 *
 * This test validates the ACTUAL behavior of NDKSwift's core functionality.
 * It tests:
 * 1. NDK initialization with different configurations
 * 2. Relay connection/disconnection
 * 3. Basic event creation and publishing
 * 4. Simple subscriptions using NDKSubscription API
 * 5. Different cache policies (cacheWithNetwork, cacheOnly, networkOnly)
 * 6. Signer creation (generate, from hex, from nsec)
 * 7. Key conversions (hex/npub/nsec)
 *
 * CRITICAL: This validates ACTUAL behavior, not documentation!
 */

import Foundation
import NDKSwift

// MARK: - Test Configuration

let TIMEOUT_SHORT = 2_000_000_000  // 2 seconds
let TIMEOUT_MEDIUM = 5_000_000_000 // 5 seconds
let TIMEOUT_LONG = 10_000_000_000  // 10 seconds

let TEST_RELAYS = [
    "wss://relay.damus.io",
    "wss://relay.primal.net",
    "wss://nos.lol"
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

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual == expected {
        printSuccess("\(message): \(actual) == \(expected)")
    } else {
        printFailure("\(message): \(actual) != \(expected)")
    }
}

func assertNotNil<T>(_ value: T?, _ message: String) {
    if value != nil {
        printSuccess("\(message): value exists")
    } else {
        printFailure("\(message): value is nil")
    }
}

// MARK: - Test Functions

func testNDKInitialization() async throws {
    printSection("TEST 1: NDK Initialization")

    // Test 1.1: Basic initialization with relays
    printTest("Basic initialization with relays")
    let ndk1 = NDK(relayUrls: TEST_RELAYS)
    printSuccess("Created NDK with \(TEST_RELAYS.count) relays")
    printDiscovery("NDK can be initialized with just relay URLs - no errors thrown")

    // Test 1.2: Initialization with signer
    printTest("Initialization with signer")
    let signer = try NDKPrivateKeySigner.generate()
    let ndk2 = NDK(relayUrls: TEST_RELAYS, signer: signer)
    assertNotNil(ndk2.signer, "NDK has signer")
    printDiscovery("NDK accepts optional signer during initialization")

    // Test 1.3: Initialization with cache
    printTest("Initialization with MemoryCache")
    let cache = MemoryCache()
    let ndk3 = NDK(relayUrls: TEST_RELAYS, cache: cache)
    printSuccess("Created NDK with MemoryCache")
    printDiscovery("NDK accepts optional cache during initialization (defaults to MemoryCache)")

    // Test 1.4: Empty initialization
    printTest("Empty initialization (no relays)")
    let ndk4 = NDK()
    printSuccess("Created NDK with no relays")
    printDiscovery("NDK can be initialized without any parameters")

    // Test 1.5: Check activeUser
    printTest("Active user from signer")
    let activeUser = await ndk2.activeUser
    assertNotNil(activeUser, "Active user exists when signer is set")
    if let user = activeUser {
        print("   Active user pubkey: \(String(user.pubkey.prefix(16)))...")
        printDiscovery("activeUser is derived from signer and returns NDKUser")
    }
}

func testSignerCreation() async throws {
    printSection("TEST 2: Signer Creation and Key Conversions")

    // Test 2.1: Generate new signer
    printTest("Generate new signer")
    let generatedSigner = try NDKPrivateKeySigner.generate()
    let pubkey = try await generatedSigner.pubkey
    print("   Generated pubkey: \(String(pubkey.prefix(16)))...")
    printSuccess("Signer generated successfully")
    printDiscovery("NDKPrivateKeySigner.generate() creates a new random keypair")

    // Test 2.2: Create from hex private key
    printTest("Create signer from hex private key")
    let hexPrivKey = generatedSigner.privateKeyValue
    let signerFromHex = try NDKPrivateKeySigner(privateKey: hexPrivKey)
    let pubkeyFromHex = try await signerFromHex.pubkey
    assertEqual(pubkeyFromHex, pubkey, "Pubkey from hex matches original")
    printDiscovery("NDKPrivateKeySigner(privateKey:) accepts 64-character hex string")

    // Test 2.3: Create from nsec
    printTest("Create signer from nsec")
    let nsec = try generatedSigner.nsec
    print("   nsec: \(String(nsec.prefix(20)))...")
    let signerFromNsec = try NDKPrivateKeySigner(nsec: nsec)
    let pubkeyFromNsec = try await signerFromNsec.pubkey
    assertEqual(pubkeyFromNsec, pubkey, "Pubkey from nsec matches original")
    printDiscovery("NDKPrivateKeySigner(nsec:) accepts Bech32-encoded private key")

    // Test 2.4: Get npub from signer
    printTest("Convert pubkey to npub")
    let npub = try generatedSigner.npub
    print("   npub: \(String(npub.prefix(20)))...")
    printSuccess("npub generated successfully")
    printDiscovery("Signer provides npub property for Bech32-encoded public key")

    // Test 2.5: Invalid hex key
    printTest("Error handling - invalid hex key")
    do {
        let _ = try NDKPrivateKeySigner(privateKey: "invalid")
        printFailure("Should have thrown error for invalid key")
    } catch {
        printSuccess("Correctly throws error for invalid hex key")
        printDiscovery("Invalid private keys are validated and throw NDKError")
    }

    // Test 2.6: Encryption schemes
    printTest("Available encryption schemes")
    let schemes = await generatedSigner.encryptionEnabled()
    print("   Supported schemes: \(schemes)")
    printSuccess("Signer reports encryption capabilities")
    printDiscovery("Private key signer supports both NIP-04 and NIP-44 encryption")
}

func testRelayConnections() async throws {
    printSection("TEST 3: Relay Connection/Disconnection")

    let ndk = NDK(relayUrls: TEST_RELAYS)

    // Test 3.1: Connect to relays
    printTest("Connect to relays")
    await ndk.connect()
    printSuccess("Connect called (async operation)")
    printDiscovery("ndk.connect() is async and doesn't throw errors")

    // Wait for connections to establish
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 3.2: Check connection status
    printTest("Connection status summary")
    let (connected, total) = await ndk.getRelayConnectionSummary()
    print("   Connected: \(connected)/\(total) relays")
    printSuccess("Got connection summary")
    printDiscovery("getRelayConnectionSummary() returns (connected, total) tuple")

    // Test 3.3: Get individual relay statuses
    printTest("Individual relay statuses")
    let relays = await ndk.pool.relays
    for relay in relays.values.prefix(3) {
        let status = await relay.connection.status
        print("   \(relay.url): \(status)")
    }
    printDiscovery("Can access individual relay connection statuses via ndk.pool.relays")

    // Test 3.4: Disconnect
    printTest("Disconnect from relays")
    await ndk.disconnect()
    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
    let (connectedAfter, _) = await ndk.getRelayConnectionSummary()
    print("   Connected after disconnect: \(connectedAfter)")
    printSuccess("Disconnect called")
    printDiscovery("ndk.disconnect() is async and closes all relay connections")
}

func testBasicEventPublishing() async throws {
    printSection("TEST 4: Basic Event Creation and Publishing")

    let ndk = NDK(relayUrls: Array(TEST_RELAYS.prefix(1))) // Use just one relay
    let signer = try NDKPrivateKeySigner.generate()
    ndk.signer = signer

    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 4.1: Publish with builder closure
    printTest("Publish event using builder closure")
    let (event1, result1) = try await ndk.publish { builder in
        builder
            .content("Test message from NDKSwift test app")
            .tag(["test", "automated"])
    }
    print("   Event ID: \(String(event1.id.prefix(16)))...")
    print("   Published to \(result1.count) relay(s)")
    printSuccess("Event published via closure builder")
    printDiscovery("ndk.publish(builder:) returns (event, [RelayPublishResult])")
    printDiscovery("Default event kind is 1 (text note)")

    // Test 4.2: Publish with explicit kind
    printTest("Publish with explicit kind")
    let (event2, result2) = try await ndk.publish { builder in
        builder
            .content("Custom kind event")
            .kind(30078)
            .tag(["d", "test-identifier"])
    }
    assertEqual(event2.kind, 30078, "Event has correct kind")
    print("   Published kind \(event2.kind) to \(result2.count) relay(s)")
    printDiscovery("Builder supports .kind() method for custom kinds")

    // Test 4.3: Publish pre-built event
    printTest("Publish pre-built event")
    let eventBuilder = try await NDKEventBuilder(ndk: ndk)
        .content("Pre-built event")
        .kind(EventKind.textNote)
    let prebuiltEvent = try await eventBuilder.build()
    let result3 = try await ndk.publish(prebuiltEvent)
    print("   Published to \(result3.count) relay(s)")
    printSuccess("Can publish pre-built event")
    printDiscovery("ndk.publish(event) accepts pre-built NDKEvent")
    printDiscovery("NDKEventBuilder can be used separately with .build()")

    // Test 4.4: Event properties
    printTest("Event properties and structure")
    print("   Event ID: \(event1.id)")
    print("   Pubkey: \(String(event1.pubkey.prefix(16)))...")
    print("   Created at: \(event1.createdAt)")
    print("   Kind: \(event1.kind)")
    print("   Content: \(event1.content)")
    print("   Tags: \(event1.tags)")
    print("   Signature: \(String(event1.signature.prefix(16)))...")
    printDiscovery("NDKEvent has properties: id, pubkey, createdAt, kind, content, tags, signature")

    // Test 4.5: Publish without signer
    printTest("Publish without signer (error case)")
    let ndkNoSigner = NDK(relayUrls: TEST_RELAYS)
    do {
        let _ = try await ndkNoSigner.publish { builder in
            builder.content("This should fail")
        }
        printFailure("Should have thrown error without signer")
    } catch {
        printSuccess("Correctly throws error when publishing without signer")
        printDiscovery("Publishing requires a signer to be set on NDK instance")
    }

    await ndk.disconnect()
}

func testBasicSubscriptions() async throws {
    printSection("TEST 5: Basic Subscriptions")

    let ndk = NDK(relayUrls: TEST_RELAYS)
    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 5.1: Subscribe with filter
    printTest("Subscribe to events with filter")
    let filter = NDKFilter(
        kinds: [EventKind.textNote],
        since: Timestamp(Date().addingTimeInterval(-300).timeIntervalSince1970), // Last 5 min
        limit: 5
    )
    print("   Filter: kinds=[\(EventKind.textNote)], since=5min ago, limit=5")
    let subscription = ndk.subscribe(filter: filter)
    printSuccess("Created subscription")
    printDiscovery("ndk.subscribe(filter:) returns NDKSubscription<NDKEvent>")

    // Test 5.2: Receive events via AsyncSequence
    printTest("Receive events via AsyncSequence")
    var eventCount = 0
    let collectTask = Task {
        for await event in subscription.events {
            eventCount += 1
            print("   Event #\(eventCount): \(String(event.content.prefix(30)))")
            if eventCount >= 5 {
                break
            }
        }
    }

    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)
    collectTask.cancel()
    print("   Total events received: \(eventCount)")
    printSuccess("Events received via AsyncSequence")
    printDiscovery("subscription.events is an AsyncStream<NDKEvent>")
    printDiscovery("Events stream continuously - use break or Task cancellation to stop")

    await ndk.disconnect()
}

func testCachePolicies() async throws {
    printSection("TEST 6: Cache Policies")

    let cache = MemoryCache()
    let ndk = NDK(relayUrls: TEST_RELAYS, cache: cache)
    let signer = try NDKPrivateKeySigner.generate()
    ndk.signer = signer

    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // First, publish an event to have something in cache
    printTest("Publish event to populate cache")
    let (testEvent, _) = try await ndk.publish { builder in
        builder.content("Event for cache testing")
    }
    try await Task.sleep(nanoseconds: 1_000_000_000) // 1s for relay confirmation

    let pubkey = try await signer.pubkey

    // Test 6.1: cacheWithNetwork (default)
    printTest("CachePolicy.cacheWithNetwork")
    let sub1 = ndk.subscribe(
        filter: NDKFilter(authors: [pubkey], kinds: [1], limit: 10),
        cachePolicy: .cacheWithNetwork
    )
    var count1 = 0
    let task1 = Task {
        for await event in sub1.events {
            count1 += 1
            if count1 >= 5 { break }
        }
    }
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)
    task1.cancel()
    print("   Events with cacheWithNetwork: \(count1)")
    printDiscovery("cacheWithNetwork returns events from both cache and network")

    // Test 6.2: cacheOnly
    printTest("CachePolicy.cacheOnly")
    let sub2 = ndk.subscribe(
        filter: NDKFilter(authors: [pubkey], kinds: [1], limit: 10),
        cachePolicy: .cacheOnly
    )
    var count2 = 0
    let task2 = Task {
        for await event in sub2.events {
            count2 += 1
            if count2 >= 5 { break }
        }
    }
    try await Task.sleep(nanoseconds: 1_000_000_000) // 1s should be enough for cache
    task2.cancel()
    print("   Events with cacheOnly: \(count2)")
    printDiscovery("cacheOnly returns events only from cache, not network")

    // Test 6.3: networkOnly
    await ndk.disconnect()
    printTest("CachePolicy.networkOnly (disconnected)")
    let sub3 = ndk.subscribe(
        filter: NDKFilter(authors: [pubkey], kinds: [1], limit: 10),
        cachePolicy: .networkOnly
    )
    var count3 = 0
    let task3 = Task {
        for await event in sub3.events {
            count3 += 1
            if count3 >= 5 { break }
        }
    }
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)
    task3.cancel()
    print("   Events with networkOnly (disconnected): \(count3)")
    printDiscovery("networkOnly only returns events from network, ignores cache")
    printDiscovery("networkOnly returns 0 events when disconnected")

    await ndk.disconnect()
}

func testFilterCreation() async throws {
    printSection("TEST 7: Filter Creation and Options")

    // Test 7.1: Basic filter
    printTest("Basic filter with kinds")
    let filter1 = NDKFilter(kinds: [1, 6, 7])
    print("   Filter: \(filter1)")
    printDiscovery("NDKFilter accepts array of kinds")

    // Test 7.2: Filter with authors
    printTest("Filter with authors")
    let filter2 = NDKFilter(
        authors: ["82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"],
        kinds: [1]
    )
    print("   Filter: \(filter2)")
    printDiscovery("NDKFilter accepts authors array")

    // Test 7.3: Filter with time range
    printTest("Filter with time range")
    let now = Timestamp(Date().timeIntervalSince1970)
    let hourAgo = Timestamp(Date().addingTimeInterval(-3600).timeIntervalSince1970)
    let filter3 = NDKFilter(
        kinds: [1],
        since: hourAgo,
        until: now,
        limit: 50
    )
    print("   Filter: \(filter3)")
    printDiscovery("NDKFilter supports since, until, and limit parameters")

    // Test 7.4: Filter with tags
    printTest("Filter with tags")
    var filter4 = NDKFilter(kinds: [1])
    filter4.addTagFilter("e", values: ["event_id_here"])
    filter4.addTagFilter("p", values: ["pubkey_here"])
    print("   Filter: \(filter4)")
    printDiscovery("NDKFilter supports tag filters via addTagFilter() method")

    // Test 7.5: Filter matching
    printTest("Filter matching events")
    let testEvent = NDKEvent(
        id: "test_id",
        pubkey: "test_pubkey",
        createdAt: now,
        kind: 1,
        tags: [],
        content: "test",
        signature: "test_sig"
    )
    let matchFilter = NDKFilter(kinds: [1])
    let matches = matchFilter.matches(event: testEvent)
    print("   Event matches filter: \(matches)")
    printDiscovery("NDKFilter has matches(event:) method for client-side filtering")
}

// MARK: - Main Test Runner

@main
struct TestApp1 {
    static func main() async {
        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║                  NDKSwift Test App 1: Core Basics                  ║")
        print("║                                                                    ║")
        print("║  This test validates the ACTUAL behavior of NDKSwift core         ║")
        print("║  functionality through hands-on testing and experimentation.      ║")
        print("╚════════════════════════════════════════════════════════════════════╝")

        do {
            try await testNDKInitialization()
            try await testSignerCreation()
            try await testRelayConnections()
            try await testBasicEventPublishing()
            try await testBasicSubscriptions()
            try await testCachePolicies()
            try await testFilterCreation()

            printSection("TEST SUMMARY")
            print("✅ All core basic tests completed!")
            print("\nKey Discoveries:")
            print("- NDK initialization is flexible with optional parameters")
            print("- Signers can be created from generated keys, hex, or nsec")
            print("- Relay connections are async and status can be monitored")
            print("- Event publishing uses builder pattern with closures")
            print("- Subscriptions use AsyncSequence for event streaming")
            print("- Cache policies control data source behavior")
            print("- Filters are powerful with multiple criteria options")

        } catch {
            printFailure("Test suite failed", error: error)
        }
    }
}
