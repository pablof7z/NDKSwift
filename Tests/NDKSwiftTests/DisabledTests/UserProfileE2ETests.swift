@testable import NDKSwiftCore
import XCTest

final class UserProfileE2ETests: XCTestCase {
    let relayURLs = [
        "wss://relay.damus.io",
        "wss://relay.nostr.band",
        "wss://nos.lol",
    ]

    override func setUp() async throws {
        try await super.setUp()

        // Configure logging for debugging
        NDKLogger.logLevel = .debug
        NDKLogger.logNetworkTraffic = false // Too verbose for profile tests
    }

    override func tearDown() async throws {
        try await super.tearDown()
    }

    func testUserProfileCreateUpdateAndFetch() async throws {
        let startTime = Date()
        print("[\(timestamp())] Starting user profile E2E test")

        // Create two NDK instances - publisher and fetcher
        let publisherNDK = NDK(cache: MemoryCache())
        let fetcherNDK = NDK(cache: MemoryCache())

        // Create signer for publisher
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        publisherNDK.signer = signer

        print("[\(timestamp())] Generated keypair, pubkey: \(pubkey)")

        // Connect both instances to relays
        print("[\(timestamp())] Connecting to relays...")
        for relayURL in relayURLs {
            await publisherNDK.addRelay(relayURL)
            await fetcherNDK.addRelay(relayURL)
        }
        await publisherNDK.connect()
        await fetcherNDK.connect()

        // Wait for connections
        print("[\(timestamp())] Waiting for relay connections...")
        let publisherConnected = await publisherNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        let fetcherConnected = await fetcherNDK.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)

        guard publisherConnected > 0 && fetcherConnected > 0 else {
            XCTFail("Failed to connect to relays")
            return
        }

        let connectTime = Date()
        print("[\(timestamp())] Connected to relays in \(connectTime.timeIntervalSince(startTime))s")

        // Step 1: Create and publish initial profile
        print("[\(timestamp())] Creating initial user profile...")
        let initialMetadata = [
            "name": "Test User \(Int.random(in: 1000 ... 9999))",
            "display_name": "Test Display Name",
            "about": "This is a test profile created by NDKSwift E2E tests",
            "picture": "https://example.com/avatar.jpg",
            "banner": "https://example.com/banner.jpg",
            "nip05": "testuser@example.com",
            "lud16": "testuser@getalby.com",
            "website": "https://example.com",
        ]

        // Create metadata event (kind 0)
        let profileContent = try JSONCoding.encodeToString(initialMetadata)
        let profileEvent = try await NDKEventBuilder(ndk: publisherNDK)
            .content(profileContent)
            .kind(0) // Metadata kind
            .build()

        print("[\(timestamp())] Publishing initial profile...")
        let publishStart = Date()
        let publishedRelays = try await publisherNDK.publish(profileEvent)
        let publishTime = Date()
        print("[\(timestamp())] Profile published to \(publishedRelays.count) relays in \(publishTime.timeIntervalSince(publishStart))s")

        // Step 2: Fetch the profile from another instance
        print("[\(timestamp())] Fetching profile from another NDK instance...")
        let fetchStart = Date()

        // Give relays time to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Fetch profile using a filter
        let profileFilter = NDKFilter(
            authors: [pubkey],
            kinds: [0] // Metadata kind
        )

        let fetchedMetadata = try await fetchProfileMetadata(ndk: fetcherNDK, filter: profileFilter, pubkey: pubkey)
        let fetchTime = Date()
        print("[\(timestamp())] Profile fetched in \(fetchTime.timeIntervalSince(fetchStart))s")

        // Verify initial profile data
        XCTAssertNotNil(fetchedMetadata, "Should fetch profile successfully")
        if let metadata = fetchedMetadata {
            print("[\(timestamp())] Verifying initial profile data...")
            XCTAssertEqual(metadata.name, initialMetadata["name"])
            XCTAssertEqual(metadata.displayName, initialMetadata["display_name"])
            XCTAssertEqual(metadata.about, initialMetadata["about"])
            XCTAssertEqual(metadata.picture, initialMetadata["picture"])
            XCTAssertEqual(metadata.banner, initialMetadata["banner"])
            XCTAssertEqual(metadata.nip05, initialMetadata["nip05"])
            XCTAssertEqual(metadata.lud16, initialMetadata["lud16"])
            XCTAssertEqual(metadata.website, initialMetadata["website"])
            print("[\(timestamp())] Initial profile verification successful")
        }

