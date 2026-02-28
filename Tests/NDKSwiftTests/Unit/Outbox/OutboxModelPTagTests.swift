@testable import NDKSwiftCore
import XCTest

/// Focused tests for NIP-65 outbox model p-tag publishing behavior
final class OutboxModelPTagTests: XCTestCase {
    func testEventWithFewerThan10PTagsUsesOutboxModel() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(relayURLs: [], signer: signer, cache: cache)

        // Create test event with 3 p-tags (< 10)
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Hello!")
            .tag(["p", "user1_64_char_hex_key_0000000000000000000000000000000000000001"])
            .tag(["p", "user2_64_char_hex_key_0000000000000000000000000000000000000002"])
            .tag(["p", "user3_64_char_hex_key_0000000000000000000000000000000000000003"])
            .build()

        // Verify p-tag count
        XCTAssertEqual(event.pTags.count, 3, "Event should have 3 p-tags")
        XCTAssertLessThan(event.pTags.count, 10, "Event should have fewer than 10 p-tags")

        // The relay selector should apply outbox model logic for this event
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)

        // Should track the p-tagged users as missing relay info since we haven't set up their relay lists
        XCTAssertEqual(selection.missingRelayInfoPubkeys.count, 3, "Should track all 3 p-tagged users as missing relay info")
        XCTAssertTrue(selection.missingRelayInfoPubkeys.contains("user1_64_char_hex_key_0000000000000000000000000000000000000001"))
        XCTAssertTrue(selection.missingRelayInfoPubkeys.contains("user2_64_char_hex_key_0000000000000000000000000000000000000002"))
        XCTAssertTrue(selection.missingRelayInfoPubkeys.contains("user3_64_char_hex_key_0000000000000000000000000000000000000003"))
    }

    func testEventWith10OrMorePTagsSkipsOutboxModel() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(relayURLs: [], signer: signer, cache: cache)

        // Create test event with 11 p-tags (>= 10)
        var eventBuilder = NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Hello to many people!")

        for i in 1 ... 11 {
            let pubkey = String(format: "user%02d_64_char_hex_key_000000000000000000000000000000000000%02d", i, i)
            eventBuilder = eventBuilder.tag(["p", pubkey])
        }

        let event = try await eventBuilder.build()

        // Verify p-tag count
        XCTAssertEqual(event.pTags.count, 11, "Event should have 11 p-tags")
        XCTAssertGreaterThanOrEqual(event.pTags.count, 10, "Event should have 10 or more p-tags")

        // The relay selector should NOT apply outbox model for p-tagged users
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)

        // Should NOT track the p-tagged users as missing relay info when >= 10 p-tags
        XCTAssertEqual(selection.missingRelayInfoPubkeys.count, 0, "Should not track p-tagged users when event has 10+ p-tags")
    }

    func testEventWithNoPTagsWorksNormally() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(relayURLs: [], signer: signer, cache: cache)

        // Create test event with no p-tags
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Hello world!")
            .build()

        // Verify no p-tags
        XCTAssertEqual(event.pTags.count, 0, "Event should have no p-tags")

        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)

        // Should have no missing relay info pubkeys
        XCTAssertEqual(selection.missingRelayInfoPubkeys.count, 0, "Should have no missing relay info when no p-tags")

        // Should still select some relays for publishing (author's relays + fallback)
        XCTAssertGreaterThan(selection.relays.count, 0, "Should select some relays for publishing")
    }

    func testPTagExtractionWorksCorrectly() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(relayURLs: [], signer: signer, cache: cache)

        // Create test event with mixed tags
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1)
            .content("Mixed tags test")
            .tag(["p", "pubkey1"])
            .tag(["e", "eventid1"])
            .tag(["p", "pubkey2"])
            .tag(["t", "hashtag"])
            .tag(["p", "pubkey3"])
            .build()

        // Verify p-tag extraction
        let pTags = event.pTags
        XCTAssertEqual(pTags.count, 3, "Should extract 3 p-tags")
        XCTAssertTrue(pTags.contains("pubkey1"))
        XCTAssertTrue(pTags.contains("pubkey2"))
        XCTAssertTrue(pTags.contains("pubkey3"))

        // Verify it doesn't include other tag types
        XCTAssertFalse(pTags.contains("eventid1"))
        XCTAssertFalse(pTags.contains("hashtag"))
    }

    func testFetchingIgnoresPTagCount() async throws {
        let cache = try await NDKTestFactory.createTestCache()
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(relayURLs: [], signer: signer, cache: cache)

        // Create filter with many p-tags
        var pTagUsers: [String] = []
        for i in 1 ... 15 {
            pTagUsers.append(String(format: "user%02d_64_char_hex_key_000000000000000000000000000000000000%02d", i, i))
        }

        let filter = NDKFilter(
            kinds: [1],
            tags: ["p": Set(pTagUsers)]
        )

        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForFetching(filter: filter)

        // For fetching, should consider p-tagged users regardless of count
        // Since we haven't set up relay lists, they should be in missing pubkeys
        XCTAssertEqual(selection.missingRelayInfoPubkeys.count, 15, "Fetching should consider all p-tagged users regardless of count")
    }
}
