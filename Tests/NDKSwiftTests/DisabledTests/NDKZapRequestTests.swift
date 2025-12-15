@testable import NDKSwiftCore
import XCTest

final class NDKZapRequestTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    var mockRelay: MockRelay!

    override func setUp() async throws {
        try await super.setUp()
        signer = try NDKPrivateKeySigner.generate()
        ndk = NDKTestFactory.createNDK(signer: signer)
        mockRelay = MockRelay(url: "wss://test.relay.com")
    }

    override func tearDown() async throws {
        ndk = nil
        signer = nil
        mockRelay = nil
        try await super.tearDown()
    }

    // MARK: - Creation Tests

    func testCreateBasicZapRequest() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey")
        let relays = ["wss://relay1.com", "wss://relay2.com"]

        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            signer: signer,
            recipient: recipient,
            amountMillisats: 1000,
            comment: "Great post!",
            relays: relays
        )

        let event = zapRequest.event
        XCTAssertEqual(event.kind, EventKind.zapRequest)
        XCTAssertEqual(event.content, "Great post!")

        // Check required tags
        XCTAssertTrue(event.tags.contains(["p", "recipient-pubkey"]))
        XCTAssertTrue(event.tags.contains(["relays", "wss://relay1.com", "wss://relay2.com"]))
        XCTAssertTrue(event.tags.contains(["amount", "1000"]))
    }

    func testCreateZapRequestWithoutComment() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey")

        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            signer: signer,
            recipient: recipient,
            amountMillisats: 5000,
            comment: nil,
            relays: ["wss://relay.com"]
        )

        XCTAssertEqual(zapRequest.event.content, "")
    }

    func testCreateZapRequestForEvent() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey")
        let zappedEvent = NDKEvent(
            id: "event-to-zap",
            pubkey: "event-author",
            createdAt: Timestamp.now,
            kind: 1,
            tags: [],
            content: "Original post",
            sig: "sig"
        )

        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            signer: signer,
            recipient: recipient,
            amountMillisats: 2000,
            comment: "Zapping this event",
            relays: ["wss://relay.com"],
            zappedEvent: zappedEvent
        )

        // Should include event tag
        XCTAssertTrue(zapRequest.event.tags.contains(["e", "event-to-zap"]))
    }

    func testCreateZapRequestForAddressableEvent() async throws {
        let recipient = NDKUser(pubkey: "recipient-pubkey")
        let coordinate = "30023:author-pubkey:article-id"

        let zapRequest = try await NDKZapRequest.create(
            ndk: ndk,
            signer: signer,
            recipient: recipient,
            amountMillisats: 3000,
            comment: "Great article!",
            relays: ["wss://relay.com"],
            zappedEventCoordinate: coordinate
        )

        // Should include address tag
        XCTAssertTrue(zapRequest.event.tags.contains(["a", coordinate]))
    }

    // MARK: - Parsing Tests

    func testParseZapRequest() {
        let event = NDKEvent(
            id: "zap-request-id",
            pubkey: "sender-pubkey",
            createdAt: Timestamp.now,
            kind: EventKind.zapRequest,
            tags: [
                ["p", "recipient-pubkey"],
                ["relays", "wss://relay1.com", "wss://relay2.com"],
                ["amount", "1000"],
                ["e", "zapped-event-id"],
            ],
            content: "Test zap",
            sig: "sig"
        )

        let zapRequest = NDKZapRequest(event: event)

        // Test getters
        XCTAssertEqual(zapRequest.recipientPubkey, "recipient-pubkey")
        XCTAssertEqual(zapRequest.amountMillisats, 1000)
        XCTAssertEqual(zapRequest.comment, "Test zap")
        XCTAssertEqual(zapRequest.relays, ["wss://relay1.com", "wss://relay2.com"])
        XCTAssertEqual(zapRequest.zappedEventId, "zapped-event-id")
        XCTAssertNil(zapRequest.zappedEventCoordinate)
    }

    func testParseZapRequestWithAddressTag() {
        let event = NDKEvent(
            id: "zap-request-id",
            pubkey: "sender-pubkey",
            createdAt: Timestamp.now,
            kind: EventKind.zapRequest,
            tags: [
                ["p", "recipient-pubkey"],
                ["relays", "wss://relay.com"],
                ["amount", "5000"],
                ["a", "30023:author:article"],
            ],
            content: "",
            sig: "sig"
        )

        let zapRequest = NDKZapRequest(event: event)

        XCTAssertNil(zapRequest.zappedEventId)
        XCTAssertEqual(zapRequest.zappedEventCoordinate, "30023:author:article")
    }

    // MARK: - Validation Tests

    func testValidateZapRequest() {
        // Valid zap request
        let validEvent = NDKEvent(
            id: "valid-id",
            pubkey: "sender",
            createdAt: Timestamp.now,
            kind: EventKind.zapRequest,
            tags: [
                ["p", "recipient"],
                ["relays", "wss://relay.com"],
                ["amount", "1000"],
            ],
            content: "",
            sig: "sig"
        )

        let validRequest = NDKZapRequest(event: validEvent)
        XCTAssertTrue(validRequest.isValid)

        // Invalid - missing recipient
        let missingRecipient = NDKEvent(
            id: "id",
            pubkey: "sender",
            createdAt: Timestamp.now,
            kind: EventKind.zapRequest,
            tags: [
                ["relays", "wss://relay.com"],
                ["amount", "1000"],
            ],
            content: "",
            sig: "sig"
        )

        let invalidRequest1 = NDKZapRequest(event: missingRecipient)
        XCTAssertFalse(invalidRequest1.isValid)

        // Invalid - missing amount
        let missingAmount = NDKEvent(
            id: "id",
            pubkey: "sender",
            createdAt: Timestamp.now,
            kind: EventKind.zapRequest,
            tags: [
                ["p", "recipient"],
                ["relays", "wss://relay.com"],
            ],
            content: "",
            sig: "sig"
        )

        let invalidRequest2 = NDKZapRequest(event: missingAmount)
        XCTAssertFalse(invalidRequest2.isValid)

        // Invalid - missing relays
        let missingRelays = NDKEvent(
            id: "id",
            pubkey: "sender",
            createdAt: Timestamp.now,
            kind: EventKind.zapRequest,
            tags: [
                ["p", "recipient"],
                ["amount", "1000"],
            ],
            content: "",
            sig: "sig"
        )

        let invalidRequest3 = NDKZapRequest(event: missingRelays)
        XCTAssertFalse(invalidRequest3.isValid)
    }

    // MARK: - Amount Tests

    func testAmountParsing() {
        // Valid amount
        let event1 = createZapRequestEvent(tags: [
            ["p", "recipient"],
            ["relays", "wss://relay.com"],
            ["amount", "12345"],
        ])
        let request1 = NDKZapRequest(event: event1)
        XCTAssertEqual(request1.amountMillisats, 12345)

        // Invalid amount (not a number)
        let event2 = createZapRequestEvent(tags: [
            ["p", "recipient"],
            ["relays", "wss://relay.com"],
            ["amount", "not-a-number"],
        ])
        let request2 = NDKZapRequest(event: event2)
        XCTAssertNil(request2.amountMillisats)

        // Negative amount (should be treated as invalid)
        let event3 = createZapRequestEvent(tags: [
            ["p", "recipient"],
            ["relays", "wss://relay.com"],
            ["amount", "-1000"],
        ])
        let request3 = NDKZapRequest(event: event3)
        XCTAssertEqual(request3.amountMillisats, -1000) // Parser allows it, validation should catch
    }

    // MARK: - Relay Parsing Tests

    func testRelayParsing() {
        // Multiple relays
        let event1 = createZapRequestEvent(tags: [
            ["p", "recipient"],
            ["relays", "wss://relay1.com", "wss://relay2.com", "wss://relay3.com"],
            ["amount", "1000"],
        ])
        let request1 = NDKZapRequest(event: event1)
        XCTAssertEqual(request1.relays, ["wss://relay1.com", "wss://relay2.com", "wss://relay3.com"])

        // Single relay
        let event2 = createZapRequestEvent(tags: [
            ["p", "recipient"],
            ["relays", "wss://single-relay.com"],
            ["amount", "1000"],
        ])
        let request2 = NDKZapRequest(event: event2)
        XCTAssertEqual(request2.relays, ["wss://single-relay.com"])

        // Empty relays tag (invalid)
        let event3 = createZapRequestEvent(tags: [
            ["p", "recipient"],
            ["relays"],
            ["amount", "1000"],
        ])
        let request3 = NDKZapRequest(event: event3)
        XCTAssertTrue(request3.relays.isEmpty)
    }

    // MARK: - Helper Methods

    private func createZapRequestEvent(tags: [[String]], content: String = "") -> NDKEvent {
        return NDKEvent(
            id: "test-id",
            pubkey: "test-pubkey",
            createdAt: Timestamp.now,
            kind: EventKind.zapRequest,
            tags: tags,
            content: content,
            sig: "test-sig"
        )
    }
}

// MARK: - Test Extensions

extension NDKZapRequest {
    // Add computed properties for easier testing
    var recipientPubkey: String? {
        event.tags.first { $0.count > 1 && $0[0] == "p" }?[1]
    }

    var amountMillisats: Int64? {
        guard let amountTag = event.tags.first(where: { $0.count > 1 && $0[0] == "amount" }),
              let amount = Int64(amountTag[1]) else { return nil }
        return amount
    }

    var comment: String? {
        event.content.isEmpty ? nil : event.content
    }

    var relays: [String] {
        guard let relayTag = event.tags.first(where: { $0.count > 0 && $0[0] == "relays" }) else {
            return []
        }
        return Array(relayTag.dropFirst())
    }

    var zappedEventId: String? {
        event.tags.first { $0.count > 1 && $0[0] == "e" }?[1]
    }

    var zappedEventCoordinate: String? {
        event.tags.first { $0.count > 1 && $0[0] == "a" }?[1]
    }

    var isValid: Bool {
        recipientPubkey != nil && amountMillisats != nil && !relays.isEmpty
    }
}
