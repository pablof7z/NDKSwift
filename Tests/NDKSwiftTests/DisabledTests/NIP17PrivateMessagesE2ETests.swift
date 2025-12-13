@testable import NDKSwiftCore
import XCTest

/// End-to-end tests for NIP-17 Private Direct Messages
final class NIP17PrivateMessagesE2ETests: XCTestCase {
    var ndk: NDK!
    var alice: NDKPrivateKeySigner!
    var bob: NDKPrivateKeySigner!
    var alicePubkey: PublicKey!
    var bobPubkey: PublicKey!

    override func setUp() async throws {
        try await super.setUp()

        // Initialize NDK with test relays
        ndk = NDK(relayUrls: ["wss://relay.damus.io"])
        await ndk.connect()

        // Generate test keys
        alice = try NDKPrivateKeySigner.generate()
        bob = try NDKPrivateKeySigner.generate()

        alicePubkey = try await alice.pubkey
        bobPubkey = try await bob.pubkey
    }

    override func tearDown() async throws {
        await ndk.disconnect()
        try await super.tearDown()
    }

    func testSendAndReceivePrivateMessage() async throws {
        let testMessage = "Test NIP-17 message: \(UUID().uuidString)"
        let testSubject = "E2E Test Subject"

        // Create recipient with relay hint
        let recipient = NIP17Recipient(
            pubkey: bobPubkey,
            relayURL: "wss://relay.damus.io"
        )

        // Send message from Alice to Bob
        let wrappedMessage = try await NIP17.sendMessage(
            testMessage,
            to: recipient,
            signer: alice,
            subject: testSubject
        )

        // Verify wrapped message properties
        XCTAssertEqual(wrappedMessage.kind, EventKind.giftWrap)
        XCTAssertTrue(wrappedMessage.tags.contains { $0[0] == "p" && $0[1] == bobPubkey })

        // Publish the wrapped message
        _ = try await ndk.publish(wrappedMessage)

        // Small delay to ensure propagation
        try await Task.sleep(nanoseconds: TimeConstants.nanosecondsPerMillisecond * 500) // 0.5 seconds

        // Bob fetches gift wrapped messages
        let filter = NDKFilter(
            kinds: [EventKind.giftWrap],
            tags: ["p": Set([bobPubkey])]
        )

        let dataSource = ndk.subscribe(filter: filter, maxAge: 0, closeOnEose: true)
        var receivedEvents: [NDKEvent] = []
        for await event in dataSource.events {
            receivedEvents.append(event)
        }

        // Find our message
        let ourMessage = receivedEvents.first { event in
            event.id == wrappedMessage.id
        }

        XCTAssertNotNil(ourMessage, "Should receive the gift wrapped message")

        // Unwrap the message
        if let received = ourMessage {
            let unwrapped = try await NIP17.unwrapEvent(received, recipientSigner: bob)

            XCTAssertEqual(unwrapped.content, testMessage)
            XCTAssertEqual(unwrapped.pubkey, alicePubkey)
            XCTAssertEqual(unwrapped.kind, EventKind.chatMessage)

            // Verify subject tag
            let subjectTag = unwrapped.tags.first { $0[0] == "subject" }
            XCTAssertEqual(subjectTag?[1], testSubject)
        }
    }

    func testGroupMessaging() async throws {
        // Add Charlie to the group
        let charlie = try NDKPrivateKeySigner.generate()
        let charliePubkey = try await charlie.pubkey

        let groupMessage = "Group test message: \(UUID().uuidString)"
        let recipients = [
            NIP17Recipient(pubkey: bobPubkey),
            NIP17Recipient(pubkey: charliePubkey),
        ]

        // Send to multiple recipients
        let wrappedEvents = try await NIP17.sendToMany(
            groupMessage,
            to: recipients,
            signer: alice,
            subject: "Group Chat"
        )

        // Should have events for sender + recipients
        XCTAssertEqual(wrappedEvents.events.count, 3) // Alice + Bob + Charlie

        // Publish all wrapped events
        for (_, event) in wrappedEvents.events {
            _ = try await ndk.publish(event)
        }

        try await Task.sleep(nanoseconds: TimeConstants.nanosecondsPerMillisecond * 500) // 0.5 seconds

        // Bob fetches and unwraps his copy
        let bobFilter = NDKFilter(
            kinds: [EventKind.giftWrap],
            tags: ["p": Set([bobPubkey])]
        )

        let bobDataSource = ndk.subscribe(filter: bobFilter, maxAge: 0, closeOnEose: true)
        var bobEvents: [NDKEvent] = []
        for await event in bobDataSource.events {
            bobEvents.append(event)
        }
        let bobWrapped = bobEvents.first { event in
            wrappedEvents.events[bobPubkey]?.id == event.id
        }

        if let wrapped = bobWrapped {
            let unwrapped = try await NIP17.unwrapEvent(wrapped, recipientSigner: bob)
            XCTAssertEqual(unwrapped.content, groupMessage)

            // Verify all recipients are tagged
            let pTags = unwrapped.tags.filter { $0[0] == "p" }
            XCTAssertEqual(pTags.count, 2) // Bob and Charlie
        }
    }

