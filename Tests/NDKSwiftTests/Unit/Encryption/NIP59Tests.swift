import XCTest
@testable import NDKSwiftCore

final class NIP59Tests: XCTestCase {
    
    let senderPrivateKey = "f09ac9b695d0a4c6daa418fe95b977eea20f54d9545592bc36a4f9e14f3eb840"
    let senderPublicKey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    
    let recipientPrivateKey = "5393a825e5892d8e18d4a5ea61ced105e8bb2a106f42876be3a40522e0b13747"
    let recipientPublicKey = "483e062bd1148c64e10abcdcc42444c2f6c5d9115a7925c9e0c0b4dc84cd8f0f"
    
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
            createdAt: 1234567890
        )
        
        XCTAssertEqual(rumor.kind, EventKind.textNote)
        XCTAssertEqual(rumor.content, "Test rumor content")
        XCTAssertEqual(rumor.pubkey, senderPublicKey)
        XCTAssertEqual(rumor.createdAt, 1234567890)
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
        
        let seal = try await NIP59.seal(
            rumor: rumor,
            signer: signer,
            recipientPubkey: recipientPublicKey
        )
        
        // Verify seal properties
        XCTAssertEqual(seal.kind, EventKind.seal)
        XCTAssertEqual(seal.pubkey, senderPublicKey)
        XCTAssertFalse(seal.content.isEmpty, "Seal should have encrypted content")
        XCTAssertFalse(seal.id.isEmpty, "Seal should be signed with ID")
        XCTAssertFalse(seal.sig.isEmpty, "Seal should be signed")
        XCTAssertEqual(seal.tags.count, 0, "Seal should have no tags")
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
            createdAt: 1234567890
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
            createdAt: 1234567890
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
            createdAt: 9876543210
        )
        
        let json = try rumor.toJSON()
        let recovered = try NDKEvent.fromJSON(json)
        
        XCTAssertTrue(recovered.isRumor)
        XCTAssertEqual(recovered.content, rumor.content)
        XCTAssertEqual(recovered.tags, rumor.tags)
    }
}