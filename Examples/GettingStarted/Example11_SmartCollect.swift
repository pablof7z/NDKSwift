import Foundation
import NDKSwift

/// Example demonstrating the improved collect() method with smart EOSE handling
///
/// The new collect() implementation:
/// - Returns immediately when all requested event IDs are found
/// - Returns immediately when the limit is reached
/// - Uses progressive timeout based on percentage of relays that have sent EOSE
/// - Waits for all relays when fetching replaceable events (profiles, contact lists, etc.)

@main
struct SmartCollectExample {
    static func main() async throws {
        // Initialize NDK
        let ndk = NDK()

        // Add some relays
        await ndk.addRelay("wss://relay.damus.io")
        await ndk.addRelay("wss://nos.lol")
        await ndk.addRelay("wss://relay.primal.net")

        // Connect to all relays (including outbox relays)
        await ndk.connect()

        // Wait for connections
        try await Task.sleep(nanoseconds: 1_000_000_000)

        print("Connected to \(await ndk.pool.connectedRelays().count) relays\n")

        // Example 1: Fetch specific events by ID
        print("Example 1: Fetching specific events by ID")
        await fetchSpecificEvents(ndk: ndk)

        // Example 2: Fetch with limit
        print("\nExample 2: Fetching with limit")
        await fetchWithLimit(ndk: ndk)

        // Example 3: Fetch user profiles (replaceable events)
        print("\nExample 3: Fetching user profiles")
        await fetchUserProfiles(ndk: ndk)

        // Example 4: Fetch relay lists with smart timeout
        print("\nExample 4: Fetching relay lists")
        await fetchRelayLists(ndk: ndk)
    }

    static func fetchSpecificEvents(ndk: NDK) async {
        // When fetching by IDs, collect() returns as soon as all IDs are found
        let eventIds = [
            "7c8b666830d89179330e36e8f2674f7638c59030e7cf019068efba210c231277",
            "8e68cdfa8301c0b78f13671cd5962e4e8930b630fccf5a962a42f75296ac083e",
        ]

        let filter = NDKFilter(ids: eventIds)
        let dataSource = ndk.subscribe(filter: filter, closeOnEose: true)

        let startTime = Date()
        let events = await dataSource.collect()
        let elapsed = Date().timeIntervalSince(startTime)

        print("  Found \(events.count)/\(eventIds.count) events in \(String(format: "%.2f", elapsed))s")

        // This will return immediately after finding all requested IDs,
        // even if some relays haven't sent EOSE yet
    }

    static func fetchWithLimit(ndk: NDK) async {
        // When fetching with a limit, collect() returns as soon as the limit is reached
        let filter = NDKFilter(
            kinds: [EventKind.textNote],
            limit: 10
        )

        let dataSource = ndk.subscribe(filter: filter, closeOnEose: true)

        let startTime = Date()
        let events = await dataSource.collect()
        let elapsed = Date().timeIntervalSince(startTime)

        print("  Collected \(events.count) events in \(String(format: "%.2f", elapsed))s")

        // This returns immediately after receiving 10 events,
        // without waiting for all relays to finish
    }

    static func fetchUserProfiles(ndk: NDK) async {
        // For replaceable events, collect() waits for all relays to ensure
        // we get the most recent version
        let authors = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", // fiatjaf
        ]

        let filter = NDKFilter(
            authors: authors,
            kinds: [EventKind.profile]
        )

        let dataSource = ndk.subscribe(filter: filter, closeOnEose: true)

        let startTime = Date()
        let events = await dataSource.collect()
        let elapsed = Date().timeIntervalSince(startTime)

        print("  Collected \(events.count) profile events in \(String(format: "%.2f", elapsed))s")

        // Group by author and find most recent
        var profilesByAuthor: [String: NDKEvent] = [:]
        for event in events {
            if let existing = profilesByAuthor[event.pubkey] {
                if event.createdAt > existing.createdAt {
                    profilesByAuthor[event.pubkey] = event
                }
            } else {
                profilesByAuthor[event.pubkey] = event
            }
        }

        print("  Most recent profiles:")
        for (author, event) in profilesByAuthor {
            if let profile = try? NDKUserProfile.from(event: event) {
                print("    \(author.prefix(8)): \(profile.name ?? "unnamed")")
            }
        }
    }

    static func fetchRelayLists(ndk: NDK) async {
        // Demonstrate progressive timeout:
        // - If 50% of relays respond quickly, timeout reduces
        // - If 75% respond, timeout reduces even more
        // - At 100%, returns immediately

        let filter = NDKFilter(
            authors: ["82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"],
            kinds: [EventKind.relayList]
        )

        let dataSource = ndk.subscribe(filter: filter, closeOnEose: true)

        print("  Fetching relay list with progressive timeout...")
        let startTime = Date()
        let events = await dataSource.collect(timeout: 5.0)
        let elapsed = Date().timeIntervalSince(startTime)

        print("  Found \(events.count) relay list(s) in \(String(format: "%.2f", elapsed))s")

        if let relayListEvent = events.first {
            let relayList = NDKRelayList.fromEvent(relayListEvent)
            print("  User has \(relayList.relayURLs.count) relays:")
            for url in relayList.relayURLs.prefix(5) {
                print("    - \(url)")
            }
            if relayList.relayURLs.count > 5 {
                print("    ... and \(relayList.relayURLs.count - 5) more")
            }
        }
    }
}

// Run with: swift run --package-path Examples SmartCollectExample