        // Step 3: Update the profile
        print("[\(timestamp())] Updating user profile...")
        let updatedMetadata = [
            "name": "Updated Test User",
            "display_name": "Updated Display Name",
            "about": "This profile has been updated by NDKSwift E2E tests",
            "picture": "https://example.com/new-avatar.jpg",
            "banner": "https://example.com/new-banner.jpg",
            "nip05": "updateduser@example.com",
            "lud16": "updateduser@getalby.com",
            "website": "https://newexample.com",
        ]

        // Create updated metadata event
        let updateContent = try JSONCoding.encodeToString(updatedMetadata)
        let updateEvent = try await NDKEventBuilder(ndk: publisherNDK)
            .content(updateContent)
            .kind(0) // Metadata kind
            .build()

        print("[\(timestamp())] Publishing updated profile...")
        let updateStart = Date()
        let updateRelays = try await publisherNDK.publish(updateEvent)
        let updateTime = Date()
        print("[\(timestamp())] Profile update published to \(updateRelays.count) relays in \(updateTime.timeIntervalSince(updateStart))s")

        // Step 4: Fetch the updated profile
        print("[\(timestamp())] Fetching updated profile...")

        // Give relays time to propagate the update
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        let fetchUpdateStart = Date()
        let updatedFetchedMetadata = try await fetchProfileMetadata(ndk: fetcherNDK, filter: profileFilter, pubkey: pubkey)
        let fetchUpdateTime = Date()
        print("[\(timestamp())] Updated profile fetched in \(fetchUpdateTime.timeIntervalSince(fetchUpdateStart))s")

        // Verify updated profile data
        XCTAssertNotNil(updatedFetchedMetadata, "Should fetch updated profile successfully")
        if let metadata = updatedFetchedMetadata {
            print("[\(timestamp())] Verifying updated profile data...")
            XCTAssertEqual(metadata.name, updatedMetadata["name"])
            XCTAssertEqual(metadata.displayName, updatedMetadata["display_name"])
            XCTAssertEqual(metadata.about, updatedMetadata["about"])
            XCTAssertEqual(metadata.picture, updatedMetadata["picture"])
            XCTAssertEqual(metadata.banner, updatedMetadata["banner"])
            XCTAssertEqual(metadata.nip05, updatedMetadata["nip05"])
            XCTAssertEqual(metadata.lud16, updatedMetadata["lud16"])
            XCTAssertEqual(metadata.website, updatedMetadata["website"])
            print("[\(timestamp())] Updated profile verification successful")
        }

        // Step 5: Test profile caching
        print("[\(timestamp())] Testing profile caching...")
        let cacheStart = Date()

        // Fetch again from cache using cacheOnly policy
        let dataSource = fetcherNDK.subscribe(
            filter: profileFilter,
            maxAge: 3600, // 1 hour
            cachePolicy: .cacheOnly
        )

        let cachedEvents = dataSource.data
        let cacheTime = Date()
        print("[\(timestamp())] Cache check completed in \(cacheTime.timeIntervalSince(cacheStart))s")

        if let cachedEvent = cachedEvents.first {
            let cachedMetadata = NDKUserMetadata(event: cachedEvent)
            XCTAssertEqual(cachedMetadata.name, updatedMetadata["name"])
            print("[\(timestamp())] Profile found in cache")
        } else {
            print("[\(timestamp())] Profile not in cache")
        }

        // Step 6: Test fetching non-existent profile
        print("[\(timestamp())] Testing non-existent profile fetch...")
        let nonExistentSigner = try NDKPrivateKeySigner.generate()
        let nonExistentPubkey = try await nonExistentSigner.pubkey
        let nilStart = Date()

        let nilFilter = NDKFilter(
            authors: [nonExistentPubkey],
            kinds: [0]
        )
        let nilProfile = try await fetchProfileMetadata(ndk: fetcherNDK, filter: nilFilter, pubkey: nonExistentPubkey)
        let nilTime = Date()
        print("[\(timestamp())] Non-existent profile fetch completed in \(nilTime.timeIntervalSince(nilStart))s")
        XCTAssertNil(nilProfile, "Should return nil for non-existent profile")

