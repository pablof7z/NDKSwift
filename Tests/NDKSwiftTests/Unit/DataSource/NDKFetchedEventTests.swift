@testable import NDKSwiftCore
import XCTest

@MainActor
final class NDKFetchedEventTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var cache: MemoryCache!

    override func setUp() async throws {
        cache = MemoryCache()
        signer = try NDKPrivateKeySigner.generate()
        ndk = NDK(
            relayURLs: [
                "wss://relay1.example.com",
                "wss://relay2.example.com",
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

    // MARK: - Identifier Parsing Tests

    func testFetchEventByHexID() async throws {
        let eventId = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"

        let fetched = ndk.fetchEvent(eventId)

        // Should create NDKFetchedEvent without error
        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched.error)
    }

    func testFetchEventByNote1() async throws {
        // note1 encoded event ID
        let note1 = "note19yx9aknwfwxyu3f3x6nr24pygnj0jtzw6x7gttq8k4a5kyp58k9qd78x46"

        let fetched = ndk.fetchEvent(note1)

        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched.error)
    }

    func testFetchEventInvalidIdentifier() async throws {
        let invalidId = "invalid-event-id"

        let fetched = ndk.fetchEvent(invalidId)

        // Should eventually set an error
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(fetched.error)
    }

    // MARK: - Tag Parsing Tests

    func testFetchEventByETag() async throws {
        let eventId = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"
        let tag: Tag = ["e", eventId, "wss://relay.example.com", "reply", "author-pubkey"]

        let fetched = ndk.fetchEvent(tag: tag)

        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched.error)
    }

    func testFetchEventByATag() async throws {
        let tag: Tag = ["a", "30023:pubkey123:article-slug", "wss://relay.example.com"]

        let fetched = ndk.fetchEvent(tag: tag)

        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched.error)
    }

    func testFetchEventByInvalidTag() async throws {
        let tag: Tag = ["x", "invalid"]

        let fetched = ndk.fetchEvent(tag: tag)

        // Should set error for invalid tag type
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(fetched.error)
    }

    func testFetchEventByETagWithMinimalFields() async throws {
        let eventId = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"
        let tag: Tag = ["e", eventId]

        let fetched = ndk.fetchEvent(tag: tag)

        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched.error)
    }

    func testFetchEventByATagInvalidFormat() async throws {
        // Missing components in kind:pubkey:d-tag
        let tag: Tag = ["a", "30023:pubkey"]

        let fetched = ndk.fetchEvent(tag: tag)

        // Should set error for invalid format
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(fetched.error)
    }

    // MARK: - Cache Behavior Tests

    func testCachedNonReplaceableEventSkipsNetwork() async throws {
        // Create a non-replaceable event (kind 1)
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Test event")
            .build()

        // Cache the event
        try await cache.saveEvent(event)

        // Fetch the event
        let fetched = ndk.fetchEvent(event.id)

        // Wait for cache check
        try await Task.sleep(for: .milliseconds(100))

        // Should have event from cache immediately
        XCTAssertNotNil(fetched.event)
        XCTAssertEqual(fetched.event?.id, event.id)
        XCTAssertFalse(fetched.isLoading)
    }

    func testCachedReplaceableEventStillFetchesFromNetwork() async throws {
        // Create a replaceable event (kind 0 - metadata)
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(0)
            .content("{\"name\":\"Test User\"}")
            .build()

        // Cache the event
        try await cache.saveEvent(event)

        // Fetch the event
        let fetched = ndk.fetchEvent(event.id)

        // Wait briefly
        try await Task.sleep(for: .milliseconds(500))

        // Should have cached event immediately
        XCTAssertNotNil(fetched.event)
        XCTAssertEqual(fetched.event?.id, event.id)

        // But should still be loading (checking network for newer version)
        XCTAssertTrue(fetched.isLoading)
    }

    func testUncachedEventStartsLoading() async throws {
        let eventId = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"

        let fetched = ndk.fetchEvent(eventId)

        // Should start loading
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(fetched.isLoading)
        XCTAssertNil(fetched.event)
    }

    // MARK: - Addressable Event Tests

    func testFetchAddressableEventByATag() async throws {
        let pubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let tag: Tag = ["a", "30023:\(pubkey):my-article", "wss://relay.example.com"]

        let fetched = ndk.fetchEvent(tag: tag)

        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched.error)
    }

    // MARK: - Relay Hint Tests

    func testRelayHintExtractedFromTag() async throws {
        let eventId = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"
        let relayHint = "wss://custom-relay.example.com"
        let tag: Tag = ["e", eventId, relayHint]

        let fetched = ndk.fetchEvent(tag: tag)

        XCTAssertNotNil(fetched)
        // Relay hint should be used in subscription
    }

    // MARK: - Error Handling Tests

    func testInvalidBech32LogsError() async throws {
        let invalidBech32 = "note1invalid"

        let fetched = ndk.fetchEvent(invalidBech32)

        // Should log warning but not crash
        XCTAssertNotNil(fetched)
    }

    func testEmptyTagIdentifier() async throws {
        let tag: Tag = ["e", ""]

        let fetched = ndk.fetchEvent(tag: tag)

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(fetched.error)
    }

    // MARK: - Cleanup Tests

    func testDeinitCancelsSubscription() async throws {
        var fetched: NDKFetchedEvent? = ndk.fetchEvent("a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd")

        XCTAssertNotNil(fetched)

        // Deinit should cancel subscription
        fetched = nil

        // Should not leak or crash
        try await Task.sleep(for: .milliseconds(100))
    }
}
