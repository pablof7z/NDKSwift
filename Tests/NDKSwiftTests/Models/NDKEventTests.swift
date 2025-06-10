@testable import NDKSwift
import XCTest

final class NDKEventTests: XCTestCase {
    func testEventInitialization() {
        let pubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let event = NDKEvent(
            pubkey: pubkey,
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [["p", "abcd1234"]],
            content: "Hello, Nostr!"
        )

        XCTAssertEqual(event.pubkey, pubkey)
        XCTAssertEqual(event.createdAt, 1_234_567_890)
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.tags.count, 1)
        XCTAssertEqual(event.content, "Hello, Nostr!")
        XCTAssertNil(event.id)
        XCTAssertNil(event.sig)
    }

    func testEventIDGeneration() throws {
        let event = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [],
            content: "Test message"
        )

        let id = try event.generateID()

        XCTAssertNotNil(event.id)
        XCTAssertEqual(event.id, id)
        XCTAssertEqual(id.count, 64)
        XCTAssertTrue(id.allSatisfy { $0.isASCII && $0.isHexDigit })
    }

    func testEventSerialization() throws {
        let event = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [["e", "event123"], ["p", "pubkey456"]],
            content: "Test content"
        )

        // Generate ID to ensure all fields are set
        try event.generateID()

        // Test encoding
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(event)
        let json = String(data: data, encoding: .utf8)!

        // Test decoding
        let decoder = JSONDecoder()
        let decodedEvent = try decoder.decode(NDKEvent.self, from: data)

        XCTAssertEqual(decodedEvent.pubkey, event.pubkey)
        XCTAssertEqual(decodedEvent.createdAt, event.createdAt)
        XCTAssertEqual(decodedEvent.kind, event.kind)
        XCTAssertEqual(decodedEvent.content, event.content)
        XCTAssertEqual(decodedEvent.tags.count, event.tags.count)
    }

    func testEventValidation() throws {
        // Valid event
        let validEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Valid"
        )
        try validEvent.generateID()
        XCTAssertNoThrow(try validEvent.validate())

        // Invalid pubkey
        let invalidPubkeyEvent = NDKEvent(
            pubkey: "invalid",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Invalid"
        )
        XCTAssertThrowsError(try invalidPubkeyEvent.validate()) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            XCTAssertEqual(ndkError.code, "invalid_public_key")
            XCTAssertEqual(ndkError.category, .validation)
        }

        // Invalid ID
        let invalidIDEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Invalid ID"
        )
        invalidIDEvent.id = "invalid"
        XCTAssertThrowsError(try invalidIDEvent.validate()) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            XCTAssertEqual(ndkError.code, "invalid_event_id")
            XCTAssertEqual(ndkError.category, .validation)
        }
    }

    func testTagHelpers() {
        let event = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [
                ["e", "event1", "wss://relay1.com", "root"],
                ["e", "event2", "wss://relay2.com", "reply"],
                ["p", "pubkey1"],
                ["p", "pubkey2", "wss://relay3.com"],
                ["t", "nostr"],
                ["t", "test"],
            ],
            content: "Test"
        )

        // Test getting tags by name
        let eTags = event.tags(withName: "e")
        XCTAssertEqual(eTags.count, 2)

        let pTags = event.tags(withName: "p")
        XCTAssertEqual(pTags.count, 2)

        let tTags = event.tags(withName: "t")
        XCTAssertEqual(tTags.count, 2)

        // Test getting first tag
        let firstETag = event.tag(withName: "e")
        XCTAssertNotNil(firstETag)
        XCTAssertEqual(firstETag?[1], "event1")

        // Test referenced IDs
        let referencedEvents = event.referencedEventIds
        XCTAssertEqual(referencedEvents.count, 2)
        XCTAssertTrue(referencedEvents.contains("event1"))
        XCTAssertTrue(referencedEvents.contains("event2"))

        let referencedPubkeys = event.referencedPubkeys
        XCTAssertEqual(referencedPubkeys.count, 2)
        XCTAssertTrue(referencedPubkeys.contains("pubkey1"))
        XCTAssertTrue(referencedPubkeys.contains("pubkey2"))

        // Test reply detection
        XCTAssertTrue(event.isReply)
        XCTAssertEqual(event.replyEventId, "event2")
    }

    func testAddingTags() {
        let event = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Test"
        )

        // Add a simple tag
        event.addTag(["t", "nostr"])
        XCTAssertEqual(event.tags.count, 1)

        // Add user tag
        let user = NDKUser(pubkey: "abcd1234567890abcd1234567890abcd1234567890abcd1234567890abcd1234")
        event.tag(user: user)
        XCTAssertEqual(event.tags.count, 2)
        XCTAssertEqual(event.tags[1], ["p", user.pubkey])

        // Add user tag with marker
        event.tag(user: user, marker: "mention")
        XCTAssertEqual(event.tags.count, 3)
        XCTAssertEqual(event.tags[2], ["p", user.pubkey, "mention"])

        // Add event tag
        let referencedEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Referenced"
        )
        referencedEvent.id = "referenced123"

        event.tag(event: referencedEvent, marker: "reply", relay: "wss://relay.com")
        XCTAssertEqual(event.tags.count, 4)
        XCTAssertEqual(event.tags[3], ["e", "referenced123", "wss://relay.com", "reply"])
    }

    func testEventKindHelpers() {
        // Ephemeral event
        let ephemeralEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 20000,
            content: "Ephemeral"
        )
        XCTAssertTrue(ephemeralEvent.isEphemeral)
        XCTAssertFalse(ephemeralEvent.isReplaceable)
        XCTAssertFalse(ephemeralEvent.isParameterizedReplaceable)

        // Replaceable event
        let replaceableEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 10002,
            content: "Replaceable"
        )
        XCTAssertFalse(replaceableEvent.isEphemeral)
        XCTAssertTrue(replaceableEvent.isReplaceable)
        XCTAssertFalse(replaceableEvent.isParameterizedReplaceable)

        // Parameterized replaceable event
        let parameterizedEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 30023,
            content: "Parameterized"
        )
        XCTAssertFalse(parameterizedEvent.isEphemeral)
        XCTAssertFalse(parameterizedEvent.isReplaceable)
        XCTAssertTrue(parameterizedEvent.isParameterizedReplaceable)

        // Regular event
        let regularEvent = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Regular"
        )
        XCTAssertFalse(regularEvent.isEphemeral)
        XCTAssertFalse(regularEvent.isReplaceable)
        XCTAssertFalse(regularEvent.isParameterizedReplaceable)
    }

    func testEquatableAndHashable() {
        let event1 = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Test"
        )
        event1.id = "event123"

        let event2 = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Test"
        )
        event2.id = "event123"

        let event3 = NDKEvent(
            pubkey: "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            createdAt: 1_234_567_890,
            kind: 1,
            content: "Different"
        )
        event3.id = "event456"

        // Test equality
        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)

        // Test hashable
        var set = Set<NDKEvent>()
        set.insert(event1)
        set.insert(event2)
        set.insert(event3)

        XCTAssertEqual(set.count, 2) // event1 and event2 are the same
    }
}
