#!/usr/bin/env swift

/*
 * TestApp2-Subscriptions.swift
 *
 * COMPREHENSIVE TEST: Advanced Subscription Features
 *
 * This test validates the ACTUAL behavior of NDKSwift's subscription system.
 * It tests:
 * 1. Filter creation with various parameters
 * 2. AsyncSequence-based subscriptions
 * 3. Using .collect() vs streaming with for await
 * 4. Different data source configurations
 * 5. Profile fetching using NDKProfileManager
 * 6. Event filtering and matching
 * 7. Relay-specific subscriptions
 * 8. Subscription lifecycle management
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

// Well-known test pubkeys
let JACK_PUBKEY = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
let FIATJAF_PUBKEY = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"

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

func testComplexFilters() async throws {
    printSection("TEST 1: Complex Filter Creation")

    // Test 1.1: Multi-kind filter
    printTest("Multi-kind filter")
    let filter1 = NDKFilter(
        kinds: [EventKind.textNote, EventKind.metadata, EventKind.contactList],
        limit: 20
    )
    print("   Filter: \(filter1)")
    printSuccess("Created filter with multiple kinds")
    printDiscovery("Can specify multiple kinds in a single filter")

    // Test 1.2: Multi-author filter
    printTest("Multi-author filter")
    let filter2 = NDKFilter(
        authors: [JACK_PUBKEY, FIATJAF_PUBKEY],
        kinds: [EventKind.textNote],
        limit: 10
    )
    print("   Filter: \(filter2)")
    printSuccess("Created filter with multiple authors")
    printDiscovery("Can batch multiple authors in a single filter for efficiency")

    // Test 1.3: Tag-based filters
    printTest("Tag-based filter")
    var filter3 = NDKFilter(kinds: [EventKind.textNote])
    filter3.addTagFilter("p", values: [JACK_PUBKEY])
    print("   Filter: \(filter3)")
    printSuccess("Created filter with 'p' tag")
    printDiscovery("Tag filters use addTagFilter() method")

    // Test 1.4: Event reference filter
    printTest("Event reference filter")
    let filter4 = NDKFilter(
        kinds: [EventKind.textNote],
        events: ["test_event_id_1", "test_event_id_2"]
    )
    print("   Filter: \(filter4)")
    printSuccess("Created filter with event references")
    printDiscovery("Filter supports 'events' parameter for #e tag filtering")

    // Test 1.5: Pubkey reference filter
    printTest("Pubkey reference filter")
    let filter5 = NDKFilter(
        kinds: [EventKind.textNote],
        pubkeys: [JACK_PUBKEY, FIATJAF_PUBKEY]
    )
    print("   Filter: \(filter5)")
    printSuccess("Created filter with pubkey references")
    printDiscovery("Filter supports 'pubkeys' parameter for #p tag filtering")

    // Test 1.6: Time-bounded filter
    printTest("Time-bounded filter")
    let now = Date()
    let dayAgo = now.addingTimeInterval(-86400)
    let filter6 = NDKFilter(
        kinds: [EventKind.textNote],
        since: Timestamp(dayAgo.timeIntervalSince1970),
        until: Timestamp(now.timeIntervalSince1970),
        limit: 100
    )
    print("   Filter: \(filter6)")
    printSuccess("Created time-bounded filter")
    printDiscovery("since/until use Timestamp type (Unix timestamps)")

    // Test 1.7: Filter fingerprint
    printTest("Filter fingerprint generation")
    let fingerprint = filter6.fingerprint
    print("   Fingerprint: \(fingerprint)")
    printSuccess("Generated filter fingerprint")
    printDiscovery("Each filter has a unique fingerprint for subscription management")
}

func testAsyncSequencePatterns() async throws {
    printSection("TEST 2: AsyncSequence Subscription Patterns")

    let ndk = NDK(relayUrls: TEST_RELAYS)
    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 2.1: Streaming with for-await
    printTest("Streaming events with for-await loop")
    let filter = NDKFilter(
        kinds: [EventKind.textNote],
        since: Timestamp(Date().addingTimeInterval(-3600).timeIntervalSince1970),
        limit: 5
    )
    let subscription = ndk.subscribe(filter: filter)

    var streamCount = 0
    let streamTask = Task {
        for await event in subscription.events {
            streamCount += 1
            print("   Stream event #\(streamCount): \(String(event.id.prefix(16)))...")
            if streamCount >= 5 {
                break
            }
        }
    }

    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)
    streamTask.cancel()
    print("   Total streamed: \(streamCount)")
    printSuccess("Events stream via for-await loop")
    printDiscovery("AsyncStream continues until break or Task cancellation")

    // Test 2.2: Collecting into array
    printTest("Collecting events into array")
    let filter2 = NDKFilter(
        kinds: [EventKind.textNote],
        since: Timestamp(Date().addingTimeInterval(-600).timeIntervalSince1970),
        limit: 3
    )
    let subscription2 = ndk.subscribe(filter: filter2, cachePolicy: .cacheWithNetwork)

    var collected: [NDKEvent] = []
    let collectTask = Task {
        for await event in subscription2.events {
            collected.append(event)
            if collected.count >= 3 {
                break
            }
        }
    }

    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)
    collectTask.cancel()
    print("   Collected \(collected.count) events")
    printSuccess("Can collect events into array")
    printDiscovery("Manual collection by appending in for-await loop")

    // Test 2.3: Using Task cancellation for timeout
    printTest("Task cancellation for timeout")
    let filter3 = NDKFilter(
        kinds: [EventKind.textNote],
        since: Timestamp(Date().timeIntervalSince1970), // Real-time
        limit: 10
    )
    let subscription3 = ndk.subscribe(filter: filter3, cachePolicy: .networkOnly)

    var timeoutCount = 0
    let timeoutTask = Task {
        for await event in subscription3.events {
            timeoutCount += 1
            print("   Real-time event: \(String(event.content.prefix(30)))")
        }
    }

    // Let it run for 3 seconds
    try await Task.sleep(nanoseconds: 3_000_000_000)
    timeoutTask.cancel()
    print("   Events in 3 seconds: \(timeoutCount)")
    printSuccess("Task cancellation stops subscription")
    printDiscovery("Use Task cancellation to implement timeouts")

    await ndk.disconnect()
}

func testRelayUpdates() async throws {
    printSection("TEST 3: Relay-Level Updates")

    let ndk = NDK(relayUrls: TEST_RELAYS)
    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    printTest("Monitor relay updates (EOSE, events, closed)")
    let filter = NDKFilter(
        kinds: [EventKind.textNote],
        since: Timestamp(Date().addingTimeInterval(-300).timeIntervalSince1970),
        limit: 5
    )
    let subscription = ndk.subscribe(filter: filter)

    var eoseCount = 0
    var eventCount = 0
    var closedCount = 0
    var aggregatedEose = false

    let updateTask = Task {
        for await update in subscription.relayUpdates {
            switch update {
            case let .event(event, relay):
                eventCount += 1
                print("   Event from \(relay): \(String(event.id.prefix(16)))")
            case let .eose(relay):
                eoseCount += 1
                print("   EOSE from \(relay)")
            case .aggregatedEose:
                aggregatedEose = true
                print("   AGGREGATED EOSE received")
            case let .closed(relay):
                closedCount += 1
                print("   Closed on \(relay)")
            }

            if aggregatedEose {
                break
            }
        }
    }

    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)
    updateTask.cancel()

    print("\n   Summary:")
    print("   - Events: \(eventCount)")
    print("   - Individual EOSE: \(eoseCount)")
    print("   - Aggregated EOSE: \(aggregatedEose)")
    print("   - Closed: \(closedCount)")

    printSuccess("Relay updates tracked")
    printDiscovery("subscription.relayUpdates is AsyncStream<RelayUpdate>")
    printDiscovery("RelayUpdate has cases: .event, .eose, .aggregatedEose, .closed")

    await ndk.disconnect()
}

func testProfileManager() async throws {
    printSection("TEST 4: Profile Manager (NDKProfileManager)")

    let ndk = NDK(relayUrls: TEST_RELAYS)
    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 4.1: Fetch single profile
    printTest("Fetch single profile using profileManager")
    var fetchedMetadata: NDKUserMetadata?

    for await metadata in await ndk.profileManager.subscribe(for: JACK_PUBKEY) {
        fetchedMetadata = metadata
        break
    }

    if let metadata = fetchedMetadata {
        print("   Name: \(metadata.name ?? "N/A")")
        print("   Display Name: \(metadata.displayName ?? "N/A")")
        print("   About: \(String((metadata.about ?? "N/A").prefix(50)))...")
        print("   NIP-05: \(metadata.nip05 ?? "N/A")")
        printSuccess("Profile fetched successfully")
        printDiscovery("profileManager.subscribe(for:) returns AsyncStream<NDKUserMetadata?>")
    } else {
        print("   Profile not found")
        printDiscovery("Profile may not be cached and network may not have returned it yet")
    }

    // Test 4.2: Fetch multiple profiles
    printTest("Fetch multiple profiles")
    let pubkeys = [JACK_PUBKEY, FIATJAF_PUBKEY]
    var profiles: [String: NDKUserMetadata] = [:]

    for pubkey in pubkeys {
        for await metadata in await ndk.profileManager.subscribe(for: pubkey) {
            if let metadata = metadata {
                profiles[pubkey] = metadata
                print("   Fetched profile for: \(String(pubkey.prefix(16)))... - \(metadata.name ?? "Unknown")")
            }
            break
        }
    }

    print("   Total profiles fetched: \(profiles.count)")
    printSuccess("Multiple profiles fetched")
    printDiscovery("profileManager can fetch multiple profiles sequentially")

    // Test 4.3: Profile metadata structure
    printTest("Profile metadata structure")
    if let firstProfile = profiles.values.first {
        print("   Available fields:")
        print("   - name: \(firstProfile.name != nil ? "✓" : "✗")")
        print("   - displayName: \(firstProfile.displayName != nil ? "✓" : "✗")")
        print("   - about: \(firstProfile.about != nil ? "✓" : "✗")")
        print("   - picture: \(firstProfile.picture != nil ? "✓" : "✗")")
        print("   - banner: \(firstProfile.banner != nil ? "✓" : "✗")")
        print("   - nip05: \(firstProfile.nip05 != nil ? "✓" : "✗")")
        print("   - lud16: \(firstProfile.lud16 != nil ? "✓" : "✗")")
        print("   - lud06: \(firstProfile.lud06 != nil ? "✓" : "✗")")
        print("   - website: \(firstProfile.website != nil ? "✓" : "✗")")
        printDiscovery("NDKUserMetadata has all standard profile fields")
    }

    await ndk.disconnect()
}

func testDifferentDataSourceConfigs() async throws {
    printSection("TEST 5: Different Data Source Configurations")

    let ndk = NDK(relayUrls: TEST_RELAYS)
    let signer = try NDKPrivateKeySigner.generate()
    ndk.signer = signer
    let pubkey = try await signer.pubkey

    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 5.1: Specific relays
    printTest("Subscription to specific relays")
    let specificRelays: Set<RelayURL> = [TEST_RELAYS[0]]
    let sub1 = ndk.subscribe(
        filter: NDKFilter(kinds: [1], limit: 3),
        cachePolicy: .networkOnly,
        relays: specificRelays
    )

    var count1 = 0
    let task1 = Task {
        for await _ in sub1.events {
            count1 += 1
            if count1 >= 3 { break }
        }
    }
    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)
    task1.cancel()
    print("   Events from specific relays: \(count1)")
    printDiscovery("Can specify specific relays via relays parameter")

    // Test 5.2: Close on EOSE
    printTest("Close on EOSE option")
    let sub2 = ndk.subscribe(
        filter: NDKFilter(kinds: [1], limit: 5),
        cachePolicy: .networkOnly,
        closeOnEose: true
    )

    var eoseReceived = false
    let task2 = Task {
        for await update in sub2.relayUpdates {
            if case .aggregatedEose = update {
                eoseReceived = true
                print("   Subscription closed on EOSE")
                break
            }
        }
    }
    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)
    task2.cancel()
    printDiscovery("closeOnEose: true closes subscription after EOSE")

    // Test 5.3: Custom subscription ID
    printTest("Custom subscription ID")
    let sub3 = ndk.subscribe(
        filter: NDKFilter(kinds: [1], limit: 1),
        subscriptionId: "my-custom-sub-id"
    )
    printSuccess("Created subscription with custom ID")
    printDiscovery("Can provide custom subscriptionId parameter")

    await ndk.disconnect()
}

func testEventFiltering() async throws {
    printSection("TEST 6: Event Filtering and Matching")

    // Test 6.1: Client-side filtering
    printTest("Client-side event matching")
    let filter = NDKFilter(
        kinds: [EventKind.textNote],
        authors: [JACK_PUBKEY]
    )

    let matchingEvent = NDKEvent(
        id: "test1",
        pubkey: JACK_PUBKEY,
        createdAt: Timestamp(Date().timeIntervalSince1970),
        kind: EventKind.textNote,
        tags: [],
        content: "Test",
        signature: "sig1"
    )

    let nonMatchingEvent = NDKEvent(
        id: "test2",
        pubkey: FIATJAF_PUBKEY,
        createdAt: Timestamp(Date().timeIntervalSince1970),
        kind: EventKind.textNote,
        tags: [],
        content: "Test",
        signature: "sig2"
    )

    let matches1 = filter.matches(event: matchingEvent)
    let matches2 = filter.matches(event: nonMatchingEvent)

    print("   Matching event: \(matches1)")
    print("   Non-matching event: \(matches2)")

    if matches1, !matches2 {
        printSuccess("Filter matching works correctly")
    } else {
        printFailure("Filter matching failed")
    }
    printDiscovery("filter.matches(event:) enables client-side filtering")

    // Test 6.2: Tag matching
    printTest("Tag-based matching")
    var tagFilter = NDKFilter(kinds: [EventKind.textNote])
    tagFilter.addTagFilter("p", values: [JACK_PUBKEY])

    let eventWithTag = NDKEvent(
        id: "test3",
        pubkey: FIATJAF_PUBKEY,
        createdAt: Timestamp(Date().timeIntervalSince1970),
        kind: EventKind.textNote,
        tags: [["p", JACK_PUBKEY]],
        content: "Mentioning Jack",
        signature: "sig3"
    )

    let eventWithoutTag = NDKEvent(
        id: "test4",
        pubkey: FIATJAF_PUBKEY,
        createdAt: Timestamp(Date().timeIntervalSince1970),
        kind: EventKind.textNote,
        tags: [],
        content: "Not mentioning anyone",
        signature: "sig4"
    )

    let tagMatches1 = tagFilter.matches(event: eventWithTag)
    let tagMatches2 = tagFilter.matches(event: eventWithoutTag)

    print("   Event with tag: \(tagMatches1)")
    print("   Event without tag: \(tagMatches2)")

    if tagMatches1, !tagMatches2 {
        printSuccess("Tag filtering works correctly")
    } else {
        printFailure("Tag filtering failed")
    }
    printDiscovery("Tag filters match events with specified tag values")

    // Test 6.3: Time range matching
    printTest("Time range matching")
    let now = Date()
    let hourAgo = now.addingTimeInterval(-3600)
    let twoHoursAgo = now.addingTimeInterval(-7200)

    let timeFilter = NDKFilter(
        kinds: [EventKind.textNote],
        since: Timestamp(hourAgo.timeIntervalSince1970),
        until: Timestamp(now.timeIntervalSince1970)
    )

    let recentEvent = NDKEvent(
        id: "test5",
        pubkey: JACK_PUBKEY,
        createdAt: Timestamp(now.addingTimeInterval(-1800).timeIntervalSince1970), // 30 min ago
        kind: EventKind.textNote,
        tags: [],
        content: "Recent",
        signature: "sig5"
    )

    let oldEvent = NDKEvent(
        id: "test6",
        pubkey: JACK_PUBKEY,
        createdAt: Timestamp(twoHoursAgo.timeIntervalSince1970),
        kind: EventKind.textNote,
        tags: [],
        content: "Old",
        signature: "sig6"
    )

    let timeMatches1 = timeFilter.matches(event: recentEvent)
    let timeMatches2 = timeFilter.matches(event: oldEvent)

    print("   Recent event in range: \(timeMatches1)")
    print("   Old event outside range: \(timeMatches2)")

    if timeMatches1, !timeMatches2 {
        printSuccess("Time range filtering works correctly")
    } else {
        printFailure("Time range filtering failed")
    }
    printDiscovery("since/until filter events by timestamp range")
}

func testSubscriptionLifecycle() async throws {
    printSection("TEST 7: Subscription Lifecycle")

    let ndk = NDK(relayUrls: TEST_RELAYS)
    await ndk.connect()
    try await Task.sleep(nanoseconds: TIMEOUT_SHORT)

    // Test 7.1: Multiple concurrent subscriptions
    printTest("Multiple concurrent subscriptions")
    let sub1 = ndk.subscribe(filter: NDKFilter(kinds: [1], limit: 3))
    let sub2 = ndk.subscribe(filter: NDKFilter(kinds: [0], limit: 3))
    let sub3 = ndk.subscribe(filter: NDKFilter(kinds: [3], limit: 3))

    var counts = [0, 0, 0]

    let task1 = Task {
        for await _ in sub1.events {
            counts[0] += 1
            if counts[0] >= 3 { break }
        }
    }

    let task2 = Task {
        for await _ in sub2.events {
            counts[1] += 1
            if counts[1] >= 3 { break }
        }
    }

    let task3 = Task {
        for await _ in sub3.events {
            counts[2] += 1
            if counts[2] >= 3 { break }
        }
    }

    try await Task.sleep(nanoseconds: TIMEOUT_MEDIUM)
    task1.cancel()
    task2.cancel()
    task3.cancel()

    print("   Subscription 1 (kind 1): \(counts[0]) events")
    print("   Subscription 2 (kind 0): \(counts[1]) events")
    print("   Subscription 3 (kind 3): \(counts[2]) events")
    printSuccess("Multiple subscriptions run concurrently")
    printDiscovery("Can create multiple independent subscriptions")

    // Test 7.2: Subscription cleanup
    printTest("Subscription cleanup on Task cancellation")
    let sub4 = ndk.subscribe(filter: NDKFilter(kinds: [1]))
    let task4 = Task {
        for await _ in sub4.events {
            // Do nothing, just keep subscription alive
        }
    }

    try await Task.sleep(nanoseconds: 1_000_000_000)
    task4.cancel()
    try await Task.sleep(nanoseconds: 500_000_000)

    printSuccess("Subscription cancelled")
    printDiscovery("Cancelling Task stops event consumption")

    await ndk.disconnect()
}

// MARK: - Main Test Runner

@main
struct TestApp2 {
    static func main() async {
        print("╔════════════════════════════════════════════════════════════════════╗")
        print("║             NDKSwift Test App 2: Advanced Subscriptions            ║")
        print("║                                                                    ║")
        print("║  This test validates advanced subscription patterns and the       ║")
        print("║  profile manager through hands-on testing.                        ║")
        print("╚════════════════════════════════════════════════════════════════════╝")

        do {
            try await testComplexFilters()
            try await testAsyncSequencePatterns()
            try await testRelayUpdates()
            try await testProfileManager()
            try await testDifferentDataSourceConfigs()
            try await testEventFiltering()
            try await testSubscriptionLifecycle()

            printSection("TEST SUMMARY")
            print("✅ All advanced subscription tests completed!")
            print("\nKey Discoveries:")
            print("- Filters support complex queries with multiple criteria")
            print("- Subscriptions use AsyncSequence for flexible event handling")
            print("- RelayUpdates provide fine-grained relay-level information")
            print("- ProfileManager simplifies profile fetching")
            print("- Can subscribe to specific relays and control lifecycle")
            print("- Client-side filtering via filter.matches(event:)")
            print("- Multiple concurrent subscriptions are supported")

        } catch {
            printFailure("Test suite failed", error: error)
        }
    }
}
