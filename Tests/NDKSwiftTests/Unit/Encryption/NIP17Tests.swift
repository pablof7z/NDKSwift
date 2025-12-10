import XCTest
@testable import NDKSwiftCore

final class NIP17Tests: XCTestCase {
    
    // Test vectors from nostr-tools
    let senderPrivateKey = "f09ac9b695d0a4c6daa418fe95b977eea20f54d9545592bc36a4f9e14f3eb840"
    let senderPublicKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    
    let recipientPrivateKey = "5393a825e5892d8e18d4a5ea61ced105e8bb2a106f42876be3a40522e0b13747"
    let recipientPublicKey = "483e062bd1148c64e10abcdcc42444c2f6c5d9115a7925c9e0c0b4dc84cd8f0f"
    
    let testMessage = "Hello, this is a direct message!"
    let testSubject = "Private Group Conversation"
    let testReplyToId = "previousEventId123"
    
    override func setUp() {
        super.setUp()
    }
    
    // MARK: - Create Event Tests
    
    func testCreateChatMessageEvent() throws {
        let recipients = [
            NIP17Recipient(pubkey: recipientPublicKey, relayURL: "wss://relay1.com"),
            NIP17Recipient(pubkey: "anotherPubkey")
        ]
        
        let config = NIP17MessageConfig(
            recipients: recipients,
            subject: testSubject,
            replyTo: NIP17ReplyTo(eventId: testReplyToId, relayURL: "wss://relay2.com")
        )
        
        let event = try NIP17.createEvent(
            content: testMessage,
            config: config,
            senderPubkey: senderPublicKey
        )
        
        // Verify event properties
        XCTAssertEqual(event.kind, EventKind.chatMessage)
        XCTAssertEqual(event.content, testMessage)
        XCTAssertEqual(event.pubkey, senderPublicKey)
        XCTAssertTrue(event.isRumor, "Event should be unsigned (rumor)")
        
        // Verify tags
        let pTags = event.tags.filter { $0[0] == "p" }
        XCTAssertEqual(pTags.count, 2, "Should have 2 recipient tags")
        XCTAssertEqual(pTags[0][1], recipientPublicKey)
        XCTAssertEqual(pTags[0][2], "wss://relay1.com")
        
        let subjectTag = event.tags.first { $0[0] == "subject" }
        XCTAssertNotNil(subjectTag)
        XCTAssertEqual(subjectTag?[1], testSubject)
        
        let replyTag = event.tags.first { $0[0] == "e" }
        XCTAssertNotNil(replyTag)
        XCTAssertEqual(replyTag?[1], testReplyToId)
        XCTAssertEqual(replyTag?[3], "reply")
    }
    
    func testCreateFileMessageEvent() throws {
        let recipient = NIP17Recipient(pubkey: recipientPublicKey)
        let config = NIP17MessageConfig(recipients: [recipient])
        
        let fileContent = """
        {
            "url": "https://example.com/file.pdf",
            "mimeType": "application/pdf",
            "size": 1024000
        }
        """
        
        let event = try NIP17.createEvent(
            content: fileContent,
            config: config,
            senderPubkey: senderPublicKey,
            kind: EventKind.fileMessage
        )
        
        XCTAssertEqual(event.kind, EventKind.fileMessage)
        XCTAssertEqual(event.content, fileContent)
    }
    
    func testCreateEventWithNoRecipients() {
        let config = NIP17MessageConfig(recipients: [])
        
        XCTAssertThrowsError(
            try NIP17.createEvent(
                content: testMessage,
                config: config,
                senderPubkey: senderPublicKey
            )
        ) { error in
            XCTAssertEqual(error as? NIP17Error, NIP17Error.noRecipients)
        }
    }
    
    // MARK: - Wrap/Unwrap Tests
    
    func testWrapAndUnwrapSingleRecipient() async throws {
        _ = NDK()
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipientSigner = try NDKPrivateKeySigner(privateKey: recipientPrivateKey)
        
        let recipient = NIP17Recipient(pubkey: recipientPublicKey, relayURL: "wss://relay1.com")
        
        // Create and wrap message
        let wrapped = try await NIP17.sendMessage(
            testMessage,
            to: recipient,
            signer: senderSigner,
            subject: testSubject
        )
        
        // Verify wrapped event
        XCTAssertEqual(wrapped.kind, EventKind.giftWrap)
        XCTAssertFalse(wrapped.content.isEmpty, "Wrapped content should not be empty")
        XCTAssertTrue(wrapped.tags.contains { $0[0] == "p" && $0[1] == recipientPublicKey })
        
        // Unwrap message
        let unwrapped = try await NIP17.unwrapEvent(wrapped, recipientSigner: recipientSigner)
        
        // Verify unwrapped event
        XCTAssertEqual(unwrapped.kind, EventKind.chatMessage)
        XCTAssertEqual(unwrapped.content, testMessage)
        XCTAssertEqual(unwrapped.pubkey, senderPublicKey)
        
        // Verify subject tag preserved
        let subjectTag = unwrapped.tags.first { $0[0] == "subject" }
        XCTAssertEqual(subjectTag?[1], testSubject)
    }
    
