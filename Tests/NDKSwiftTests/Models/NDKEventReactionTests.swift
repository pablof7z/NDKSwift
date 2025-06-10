@testable import NDKSwift
import XCTest

final class NDKEventReactionTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var testEvent: NDKEvent!

    override func setUp() async throws {
        try await super.setUp()

        // Create NDK instance with test relay
        ndk = NDK(relayUrls: ["wss://relay.damus.io"])

        // Create a test signer
        let privateKey = try Crypto.generatePrivateKey()
        signer = try NDKPrivateKeySigner(privateKey: privateKey)
        ndk.signer = signer

        // Create a test event to react to
        testEvent = try NDKEvent(
            pubkey: await signer.pubkey,
            kind: EventKind.textNote,
            content: "This is a test event to react to"
        )
        testEvent.ndk = ndk
        try await testEvent.sign()
    }

    override func tearDown() async throws {
        await ndk.disconnect()
        ndk = nil
        signer = nil
        testEvent = nil
        try await super.tearDown()
    }

    func testReactWithEmoji() async throws {
        // React with a heart emoji
        let reaction = try await testEvent.react(content: "❤️", publish: false)

        // Verify reaction event properties
        XCTAssertEqual(reaction.kind, EventKind.reaction)
        XCTAssertEqual(reaction.content, "❤️")
        let pubkey = try await signer.pubkey
        XCTAssertEqual(reaction.pubkey, pubkey)
        XCTAssertNotNil(reaction.id)
        XCTAssertNotNil(reaction.sig)

        // Verify tags
        let eTags = reaction.tags(withName: "e")
        let pTags = reaction.tags(withName: "p")

        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags[0][1], testEvent.id)

        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags[0][1], testEvent.pubkey)
    }

    func testReactWithPlus() async throws {
        // React with a plus (like)
        let reaction = try await testEvent.react(content: "+", publish: false)

        XCTAssertEqual(reaction.kind, EventKind.reaction)
        XCTAssertEqual(reaction.content, "+")
        XCTAssertNotNil(reaction.id)
        XCTAssertNotNil(reaction.sig)

        // Verify the event is tagged
        let eTags = reaction.tags(withName: "e")
        XCTAssertEqual(eTags.count, 1)
        XCTAssertEqual(eTags[0][1], testEvent.id)
    }

    func testReactWithMinus() async throws {
        // React with a minus (dislike)
        let reaction = try await testEvent.react(content: "-", publish: false)

        XCTAssertEqual(reaction.kind, EventKind.reaction)
        XCTAssertEqual(reaction.content, "-")
    }

    func testReactWithMultipleEmojis() async throws {
        // React with multiple emojis
        let emojis = ["🤙", "⚡", "🚀", "🔥", "💯"]

        for emoji in emojis {
            let reaction = try await testEvent.react(content: emoji, publish: false)
            XCTAssertEqual(reaction.kind, EventKind.reaction)
            XCTAssertEqual(reaction.content, emoji)
            XCTAssertNotNil(reaction.id)
            XCTAssertNotNil(reaction.sig)
        }
    }

    func testReactWithoutNDK() async throws {
        // Create an event without NDK instance
        let orphanEvent = NDKEvent(
            pubkey: "test",
            kind: EventKind.textNote,
            content: "Orphan event"
        )

        // Should throw error
        do {
            _ = try await orphanEvent.react(content: "+", publish: false)
            XCTFail("Should have thrown error")
        } catch {
            // Expected error for NDK not set
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReactWithoutSigner() async throws {
        // Remove signer from NDK
        ndk.signer = nil

        // Should throw error
        do {
            _ = try await testEvent.react(content: "+", publish: false)
            XCTFail("Should have thrown error")
        } catch {
            // Expected error - no signer
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReactionEventStructure() async throws {
        // Create a reaction
        let reaction = try await testEvent.react(content: "👍", publish: false)

        // Verify the raw event structure
        let raw = reaction.rawEvent()

        XCTAssertEqual(raw["kind"] as? Int, EventKind.reaction)
        XCTAssertEqual(raw["content"] as? String, "👍")
        XCTAssertNotNil(raw["id"] as? String)
        XCTAssertNotNil(raw["sig"] as? String)
        XCTAssertNotNil(raw["pubkey"] as? String)
        XCTAssertNotNil(raw["created_at"] as? Int64)

        let tags = raw["tags"] as? [[String]]
        XCTAssertNotNil(tags)
        XCTAssertGreaterThan(tags?.count ?? 0, 0)
    }

    func testReactionToUnsignedEvent() async throws {
        // Create an unsigned event
        let unsignedEvent = NDKEvent(
            pubkey: "test",
            kind: EventKind.textNote,
            content: "Unsigned event"
        )
        unsignedEvent.ndk = ndk
        // Don't sign it - it will have no ID

        // Should still work - the tag method will use empty string if no ID
        let reaction = try await unsignedEvent.react(content: "+", publish: false)
        XCTAssertEqual(reaction.kind, EventKind.reaction)
        XCTAssertEqual(reaction.content, "+")
    }

    func testReactionSerialization() async throws {
        // Create a reaction
        let reaction = try await testEvent.react(content: "⭐", publish: false)

        // Test serialization
        let json = try reaction.serialize()
        XCTAssertFalse(json.isEmpty)

        // Deserialize and verify
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NDKEvent.self, from: data)

        XCTAssertEqual(decoded.kind, EventKind.reaction)
        XCTAssertEqual(decoded.content, "⭐")
        XCTAssertEqual(decoded.id, reaction.id)
        XCTAssertEqual(decoded.sig, reaction.sig)
    }

    func testMultipleReactionsToSameEvent() async throws {
        // Create multiple reactions to the same event
        let reactions = try [
            await testEvent.react(content: "❤️", publish: false),
            await testEvent.react(content: "👍", publish: false),
            await testEvent.react(content: "🔥", publish: false),
        ]

        // All should reference the same event
        for reaction in reactions {
            let eTags = reaction.tags(withName: "e")
            XCTAssertEqual(eTags.count, 1)
            XCTAssertEqual(eTags[0][1], testEvent.id)
        }

        // But have different IDs
        let ids = reactions.compactMap { $0.id }
        XCTAssertEqual(Set(ids).count, reactions.count)
    }
}