        // Cleanup
        print("[\(timestamp())] Disconnecting from relays...")
        await publisherNDK.disconnect()
        await fetcherNDK.disconnect()

        let totalTime = Date()
        print("[\(timestamp())] Test completed in \(totalTime.timeIntervalSince(startTime))s")
    }

    func testUserProfileWithMinimalData() async throws {
        print("[\(timestamp())] Starting minimal profile E2E test")

        let ndk = NDK(cache: MemoryCache())
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        ndk.signer = signer

        print("[\(timestamp())] Generated keypair, pubkey: \(pubkey)")

        // Connect to relays
        for relayURL in relayURLs {
            await ndk.addRelay(relayURL)
        }
        await ndk.connect()
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        guard connected > 0 else {
            XCTFail("Failed to connect to relays")
            return
        }

        // Create minimal profile with only name
        print("[\(timestamp())] Creating minimal profile...")
        let minimalMetadata = ["name": "Minimal User"]

        let profileContent = try JSONCoding.encodeToString(minimalMetadata)
        let profileEvent = try await NDKEventBuilder(ndk: ndk)
            .content(profileContent)
            .kind(0)
            .build()

        print("[\(timestamp())] Publishing minimal profile...")
        _ = try await ndk.publish(profileEvent)

        // Give relays time to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Fetch and verify
        print("[\(timestamp())] Fetching minimal profile...")
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [0]
        )
        let fetchedMetadata = try await fetchProfileMetadata(ndk: ndk, filter: filter, pubkey: pubkey)

        XCTAssertNotNil(fetchedMetadata)
        XCTAssertEqual(fetchedMetadata?.name, "Minimal User")
        XCTAssertNil(fetchedMetadata?.displayName)
        XCTAssertNil(fetchedMetadata?.about)
        XCTAssertNil(fetchedMetadata?.picture)

        await ndk.disconnect()
        print("[\(timestamp())] Minimal profile test completed")
    }

    func testUserProfileWithInvalidJSON() async throws {
        print("[\(timestamp())] Starting invalid JSON profile test")

        let ndk = NDK(cache: MemoryCache())
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey
        ndk.signer = signer

        // Connect to relays
        for relayURL in relayURLs {
            await ndk.addRelay(relayURL)
        }
        await ndk.connect()
        await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)

        // Create event with invalid JSON content
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("{invalid json content")
            .kind(0)
            .build()

        print("[\(timestamp())] Publishing invalid profile...")
        _ = try await ndk.publish(event)

        // Give relays time to propagate
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Try to fetch - should handle gracefully
        print("[\(timestamp())] Fetching invalid profile...")
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [0]
        )
        let fetchedMetadata = try await fetchProfileMetadata(ndk: ndk, filter: filter, pubkey: pubkey)

        // Should handle invalid JSON gracefully - NDKUserMetadata returns empty fields
        if let metadata = fetchedMetadata {
            XCTAssertNil(metadata.name, "Should have nil name for invalid JSON")
            XCTAssertNil(metadata.displayName, "Should have nil displayName for invalid JSON")
        }

        await ndk.disconnect()
        print("[\(timestamp())] Invalid JSON test completed")
    }

    // Helper function to fetch profile metadata
    private func fetchProfileMetadata(ndk: NDK, filter: NDKFilter, pubkey _: PublicKey) async throws -> NDKUserMetadata? {
        // Create data source with network-only policy to ensure fresh data
        let dataSource = ndk.subscribe(
            filter: filter,
            maxAge: 0, // Force fresh data
            cachePolicy: .networkOnly
        )

        // Wait for events to arrive
        let startTime = Date()
        let timeout: TimeInterval = 5.0

        while dataSource.data.isEmpty && Date().timeIntervalSince(startTime) < timeout {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        // Get the most recent metadata event
        guard let event = dataSource.data.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            return nil
        }

        // Return NDKUserMetadata which handles JSON parsing internally
        return NDKUserMetadata(event: event)
    }

    private func timestamp() -> String {
        return DateFormatters.custom(format: "HH:mm:ss.SSS").string(from: Date())
    }
}
