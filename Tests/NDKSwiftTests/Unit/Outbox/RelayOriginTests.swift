@testable import NDKSwiftCore
import XCTest

final class RelayOriginTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var cache: MemoryCache!

    override func setUp() async throws {
        cache = MemoryCache()
        signer = try NDKPrivateKeySigner.generate()
        ndk = NDK(
            relayURLs: [
                "wss://explicit1.example.com",
                "wss://explicit2.example.com",
            ],
            signer: signer,
            cache: cache
        )
    }

    override func tearDown() async throws {
        await ndk?.disconnect()
        ndk = nil
        signer = nil
        cache = nil
    }

    // MARK: - Relay Origin Tests

    func testOutboxRelaysAutoConnect() async throws {
        // Verify that outbox relays are automatically added on connect
        XCTAssertTrue(ndk.outboxConfig.outboxRelays.contains("wss://purplepag.es"))

        // Connect and verify outbox relays are added
        await ndk.connect()

        // Wait a bit for connections to establish
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Check that purplepag.es was added
        let relays = await ndk.pool.relays
        let purplePages = relays.first { $0.url == "wss://purplepag.es" }

        XCTAssertNotNil(purplePages, "purplepag.es should be in the relay pool")

        // Verify it has the correct origin
        if let relay = purplePages {
            let origin = await relay.origin
            XCTAssertEqual(origin, .outboxConfig, "purplepag.es should have outboxConfig origin")
        }
    }

    func testExplicitRelayOrigin() async throws {
        // Verify initial relays have explicit origin
        await ndk.initializeRelays()

        let relays = await ndk.pool.relays

        for relayUrl in ["wss://explicit1.example.com", "wss://explicit2.example.com"] {
            let relay = relays.first { $0.url == relayUrl }
            XCTAssertNotNil(relay, "\(relayUrl) should be in pool")

            if let relay = relay {
                let origin = await relay.origin
                XCTAssertEqual(origin, .explicit, "\(relayUrl) should have explicit origin")
            }
        }
    }

    func testFallbackRelaySelection() async throws {
        // Set up a user relay list for current user
        let userPubkey = try await signer.pubkey
        try await setupMockRelayList(
            for: userPubkey,
            readRelays: ["wss://user-read1.com", "wss://user-read2.com"],
            writeRelays: ["wss://user-write1.com"]
        )

        // Add some non-explicit relays to the pool (e.g., from outbox discovery)
        await ndk.pool.addRelay("wss://discovered1.com", origin: .outbox(authorPubkey: "some_author"))
        await ndk.pool.addRelay("wss://discovered2.com", origin: .outbox(authorPubkey: "another_author"))

        // Create relay selector
        let relaySelector = NDKRelaySelector(ndk: ndk, tracker: ndk.outbox, ranker: ndk.relayRanker)

        // Create an event that will need fallback relays
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test fallback selection")
            .build()

        // Select relays for publishing
        let selection = await relaySelector.selectRelaysForPublishing(event: event)

        // Verify fallback only includes explicit + user relays
        for relay in selection.relays {
            let isExplicit = ["wss://explicit1.example.com", "wss://explicit2.example.com"].contains(relay)
            let isUserRelay = ["wss://user-read1.com", "wss://user-read2.com", "wss://user-write1.com"].contains(relay)
            let isValid = isExplicit || isUserRelay

            XCTAssertTrue(isValid, "Fallback relay \(relay) should be either explicit or from user's relay list")
        }

        // Verify discovered relays are NOT in fallback
        XCTAssertFalse(selection.relays.contains("wss://discovered1.com"), "Discovered relays should not be in fallback")
        XCTAssertFalse(selection.relays.contains("wss://discovered2.com"), "Discovered relays should not be in fallback")
    }

    func testGetCurrentUserRelayUrls() async throws {
        // Set up relay list for current user
        let userPubkey = try await signer.pubkey
        try await setupMockRelayList(
            for: userPubkey,
            readRelays: ["wss://user-read1.com", "wss://user-read2.com"],
            writeRelays: ["wss://user-write1.com", "wss://user-write2.com"]
        )

        // Get current user relays
        let userRelays = await ndk.pool.getCurrentUserRelayUrls()

        XCTAssertEqual(userRelays.count, 4, "Should have all user relays")
        XCTAssertTrue(userRelays.contains("wss://user-read1.com"))
        XCTAssertTrue(userRelays.contains("wss://user-read2.com"))
        XCTAssertTrue(userRelays.contains("wss://user-write1.com"))
        XCTAssertTrue(userRelays.contains("wss://user-write2.com"))
    }

    func testGetCurrentUserRelayUrlsNoSigner() async throws {
        // Create NDK without signer
        let ndkNoSigner = NDK(cache: MemoryCache())

        // Should return empty set
        let userRelays = await ndkNoSigner.pool.getCurrentUserRelayUrls()
        XCTAssertTrue(userRelays.isEmpty, "Should return empty set when no signer")
    }

    // MARK: - Helper Methods

    private func setupMockRelayList(for _: String, readRelays: [String], writeRelays: [String]) async throws {
        // Create relay info items
        var relayInfos: [NDKRelayInfo] = []

        for url in readRelays {
            relayInfos.append(NDKRelayInfo(url: url, read: true, write: false))
        }

        for url in writeRelays {
            relayInfos.append(NDKRelayInfo(url: url, read: false, write: true))
        }

        // Create relay list using NDKEventBuilder
        let relayListEvent = try! await NDKEventBuilder(ndk: ndk)
            .kind(EventKind.relayList)
            .tags(relayInfos.map { relayInfo in
                var tag = ["r", relayInfo.url]
                if relayInfo.read, !relayInfo.write {
                    tag.append("read")
                } else if !relayInfo.read, relayInfo.write {
                    tag.append("write")
                }
                return tag
            })
            .content("")
            .build(signer: signer)

        // Cache the event
        try await cache.saveEvent(relayListEvent)

        // The outbox tracker will automatically pick up the cached event
        // when it queries for the user's relay list
    }
}
