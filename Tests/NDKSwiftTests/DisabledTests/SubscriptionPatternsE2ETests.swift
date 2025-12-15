@testable import NDKSwiftCore
import XCTest

final class SubscriptionPatternsE2ETests: XCTestCase {
    let relayURLs = [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
    ]

    override func setUp() async throws {
        try await super.setUp()
        NDKLogger.setLogLevel(.debug)
        NDKLogger.setLogNetworkTraffic(false)
    }

    func testObserveAPIPatterns() async throws {
        let startTime = Date()
        print("[\(timestamp())] Starting subscription patterns E2E test")

        let ndk = NDK(cache: MemoryCache())
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        ndk.signer = signer

        // Connect to relays
        for relay in relayURLs {
            await ndk.addRelay(relay)
        }
        await ndk.connect()
        await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)

        // Test 1: Real-time subscription (maxAge = 0)
        print("\n[\(timestamp())] Test 1: Real-time subscription")
        print("==========================================")

        let realtimeFilter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.textNote],
            limit: 10
        )

        let realtimeDataSource = ndk.subscribe(filter: realtimeFilter, maxAge: 0)
        var realtimeEvents: [NDKEvent] = []

        // Start observing in background
        let observerTask = Task {
            print("[\(timestamp())] Real-time observer started")
            for await event in realtimeDataSource.events {
                print("[\(timestamp())] Real-time event received: \(String(event.id.prefix(8)))...")
                realtimeEvents.append(event)
                if realtimeEvents.count >= 3 {
                    break
                }
            }
        }

        // Give subscription time to establish
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Publish events while subscription is active
        print("[\(timestamp())] Publishing events...")
        for i in 1 ... 3 {
            let event = try await NDKEventBuilder(ndk: ndk)
                .content("Real-time test #\(i) at \(Date())")
                .kind(EventKind.textNote)
                .tag(["test", "realtime"])
                .build()

            _ = try await ndk.publish(event)
            print("[\(timestamp())] Published event #\(i)")
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s between events
        }

        // Wait for events to be received
        try await Task.sleep(nanoseconds: 2_000_000_000)
        observerTask.cancel()

        print("[\(timestamp())] Real-time events received: \(realtimeEvents.count)")
        XCTAssertGreaterThan(realtimeEvents.count, 0, "Should receive real-time events")

        // Test 2: One-shot fetch with cache (maxAge > 0)
        print("\n[\(timestamp())] Test 2: One-shot fetch with cache")
        print("=============================================")

        let cacheFetchFilter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.textNote],
            limit: 10,
            tags: ["test": ["realtime"]]
        )

        let cacheDataSource = ndk.subscribe(
            filter: cacheFetchFilter,
            maxAge: 3600, // 1 hour
            cachePolicy: .cacheWithNetwork
        )

        var cachedEvents: [NDKEvent] = []
        let fetchTimeout = Date().addingTimeInterval(3.0)

        print("[\(timestamp())] Fetching with cache policy...")
        for await event in cacheDataSource.events {
            cachedEvents.append(event)
            print("[\(timestamp())] Cached/fetched event: \(String(event.id.prefix(8)))...")

            if cachedEvents.count >= 3 || Date() > fetchTimeout {
                break
            }
        }

        print("[\(timestamp())] Events from cache/network: \(cachedEvents.count)")
        XCTAssertGreaterThan(cachedEvents.count, 0, "Should fetch events")

        // Test 3: Multiple concurrent subscriptions
        print("\n[\(timestamp())] Test 3: Multiple concurrent subscriptions")
        print("=================================================")

        // Create different filters
        let filter1 = NDKFilter(kinds: [EventKind.metadata], limit: 5)
        let filter2 = NDKFilter(kinds: [EventKind.textNote], limit: 5)
        let filter3 = NDKFilter(kinds: [EventKind.contacts], limit: 5)

        let dataSource1 = ndk.subscribe(filter: filter1, maxAge: 3600)
        let dataSource2 = ndk.subscribe(filter: filter2, maxAge: 3600)
        let dataSource3 = ndk.subscribe(filter: filter3, maxAge: 3600)

        var results = (metadata: 0, textNotes: 0, contacts: 0)

        // Run concurrent fetches
        print("[\(timestamp())] Starting concurrent fetches...")

        await withTaskGroup(of: Void.self) { group in
            // Task 1: Metadata
            group.addTask {
                let timeout = Date().addingTimeInterval(3.0)
                for await _ in dataSource1.events {
                    results.metadata += 1
                    if results.metadata >= 2 || Date() > timeout {
                        break
                    }
                }
            }

            // Task 2: Text notes
            group.addTask {
                let timeout = Date().addingTimeInterval(3.0)
                for await _ in dataSource2.events {
                    results.textNotes += 1
                    if results.textNotes >= 2 || Date() > timeout {
                        break
                    }
                }
            }

            // Task 3: Contacts
            group.addTask {
                let timeout = Date().addingTimeInterval(3.0)
                for await _ in dataSource3.events {
                    results.contacts += 1
                    if results.contacts >= 2 || Date() > timeout {
                        break
                    }
                }
            }

            await group.waitForAll()
        }

        print("[\(timestamp())] Concurrent fetch results:")
        print("   Metadata events: \(results.metadata)")
        print("   Text note events: \(results.textNotes)")
        print("   Contact events: \(results.contacts)")

        // Test 4: Complex filter with tags
        print("\n[\(timestamp())] Test 4: Complex filter with tags")
        print("===========================================")

        // Publish some tagged events
        let testTag = "e2e-test-\(Int.random(in: 1000 ... 9999))"

        for i in 1 ... 3 {
            let event = try await NDKEventBuilder(ndk: ndk)
                .content("Tagged event #\(i)")
                .kind(EventKind.textNote)
                .tag(["t", testTag])
                .tag(["category", "test"])
                .build()

            _ = try await ndk.publish(event)
        }

        // Wait for propagation
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Query with tag filter
        let tagFilter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.textNote],
            limit: 10,
            tags: ["t": [testTag]]
        )

        let tagDataSource = ndk.subscribe(filter: tagFilter, maxAge: 3600)
        var taggedEvents: [NDKEvent] = []

        print("[\(timestamp())] Fetching events with tag '\(testTag)'...")
        let tagTimeout = Date().addingTimeInterval(3.0)

        for await event in tagDataSource.events {
            taggedEvents.append(event)
            print("[\(timestamp())] Found tagged event: \(String(event.id.prefix(8)))...")

            if taggedEvents.count >= 3 || Date() > tagTimeout {
                break
            }
        }

        print("[\(timestamp())] Tagged events found: \(taggedEvents.count)")
        XCTAssertGreaterThan(taggedEvents.count, 0, "Should find tagged events")

        // Verify tags
        for event in taggedEvents {
            let hasTag = event.tags.contains { tag in
                tag.count >= 2 && tag[0] == "t" && tag[1] == testTag
            }
            XCTAssertTrue(hasTag, "Event should have the test tag")
        }

        // Test 5: Cache-only query
        print("\n[\(timestamp())] Test 5: Cache-only query")
        print("=====================================")

        let cacheOnlyDataSource = ndk.subscribe(
            filter: tagFilter,
            maxAge: 3600,
            cachePolicy: .cacheOnly
        )

        var cacheOnlyEvents: [NDKEvent] = []
        let cacheOnlyTimeout = Date().addingTimeInterval(1.0)

        print("[\(timestamp())] Querying cache only...")
        for await event in cacheOnlyDataSource.events {
            cacheOnlyEvents.append(event)
            if cacheOnlyEvents.count >= 10 || Date() > cacheOnlyTimeout {
                break
            }
        }

        print("[\(timestamp())] Cache-only results: \(cacheOnlyEvents.count) events")

        // Cleanup
        await ndk.disconnect()

        let totalTime = Date().timeIntervalSince(startTime)
        print("\n[\(timestamp())] Test completed in \(String(format: "%.2f", totalTime))s")
    }

    func testSubscriptionWithTransform() async throws {
        print("[\(timestamp())] Starting subscription with transform E2E test")

        let ndk = NDK(cache: MemoryCache())

        for relay in relayURLs {
            await ndk.addRelay(relay)
        }
        await ndk.connect()
        await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)

        // Define a transform for profile events
        struct ProfileSummary {
            let pubkey: String
            let name: String?
            let about: String?
            let picture: String?
        }

        let profileFilter = NDKFilter(
            kinds: [EventKind.metadata],
            limit: 10
        )

        // Create data source with transform
        let profileDataSource = ndk.subscribe(
            filter: profileFilter,
            maxAge: 3600,
            transform: { (event: NDKEvent) -> ProfileSummary? in
                guard event.kind == EventKind.metadata,
                      let profileData = try? JSONCoding.decode(NDKUserProfile.self, from: event.content)
                else {
                    return nil
                }

                return ProfileSummary(
                    pubkey: event.pubkey,
                    name: profileData.name,
                    about: profileData.about,
                    picture: profileData.picture
                )
            }
        )

        var profiles: [ProfileSummary] = []
        let timeout = Date().addingTimeInterval(5.0)

        print("[\(timestamp())] Fetching and transforming profile events...")
        for await profile in profileDataSource.events {
            profiles.append(profile)
            print("[\(timestamp())] Profile: \(profile.name ?? "unnamed") (\(String(profile.pubkey.prefix(8)))...)")

            if profiles.count >= 5 || Date() > timeout {
                break
            }
        }

        print("[\(timestamp())] Transformed profiles: \(profiles.count)")
        XCTAssertGreaterThan(profiles.count, 0, "Should fetch and transform profiles")

        await ndk.disconnect()
        print("[\(timestamp())] Transform test completed")
    }

    private func timestamp() -> String {
        return DateFormatters.custom(format: "HH:mm:ss.SSS").string(from: Date())
    }
}