    func testWrapManyRecipients() async throws {
        _ = NDK()
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        
        let recipients = [
            NIP17Recipient(pubkey: recipientPublicKey, relayURL: "wss://relay1.com"),
            NIP17Recipient(pubkey: "anotherPubkey", relayURL: "wss://relay2.com")
        ]
        
        // Send to multiple recipients
        let wrappedEvents = try await NIP17.sendToMany(
            testMessage,
            to: recipients,
            signer: senderSigner,
            subject: testSubject
        )
        
        // Should have events for sender + all recipients
        XCTAssertEqual(wrappedEvents.events.count, 3) // sender + 2 recipients
        
        // Verify sender's copy exists
        XCTAssertNotNil(wrappedEvents.events[senderPublicKey])
        
        // Verify each recipient has a wrapped event
        for recipient in recipients {
            let wrapped = wrappedEvents.events[recipient.pubkey]
            XCTAssertNotNil(wrapped)
            XCTAssertEqual(wrapped?.kind, EventKind.giftWrap)
            XCTAssertTrue(wrapped?.tags.contains { $0[0] == "p" && $0[1] == recipient.pubkey } ?? false)
        }
        
        // Verify sealed event
        XCTAssertEqual(wrappedEvents.sealedEvent.kind, EventKind.seal)
    }
    
    // MARK: - NIP-59 Integration Tests
    
    func testDirectNIP59SealAndWrap() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        
        // Create rumor
        let rumor = NIP59.createRumor(
            kind: EventKind.chatMessage,
            content: testMessage,
            tags: [["p", recipientPublicKey]],
            pubkey: senderPublicKey
        )
        
        // Seal and wrap
        let wrapped = try await NIP59.sealAndWrap(
            rumor: rumor,
            signer: senderSigner,
            recipientPubkey: recipientPublicKey
        )
        
        XCTAssertEqual(wrapped.kind, EventKind.giftWrap)
        XCTAssertTrue(wrapped.tags.contains { $0[0] == "p" && $0[1] == recipientPublicKey })
    }
    
    func testTimestampRandomization() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipient = NIP17Recipient(pubkey: recipientPublicKey)
        
        let beforeTimestamp = Timestamp.now
        
        let wrapped = try await NIP17.sendMessage(
            testMessage,
            to: recipient,
            signer: senderSigner
        )
        
        let afterTimestamp = Timestamp.now
        
        // Wrapped event timestamp should be randomized
        let twoDaysInSeconds: Int64 = 2 * 24 * 60 * 60
        let minExpected = beforeTimestamp - twoDaysInSeconds
        let maxExpected = afterTimestamp + twoDaysInSeconds
        
        XCTAssertTrue(
            wrapped.createdAt >= minExpected && wrapped.createdAt <= maxExpected,
            "Timestamp should be within randomization range"
        )
    }
    
    // MARK: - Error Handling Tests
    
    func testUnwrapWithWrongRecipient() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let wrongSigner = try NDKPrivateKeySigner.generate()
        
        let recipient = NIP17Recipient(pubkey: recipientPublicKey)
        
        // Create and wrap message
        let wrapped = try await NIP17.sendMessage(
            testMessage,
            to: recipient,
            signer: senderSigner
        )
        
        // Try to unwrap with wrong signer
        do {
            _ = try await NIP17.unwrapEvent(wrapped, recipientSigner: wrongSigner)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected to fail
            XCTAssertTrue(error is NIP59.NIP59Error)
        }
    }
    
    func testInvalidEventKind() throws {
        let recipient = NIP17Recipient(pubkey: recipientPublicKey)
        let config = NIP17MessageConfig(recipients: [recipient])
        
        XCTAssertThrowsError(
            try NIP17.createEvent(
                content: testMessage,
                config: config,
                senderPubkey: senderPublicKey,
                kind: EventKind.textNote // Invalid kind for NIP-17
            )
        ) { error in
            if let nip17Error = error as? NIP17Error {
                switch nip17Error {
                case .invalidEventKind(let kind):
                    XCTAssertEqual(kind, EventKind.textNote)
                default:
                    XCTFail("Wrong error type")
                }
            }
        }
    }
}