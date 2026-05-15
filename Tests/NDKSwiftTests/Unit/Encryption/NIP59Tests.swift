@testable import NDKSwiftCore
import XCTest

final class NIP59Tests: XCTestCase {
    let senderPrivateKey = "0000000000000000000000000000000000000000000000000000000000000001"
    let senderPublicKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

    let recipientPrivateKey = "0000000000000000000000000000000000000000000000000000000000000002"
    let recipientPublicKey = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

    override func setUp() {
        super.setUp()
    }

    // MARK: - Rumor Tests

    func testCreateRumor() {
        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Test rumor content",
            tags: [["t", "test"]],
            pubkey: senderPublicKey,
            createdAt: 1_234_567_890
        )

        XCTAssertEqual(rumor.kind, EventKind.textNote)
        XCTAssertEqual(rumor.content, "Test rumor content")
        XCTAssertEqual(rumor.pubkey, senderPublicKey)
        XCTAssertEqual(rumor.createdAt, 1_234_567_890)
        XCTAssertEqual(rumor.tags.count, 1)
        XCTAssertTrue(rumor.isRumor, "Should be an unsigned rumor")
        XCTAssertTrue(rumor.id.isEmpty, "Rumor should have empty ID")
        XCTAssertTrue(rumor.sig.isEmpty, "Rumor should have empty signature")
    }

    // MARK: - Seal Tests

    func testSealRumor() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: senderPrivateKey)

        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Secret message",
            tags: [],
            pubkey: senderPublicKey
        )

        let beforeTimestamp = Timestamp.now
        let seal = try await NIP59.seal(
            rumor: rumor,
            signer: signer,
            recipientPubkey: recipientPublicKey
        )
        let afterTimestamp = Timestamp.now
        let twoDaysInSeconds: Int64 = 2 * 24 * 60 * 60

        // Verify seal properties
        XCTAssertEqual(seal.kind, EventKind.seal)
        XCTAssertEqual(seal.pubkey, senderPublicKey)
        XCTAssertFalse(seal.content.isEmpty, "Seal should have encrypted content")
        XCTAssertFalse(seal.id.isEmpty, "Seal should be signed with ID")
        XCTAssertFalse(seal.sig.isEmpty, "Seal should be signed")
        XCTAssertEqual(seal.tags.count, 0, "Seal should have no tags")
        XCTAssertGreaterThanOrEqual(seal.createdAt, beforeTimestamp - twoDaysInSeconds)
        XCTAssertLessThanOrEqual(seal.createdAt, afterTimestamp)
    }

    func testSealSignedEventFails() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: senderPrivateKey)

        // Create a signed event (not a rumor)
        let signedEvent = NDKEvent(
            id: "someId",
            pubkey: senderPublicKey,
            createdAt: .now,
            kind: EventKind.textNote,
            tags: [],
            content: "content",
            sig: "someSig"
        )

        do {
            _ = try await NIP59.seal(
                rumor: signedEvent,
                signer: signer,
                recipientPubkey: recipientPublicKey
            )
            XCTFail("Should not seal signed events")
        } catch NIP59.NIP59Error.invalidRumor(_) {
            // Expected
        }
    }

    func testSealHalfSignedRumorFails() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let malformedRumor = NDKEvent(
            id: "",
            pubkey: senderPublicKey,
            createdAt: .now,
            kind: EventKind.textNote,
            tags: [],
            content: "content",
            sig: String(repeating: "0", count: 128)
        )

        do {
            _ = try await NIP59.seal(
                rumor: malformedRumor,
                signer: signer,
                recipientPubkey: recipientPublicKey
            )
            XCTFail("Should not seal events that still carry a signature")
        } catch NIP59.NIP59Error.invalidRumor(_) {
            // Expected
        }
    }

    // MARK: - Gift Wrap Tests

    func testWrapSeal() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: senderPrivateKey)

        // Create and seal a rumor
        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Secret message",
            tags: [],
            pubkey: senderPublicKey
        )

        let seal = try await NIP59.seal(
            rumor: rumor,
            signer: signer,
            recipientPubkey: recipientPublicKey
        )

        // Wrap the seal
        let giftWrap = try await NIP59.wrap(
            seal: seal,
            recipientPubkey: recipientPublicKey
        )

        // Verify gift wrap properties
        XCTAssertEqual(giftWrap.kind, EventKind.giftWrap)
        XCTAssertFalse(giftWrap.content.isEmpty, "Gift wrap should have encrypted content")
        XCTAssertFalse(giftWrap.id.isEmpty, "Gift wrap should be signed")
        XCTAssertFalse(giftWrap.sig.isEmpty, "Gift wrap should be signed")

        // Verify recipient tag
        let pTags = giftWrap.tags.filter { $0[0] == "p" }
        XCTAssertEqual(pTags.count, 1, "Should have exactly one recipient tag")
        XCTAssertEqual(pTags[0][1], recipientPublicKey)

        // Gift wrap author should be random (not the sender)
        XCTAssertNotEqual(giftWrap.pubkey, senderPublicKey, "Gift wrap should use random key")
    }

    func testWrapNonSealFails() async throws {
        let nonSeal = NDKEvent(
            kind: EventKind.textNote, // Not a seal
            content: "content",
            tags: [],
            pubkey: senderPublicKey
        )

        do {
            _ = try await NIP59.wrap(
                seal: nonSeal,
                recipientPubkey: recipientPublicKey
            )
            XCTFail("Should not wrap non-seal events")
        } catch NIP59.NIP59Error.wrapFailed(_) {
            // Expected
        }
    }

    // MARK: - Unwrap Tests

    func testUnwrapGiftWrap() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipientSigner = try NDKPrivateKeySigner(privateKey: recipientPrivateKey)

        // Create rumor
        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Secret message",
            tags: [["t", "secret"]],
            pubkey: senderPublicKey
        )

        // Seal and wrap
        let seal = try await NIP59.seal(
            rumor: rumor,
            signer: senderSigner,
            recipientPubkey: recipientPublicKey
        )

        let giftWrap = try await NIP59.wrap(
            seal: seal,
            recipientPubkey: recipientPublicKey
        )

        // Unwrap
        let unwrappedSeal = try await NIP59.unwrap(
            giftWrap: giftWrap,
            recipientSigner: recipientSigner
        )

        // Verify unwrapped seal
        XCTAssertEqual(unwrappedSeal.kind, EventKind.seal)
        XCTAssertEqual(unwrappedSeal.pubkey, senderPublicKey)
        XCTAssertEqual(unwrappedSeal.id, seal.id, "Should recover original seal")
    }

    func testUnwrapRejectsTamperedGiftWrapSignature() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipientSigner = try NDKPrivateKeySigner(privateKey: recipientPrivateKey)
        let giftWrap = try await makeGiftWrap(senderSigner: senderSigner)

        let tamperedGiftWrap = NDKEvent(
            id: giftWrap.id,
            pubkey: giftWrap.pubkey,
            createdAt: giftWrap.createdAt,
            kind: giftWrap.kind,
            tags: giftWrap.tags,
            content: giftWrap.content + "tampered",
            sig: giftWrap.sig
        )

        do {
            _ = try await NIP59.unwrap(
                giftWrap: tamperedGiftWrap,
                recipientSigner: recipientSigner
            )
            XCTFail("Should reject a gift wrap whose signed payload was changed")
        } catch NIP59.NIP59Error.invalidGiftWrap(_) {
            // Expected
        }
    }

    func testUnwrapRejectsGiftWrapNotAddressedToRecipient() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipientSigner = try NDKPrivateKeySigner(privateKey: recipientPrivateKey)
        let wrongRecipientSigner = try NDKPrivateKeySigner.generate()
        let wrongRecipientPubkey = try await wrongRecipientSigner.pubkey

        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Secret message",
            tags: [],
            pubkey: senderPublicKey
        )
        let seal = try await NIP59.seal(
            rumor: rumor,
            signer: senderSigner,
            recipientPubkey: recipientPublicKey
        )
        let wrongTaggedGiftWrap = try await signedGiftWrap(
            seal: seal,
            encryptedTo: recipientPublicKey,
            taggedRecipient: wrongRecipientPubkey
        )

        do {
            _ = try await NIP59.unwrap(
                giftWrap: wrongTaggedGiftWrap,
                recipientSigner: recipientSigner
            )
            XCTFail("Should reject a gift wrap whose p tag does not address the recipient")
        } catch NIP59.NIP59Error.invalidGiftWrap(_) {
            // Expected
        }
    }

    // MARK: - Unseal Tests

    func testUnsealEvent() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipientSigner = try NDKPrivateKeySigner(privateKey: recipientPrivateKey)

        // Create rumor
        let originalRumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Secret message",
            tags: [["t", "secret"]],
            pubkey: senderPublicKey,
            createdAt: 1_234_567_890
        )

        // Seal
        let seal = try await NIP59.seal(
            rumor: originalRumor,
            signer: senderSigner,
            recipientPubkey: recipientPublicKey
        )

        // Unseal
        let unsealedRumor = try await NIP59.unseal(
            seal: seal,
            recipientSigner: recipientSigner
        )

        // Verify unsealed rumor matches original
        XCTAssertEqual(unsealedRumor.kind, originalRumor.kind)
        XCTAssertEqual(unsealedRumor.content, originalRumor.content)
        XCTAssertEqual(unsealedRumor.pubkey, originalRumor.pubkey)
        XCTAssertEqual(unsealedRumor.createdAt, originalRumor.createdAt)
        XCTAssertEqual(unsealedRumor.tags, originalRumor.tags)
    }

    func testUnsealRejectsTamperedSealSignature() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipientSigner = try NDKPrivateKeySigner(privateKey: recipientPrivateKey)
        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Secret message",
            tags: [],
            pubkey: senderPublicKey
        )
        let seal = try await NIP59.seal(
            rumor: rumor,
            signer: senderSigner,
            recipientPubkey: recipientPublicKey
        )

        let tamperedSeal = NDKEvent(
            id: seal.id,
            pubkey: seal.pubkey,
            createdAt: seal.createdAt + 1,
            kind: seal.kind,
            tags: seal.tags,
            content: seal.content,
            sig: seal.sig
        )

        do {
            _ = try await NIP59.unseal(
                seal: tamperedSeal,
                recipientSigner: recipientSigner
            )
            XCTFail("Should reject a seal whose signed payload was changed")
        } catch NIP59.NIP59Error.unwrapFailed(_) {
            // Expected
        }
    }

    func testUnsealRejectsSignedInnerRumor() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipientSigner = try NDKPrivateKeySigner(privateKey: recipientPrivateKey)
        let signedInnerEvent = try await signedEvent(
            signer: senderSigner,
            kind: EventKind.textNote,
            content: "This should have stayed unsigned",
            tags: []
        )
        let seal = try await signedSeal(
            payloadJSON: signedInnerEvent.toJSON(),
            signer: senderSigner,
            recipientPubkey: recipientPublicKey
        )

        do {
            _ = try await NIP59.unseal(
                seal: seal,
                recipientSigner: recipientSigner
            )
            XCTFail("Should reject a sealed payload that contains a signed inner event")
        } catch NIP59.NIP59Error.invalidRumor(_) {
            // Expected
        }
    }

    // MARK: - Full Flow Tests

    func testFullSealAndWrapFlow() async throws {
        let senderSigner = try NDKPrivateKeySigner(privateKey: senderPrivateKey)
        let recipientSigner = try NDKPrivateKeySigner(privateKey: recipientPrivateKey)

        let rumor = NIP59.createRumor(
            kind: EventKind.chatMessage,
            content: "Hello from NIP-59!",
            tags: [["subject", "Test Message"]],
            pubkey: senderPublicKey
        )

        // Seal and wrap in one operation
        let giftWrap = try await NIP59.sealAndWrap(
            rumor: rumor,
            signer: senderSigner,
            recipientPubkey: recipientPublicKey
        )

        // Verify gift wrap
        XCTAssertEqual(giftWrap.kind, EventKind.giftWrap)
        XCTAssertTrue(giftWrap.tags.contains { $0[0] == "p" && $0[1] == recipientPublicKey })

        // Unwrap and unseal in one operation
        let recovered = try await NIP59.unwrapAndUnseal(
            giftWrap: giftWrap,
            recipientSigner: recipientSigner
        )

        // Verify recovered rumor
        XCTAssertEqual(recovered.kind, rumor.kind)
        XCTAssertEqual(recovered.content, rumor.content)
        XCTAssertEqual(recovered.pubkey, rumor.pubkey)
        XCTAssertEqual(recovered.tags, rumor.tags)
    }

    // MARK: - JSON Serialization Tests

    func testEventJSONSerialization() throws {
        let event = NDKEvent(
            kind: EventKind.textNote,
            content: "Test content",
            tags: [["t", "test"], ["p", recipientPublicKey]],
            pubkey: senderPublicKey,
            createdAt: 1_234_567_890
        )

        // Serialize to JSON
        let json = try event.toJSON()
        XCTAssertFalse(json.isEmpty)

        // Deserialize from JSON
        let recovered = try NDKEvent.fromJSON(json)

        XCTAssertEqual(recovered.kind, event.kind)
        XCTAssertEqual(recovered.content, event.content)
        XCTAssertEqual(recovered.pubkey, event.pubkey)
        XCTAssertEqual(recovered.createdAt, event.createdAt)
        XCTAssertEqual(recovered.tags, event.tags)
    }

    func testRumorJSONSerialization() throws {
        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Rumor content",
            tags: [["e", "eventId"]],
            pubkey: senderPublicKey,
            createdAt: 9_876_543_210
        )

        let json = try rumor.toJSON()
        let recovered = try NDKEvent.fromJSON(json)

        XCTAssertTrue(recovered.isRumor)
        XCTAssertEqual(recovered.content, rumor.content)
        XCTAssertEqual(recovered.tags, rumor.tags)
    }

    private func makeGiftWrap(senderSigner: NDKPrivateKeySigner) async throws -> NDKEvent {
        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Secret message",
            tags: [],
            pubkey: senderPublicKey
        )
        let seal = try await NIP59.seal(
            rumor: rumor,
            signer: senderSigner,
            recipientPubkey: recipientPublicKey
        )
        return try await NIP59.wrap(
            seal: seal,
            recipientPubkey: recipientPublicKey
        )
    }

    private func signedEvent(
        signer: NDKPrivateKeySigner,
        kind: Kind,
        content: String,
        tags: [Tag]
    ) async throws -> NDKEvent {
        let unsignedEvent = NDKEvent(
            id: "",
            pubkey: try await signer.pubkey,
            createdAt: .now,
            kind: kind,
            tags: tags,
            content: content,
            sig: ""
        )
        let eventID = try unsignedEvent.calculateID()
        let eventToSign = NDKEvent(
            id: eventID,
            pubkey: unsignedEvent.pubkey,
            createdAt: unsignedEvent.createdAt,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            content: unsignedEvent.content,
            sig: ""
        )
        let signature = try await signer.sign(eventToSign)
        return NDKEvent(
            id: eventID,
            pubkey: unsignedEvent.pubkey,
            createdAt: unsignedEvent.createdAt,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            content: unsignedEvent.content,
            sig: signature
        )
    }

    private func signedSeal(
        payloadJSON: String,
        signer: NDKPrivateKeySigner,
        recipientPubkey: PublicKey
    ) async throws -> NDKEvent {
        let encryptedContent = try NIP44.encrypt(
            message: payloadJSON,
            privateKey: signer.privateKeyForNIP59,
            pubkey: recipientPubkey
        )
        return try await signedEvent(
            signer: signer,
            kind: EventKind.seal,
            content: encryptedContent,
            tags: []
        )
    }

    private func signedGiftWrap(
        seal: NDKEvent,
        encryptedTo recipientPubkey: PublicKey,
        taggedRecipient: PublicKey
    ) async throws -> NDKEvent {
        let wrapperSigner = try NDKPrivateKeySigner.generate()
        let encryptedContent = try NIP44.encrypt(
            message: seal.toJSON(),
            privateKey: wrapperSigner.privateKeyForNIP59,
            pubkey: recipientPubkey
        )
        return try await signedEvent(
            signer: wrapperSigner,
            kind: EventKind.giftWrap,
            content: encryptedContent,
            tags: [["p", taggedRecipient]]
        )
    }
}
