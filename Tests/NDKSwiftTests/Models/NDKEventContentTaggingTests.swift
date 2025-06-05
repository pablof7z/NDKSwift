@testable import NDKSwift
import XCTest

final class NDKEventContentTaggingTests: XCTestCase {
    func testEventGenerateContentTags() {
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [],
            content: "This is a #test post about #bitcoin"
        )

        event.generateContentTags()

        // Should have added hashtag tags
        let tTags = event.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 2)

        let tagValues = tTags.compactMap { $0.count > 1 ? $0[1] : nil }
        XCTAssertTrue(tagValues.contains("test"))
        XCTAssertTrue(tagValues.contains("bitcoin"))
    }

    func testEventSetContentWithAutomaticTagging() {
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [],
            content: ""
        )

        event.setContent("Hello #world! This is about #bitcoin")

        // Should have set content and generated tags
        XCTAssertEqual(event.content, "Hello #world! This is about #bitcoin")

        let tTags = event.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 2)

        let tagValues = tTags.compactMap { $0.count > 1 ? $0[1] : nil }
        XCTAssertTrue(tagValues.contains("world"))
        XCTAssertTrue(tagValues.contains("bitcoin"))
    }

    func testEventSetContentWithoutTagging() {
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [],
            content: ""
        )

        event.setContent("Hello #world! This is about #bitcoin", generateTags: false)

        // Should have set content but not generated tags
        XCTAssertEqual(event.content, "Hello #world! This is about #bitcoin")
        XCTAssertEqual(event.tags.count, 0)
    }

    func testEventWithNostrEntities() {
        let npub = "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [],
            content: "Hello @\(npub) and #bitcoin"
        )

        event.generateContentTags()

        // Should have p tag for npub and t tag for hashtag
        let pTags = event.tags.filter { $0[0] == "p" }
        let tTags = event.tags.filter { $0[0] == "t" }

        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(tTags.count, 1)
        XCTAssertEqual(tTags.first?[1], "bitcoin")
        XCTAssertEqual(pTags.first?[1], "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52")

        // Content should be normalized
        XCTAssertTrue(event.content.contains("nostr:\(npub)"))
    }

    func testEventWithExistingTags() {
        let existingTags: [Tag] = [["p", "existing_pubkey"], ["custom", "value"]]
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: existingTags,
            content: "This is about #bitcoin"
        )

        event.generateContentTags()

        // Should preserve existing tags and add new ones
        XCTAssertTrue(event.tags.contains(["p", "existing_pubkey"]))
        XCTAssertTrue(event.tags.contains(["custom", "value"]))
        XCTAssertTrue(event.tags.contains(["t", "bitcoin"]))
        XCTAssertEqual(event.tags.count, 3)
    }

    func testEventWithDuplicateTagPrevention() {
        let existingTags: [Tag] = [["t", "bitcoin"]]
        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: existingTags,
            content: "This is about #bitcoin again"
        )

        event.generateContentTags()

        // Should not duplicate existing bitcoin tag
        let bitcoinTags = event.tags.filter { $0.count > 1 && $0[0] == "t" && $0[1] == "bitcoin" }
        XCTAssertEqual(bitcoinTags.count, 1)
    }

    func testEventContentTaggingWithMixedEntities() {
        let npub = "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
        let note = "note1fntxf5qq4z6fmk186mwwu7t0972rcez8cejatp0698lrzspsuyqq9m4vm7"
        let content = "Mentioning @\(npub) and referencing nostr:\(note) about #bitcoin and #nostr"

        let event = NDKEvent(
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [],
            content: content
        )

        event.generateContentTags()

        // Should have p, q, and t tags
        let pTags = event.tags.filter { $0[0] == "p" }
        let qTags = event.tags.filter { $0[0] == "q" }
        let tTags = event.tags.filter { $0[0] == "t" }

        XCTAssertEqual(pTags.count, 1) // One for npub
        XCTAssertEqual(qTags.count, 1) // One for note
        XCTAssertEqual(tTags.count, 2) // Two hashtags

        // Verify hex conversion
        XCTAssertEqual(pTags.first?[1], "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52")
        XCTAssertEqual(qTags.first?[1].count, 64) // Hex event ID should be 64 chars

        // Content should be normalized with nostr: prefixes
        XCTAssertTrue(event.content.contains("nostr:\(npub)"))
        XCTAssertTrue(event.content.contains("nostr:\(note)"))
    }

    func testEventSigningTriggersContentTagging() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: "4c5e4b93e5e0b4c5e8e4e8e4e8e4e8e4e8e4e8e4e8e4e8e4e8e4e8e4e8e4e8e4")
        let ndk = NDK(signer: signer)

        let event = NDKEvent(
            pubkey: "",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [],
            content: "This is a #test post about #bitcoin"
        )
        event.ndk = ndk

        try await event.sign()

        // Should have generated content tags during signing
        let tTags = event.tags.filter { $0[0] == "t" }
        XCTAssertEqual(tTags.count, 2)

        let tagValues = tTags.compactMap { $0.count > 1 ? $0[1] : nil }
        XCTAssertTrue(tagValues.contains("test"))
        XCTAssertTrue(tagValues.contains("bitcoin"))

        // Should be properly signed
        XCTAssertNotNil(event.sig)
        XCTAssertNotNil(event.id)
    }
}