    func testReplyToMessage() async throws {
        // First, Alice sends a message to Bob
        let originalMessage = "Original message"
        let wrappedOriginal = try await NIP17.sendMessage(
            originalMessage,
            to: NIP17Recipient(pubkey: bobPubkey),
            signer: alice
        )

        _ = try await ndk.publish(wrappedOriginal)

        // Bob unwraps it
        let unwrappedOriginal = try await NIP17.unwrapEvent(wrappedOriginal, recipientSigner: bob)

        // Bob creates a reply
        let replyConfig = NIP17MessageConfig(
            recipients: [NIP17Recipient(pubkey: alicePubkey)],
            subject: "Re: Original",
            replyTo: NIP17ReplyTo(eventId: unwrappedOriginal.id)
        )

        let replyEvent = try NIP17.createEvent(
            content: "This is my reply",
            config: replyConfig,
            senderPubkey: bobPubkey
        )

        // Verify reply tag
        let replyTag = replyEvent.tags.first { $0[0] == "e" && $0.count > 3 && $0[3] == "reply" }
        XCTAssertNotNil(replyTag)
        XCTAssertEqual(replyTag?[1], unwrappedOriginal.id)

        // Wrap and send reply
        let wrappedReply = try await NIP17.wrapEvent(
            replyEvent,
            signer: bob,
            recipient: NIP17Recipient(pubkey: alicePubkey)
        )

        _ = try await ndk.publish(wrappedReply)
    }

    func testFileMessage() async throws {
        let fileMetadata = """
        {
            "url": "https://example.com/test.pdf",
            "mimeType": "application/pdf",
            "size": 1024000,
            "sha256": "abcd1234...",
            "name": "test.pdf"
        }
        """

        let fileConfig = NIP17MessageConfig(
            recipients: [NIP17Recipient(pubkey: bobPubkey)],
            subject: "File for review"
        )

        let fileEvent = try NIP17.createEvent(
            content: fileMetadata,
            config: fileConfig,
            senderPubkey: alicePubkey,
            kind: EventKind.fileMessage
        )

        XCTAssertEqual(fileEvent.kind, EventKind.fileMessage)

        let wrapped = try await NIP17.wrapEvent(
            fileEvent,
            signer: alice,
            recipient: NIP17Recipient(pubkey: bobPubkey)
        )

        _ = try await ndk.publish(wrapped)

        // Bob unwraps and verifies
        let unwrapped = try await NIP17.unwrapEvent(wrapped, recipientSigner: bob)
        XCTAssertEqual(unwrapped.kind, EventKind.fileMessage)
        XCTAssertEqual(unwrapped.content, fileMetadata)
    }

    func testMetadataPrivacy() async throws {
        let message = "Privacy test message"
        let wrapped = try await NIP17.sendMessage(
            message,
            to: NIP17Recipient(pubkey: bobPubkey),
            signer: alice
        )

        // Verify metadata protection

        // 1. Sender identity is hidden
        XCTAssertNotEqual(wrapped.pubkey, alicePubkey, "Gift wrap should not reveal sender")

        // 2. Timestamp is randomized
        let now = Timestamp.now
        let twoDays: Int64 = 2 * 24 * 60 * 60
        let timeDiff = abs(wrapped.createdAt - now)
        XCTAssertLessThanOrEqual(timeDiff, twoDays, "Timestamp should be within randomization range")

        // 3. Only recipient is tagged
        let tags = wrapped.tags
        XCTAssertEqual(tags.count, 1, "Should only have recipient tag")
        XCTAssertEqual(tags[0][0], "p")
        XCTAssertEqual(tags[0][1], bobPubkey)
    }
}
