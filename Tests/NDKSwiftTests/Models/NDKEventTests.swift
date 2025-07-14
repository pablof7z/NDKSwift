import XCTest
import CryptoSwift
@testable import NDKSwift

final class NDKEventTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func test_init_withAllParameters_createsEvent() {
        // Arrange
        let id = "4b697394206581b03ca5222b37449a9cdca1741b122d78defc177444e2536f49"
        let pubkey = TestKeys.alicePublicKey
        let createdAt = Timestamp(1640995200)
        let kind: Kind = 1
        let tags: [Tag] = [["p", TestKeys.bobPublicKey], ["e", "eventid123"]]
        let content = "Hello, Nostr!"
        let sig = "264d5a4e2a47fad3e21b3e949e80a139f04bcb72e8ec608ec9e6cc0470961a7de2c47762885864575be49b0b88bec3635ba98e4265ea4f7d5b947c4bb2bdddf8"
        
        // Act
        let event = NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
        
        // Assert
        XCTAssertEqual(event.id, id)
        XCTAssertEqual(event.pubkey, pubkey)
        XCTAssertEqual(event.createdAt, createdAt)
        XCTAssertEqual(event.kind, kind)
        XCTAssertEqual(event.tags, tags)
        XCTAssertEqual(event.content, content)
        XCTAssertEqual(event.sig, sig)
    }
    
    // MARK: - Codable Tests
    
    func test_encode_decode_roundTrip() throws {
        // Arrange
        let originalEvent = TestEvents.preSignedValidEvent()
        
        // Act - Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(originalEvent)
        
        // Assert - Valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["id"] as? String, originalEvent.id)
        XCTAssertEqual(json?["pubkey"] as? String, originalEvent.pubkey)
        XCTAssertEqual(json?["created_at"] as? Int, Int(originalEvent.createdAt))
        XCTAssertEqual(json?["kind"] as? Int, originalEvent.kind)
        XCTAssertEqual(json?["content"] as? String, originalEvent.content)
        XCTAssertEqual(json?["sig"] as? String, originalEvent.sig)
        
        // Act - Decode
        let decoder = JSONDecoder()
        let decodedEvent = try decoder.decode(NDKEvent.self, from: data)
        
        // Assert - Events match
        assertEventsEqual(originalEvent, decodedEvent)
    }
    
    func test_decode_withMissingID_throws() {
        // Arrange
        let json = """
        {
            "pubkey": "\(TestKeys.alicePublicKey)",
            "created_at": 1640995200,
            "kind": 1,
            "tags": [],
            "content": "Hello",
            "sig": "0000000000000000000000000000000000000000000000000000000000000000"
        }
        """
        let data = json.data(using: .utf8)!
        
        // Act & Assert
        XCTAssertThrowsError(try JSONDecoder().decode(NDKEvent.self, from: data)) { error in
            guard let ndkError = error as? NDKError,
                  case .invalidEventID = ndkError else {
                XCTFail("Expected NDKError.invalidEventID")
                return
            }
        }
    }
    
    func test_decode_withMissingSig_throws() {
        // Arrange
        let json = """
        {
            "id": "4b697394206581b03ca5222b37449a9cdca1741b122d78defc177444e2536f49",
            "pubkey": "\(TestKeys.alicePublicKey)",
            "created_at": 1640995200,
            "kind": 1,
            "tags": [],
            "content": "Hello"
        }
        """
        let data = json.data(using: .utf8)!
        
        // Act & Assert
        XCTAssertThrowsError(try JSONDecoder().decode(NDKEvent.self, from: data)) { error in
            guard let ndkError = error as? NDKError,
                  case .invalidSignature = ndkError else {
                XCTFail("Expected NDKError.invalidSignature")
                return
            }
        }
    }
    
    // MARK: - Equatable & Hashable Tests
    
    func test_equatable_sameID_areEqual() {
        // Arrange
        let event1 = TestEvents.preSignedValidEvent()
        let event2 = TestEvents.preSignedValidEvent()
        
        // Act & Assert
        XCTAssertEqual(event1, event2)
    }
    
    func test_equatable_differentID_areNotEqual() {
        // Arrange
        let event1 = TestEvents.textNoteEvent(content: "Hello")
        let event2 = TestEvents.textNoteEvent(content: "World")
        
        // Act & Assert
        XCTAssertNotEqual(event1, event2)
    }
    
    func test_hashable_sameID_haveSameHash() {
        // Arrange
        let event1 = TestEvents.preSignedValidEvent()
        let event2 = TestEvents.preSignedValidEvent()
        
        // Act & Assert
        XCTAssertEqual(event1.hashValue, event2.hashValue)
    }
    
    func test_hashable_canBeUsedInSet() {
        // Arrange
        let event1 = TestEvents.textNoteEvent(content: "Hello")
        let event2 = TestEvents.textNoteEvent(content: "World")
        let event3 = TestEvents.textNoteEvent(content: "Hello") // Same as event1
        
        // Act
        let set = Set([event1, event2, event3])
        
        // Assert - event3 should not be added as it's equal to event1
        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(event1))
        XCTAssertTrue(set.contains(event2))
    }
    
    // MARK: - Tag Helper Tests
    
    func test_tags_withName_filtersCorrectly() {
        // Arrange
        let event = TestEvents.eventWithMultipleTags()
        
        // Act
        let eTags = event.tags(withName: "e")
        let pTags = event.tags(withName: "p")
        let tTags = event.tags(withName: "t")
        let zTags = event.tags(withName: "z") // Non-existent
        
        // Assert
        XCTAssertEqual(eTags.count, 2)
        XCTAssertEqual(pTags.count, 2)
        XCTAssertEqual(tTags.count, 2)
        XCTAssertEqual(zTags.count, 0)
    }
    
    func test_tag_withName_returnsFirstTag() {
        // Arrange
        let event = TestEvents.eventWithMultipleTags()
        
        // Act
        let eTag = event.tag(withName: "e")
        let dTag = event.tag(withName: "d")
        let zTag = event.tag(withName: "z") // Non-existent
        
        // Assert
        XCTAssertNotNil(eTag)
        XCTAssertEqual(eTag?[1], "event1")
        XCTAssertNotNil(dTag)
        XCTAssertEqual(dTag?[1], "unique-identifier")
        XCTAssertNil(zTag)
    }
    
    func test_tagValue_returnsCorrectValue() {
        // Arrange
        let event = TestEvents.eventWithMultipleTags()
        
        // Act
        let dValue = event.tagValue("d")
        let nonExistent = event.tagValue("z")
        
        // Assert
        XCTAssertEqual(dValue, "unique-identifier")
        XCTAssertNil(nonExistent)
    }
    
    func test_referencedEventIds_returnsCorrectIds() {
        // Arrange
        let event = TestEvents.eventWithMultipleTags()
        
        // Act
        let references = event.referencedEventIds
        
        // Assert
        XCTAssertEqual(references.count, 2)
        XCTAssertTrue(references.contains("event1"))
        XCTAssertTrue(references.contains("event2"))
    }
    
    func test_referencedPubkeys_returnsCorrectPubkeys() {
        // Arrange
        let event = TestEvents.eventWithMultipleTags()
        
        // Act
        let references = event.referencedPubkeys
        
        // Assert
        XCTAssertEqual(references.count, 2)
        XCTAssertTrue(references.contains(TestKeys.bobPublicKey))
        XCTAssertTrue(references.contains(TestKeys.charliePublicKey))
    }
    
    // MARK: - Event Type Tests
    
    func test_isReplaceable_returnsCorrectValue() {
        // Arrange
        let regularEvent = TestEvents.textNoteEvent()
        let metadataEvent = NDKEvent(
            id: "test",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 0, // Metadata
            tags: [],
            content: "{}",
            sig: ""
        )
        let replaceableEvent = NDKEvent(
            id: "test2",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 10001, // Replaceable
            tags: [],
            content: "",
            sig: ""
        )
        
        // Act & Assert
        XCTAssertFalse(regularEvent.isReplaceable)
        XCTAssertTrue(metadataEvent.isReplaceable)
        XCTAssertTrue(replaceableEvent.isReplaceable)
    }
    
    func test_isEphemeral_returnsCorrectValue() {
        // Arrange
        let regularEvent = TestEvents.textNoteEvent()
        let ephemeralEvent = NDKEvent(
            id: "test",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 20001, // Ephemeral
            tags: [],
            content: "",
            sig: ""
        )
        
        // Act & Assert
        XCTAssertFalse(regularEvent.isEphemeral)
        XCTAssertTrue(ephemeralEvent.isEphemeral)
    }
    
    func test_isParameterizedReplaceable_returnsCorrectValue() {
        // Arrange
        let regularEvent = TestEvents.textNoteEvent()
        let parameterizedEvent = NDKEvent(
            id: "test",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 30023, // Parameterized replaceable
            tags: [["d", "identifier"]],
            content: "",
            sig: ""
        )
        
        // Act & Assert
        XCTAssertFalse(regularEvent.isParameterizedReplaceable)
        XCTAssertTrue(parameterizedEvent.isParameterizedReplaceable)
    }
    
    func test_isProtected_detectsProtectedEvents() {
        // Arrange
        let regularEvent = TestEvents.textNoteEvent()
        let protectedEvent = NDKEvent(
            id: "test",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 1,
            tags: [["-"]],
            content: "Protected content",
            sig: ""
        )
        
        // Act & Assert
        XCTAssertFalse(regularEvent.isProtected)
        XCTAssertTrue(protectedEvent.isProtected)
    }
    
    // MARK: - Encoding Tests
    
    func test_encode_toNIP19_formats() throws {
        // Arrange
        let event = TestEvents.preSignedValidEvent()
        let addressableEvent = NDKEvent(
            id: "test",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 30023,
            tags: [["d", "identifier"]],
            content: "",
            sig: ""
        )
        
        // Act
        let note = try event.encode()
        let nevent = try event.encode(includeRelays: true, relayHints: ["wss://relay.example.com"])
        let naddr = try addressableEvent.encode()
        
        // Assert
        XCTAssertTrue(note.hasPrefix("note1"))
        XCTAssertTrue(nevent.hasPrefix("nevent1"))
        XCTAssertTrue(naddr.hasPrefix("naddr1"))
    }
    
    // MARK: - Reply/Thread Tests
    
    func test_isReply_detectsReplies() {
        // Arrange
        let originalEvent = TestEvents.textNoteEvent()
        let replyEvent = TestEvents.unsignedReplyEvent(to: originalEvent.id)
        let regularEvent = TestEvents.textNoteEvent(content: "Not a reply")
        
        // Act & Assert
        XCTAssertTrue(replyEvent.isReply)
        XCTAssertFalse(originalEvent.isReply)
        XCTAssertFalse(regularEvent.isReply)
    }
    
    func test_replyEventId_returnsCorrectId() {
        // Arrange
        let replyId = "reply123"
        let event = NDKEvent(
            id: "test",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 1,
            tags: [["e", "root123", "", "root"], ["e", replyId, "", "reply"]],
            content: "Reply",
            sig: ""
        )
        
        // Act
        let reply = event.replyEventId
        
        // Assert
        XCTAssertEqual(reply, replyId)
    }
    
    // MARK: - Validation Tests
    
    func test_validate_withValidEvent_passes() throws {
        // Arrange
        let event = TestEvents.preSignedValidEvent()
        
        // Act & Assert - Should not throw
        try event.validate()
    }
    
    func test_validate_withInvalidPubkey_throws() {
        // Arrange
        let event = NDKEvent(
            id: "4b697394206581b03ca5222b37449a9cdca1741b122d78defc177444e2536f49",
            pubkey: "invalid",
            createdAt: 1640995200,
            kind: 1,
            tags: [],
            content: "Hello",
            sig: "264d5a4e2a47fad3e21b3e949e80a139f04bcb72e8ec608ec9e6cc0470961a7de2c47762885864575be49b0b88bec3635ba98e4265ea4f7d5b947c4bb2bdddf8"
        )
        
        // Act & Assert
        XCTAssertThrowsError(try event.validate()) { error in
            guard let ndkError = error as? NDKError,
                  case .invalidPublicKey = ndkError else {
                XCTFail("Expected NDKError.invalidPublicKey")
                return
            }
        }
    }
    
    // MARK: - Serialization Tests
    
    func test_serialize_producesValidJSON() throws {
        // Arrange
        let event = TestEvents.preSignedValidEvent()
        
        // Act
        let serialized = try event.serialize()
        
        // Assert
        XCTAssertFalse(serialized.isEmpty)
        let data = serialized.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["id"] as? String, event.id)
    }
    
    func test_toJSON_aliasWorks() throws {
        // Arrange
        let event = TestEvents.preSignedValidEvent()
        
        // Act
        let json1 = try event.serialize()
        let json2 = try event.toJSON()
        
        // Assert
        XCTAssertEqual(json1, json2)
    }
    
    func test_rawEvent_returnsDictionary() {
        // Arrange
        let event = TestEvents.preSignedValidEvent()
        
        // Act
        let raw = event.rawEvent()
        
        // Assert
        XCTAssertEqual(raw["id"] as? String, event.id)
        XCTAssertEqual(raw["pubkey"] as? String, event.pubkey)
        XCTAssertEqual(raw["created_at"] as? Timestamp, event.createdAt)
        XCTAssertEqual(raw["kind"] as? Kind, event.kind)
        XCTAssertEqual(raw["content"] as? String, event.content)
        XCTAssertEqual(raw["sig"] as? String, event.sig)
    }
    
    func test_calculateID_producesCorrectHash() throws {
        // Arrange
        let event = NDKEvent(
            id: "", // Will be calculated
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 1,
            tags: [],
            content: "Hello, Nostr!",
            sig: ""
        )
        
        // Act
        let calculatedId = try event.calculateID()
        
        // Assert
        XCTAssertEqual(calculatedId.count, 64)
        
        // Verify it matches the expected format
        XCTAssertTrue(calculatedId.allSatisfy { $0.isHexDigit })
    }
    
    func test_verifySignature_withValidSignature_returnsTrue() {
        // Arrange
        let event = TestEvents.preSignedValidEvent()
        
        // Act
        let isValid = event.verifySignature()
        
        // Assert
        XCTAssertTrue(isValid)
    }
    
    func test_verifySignature_withInvalidSignature_returnsFalse() {
        // Arrange
        let event = TestEvents.preSignedInvalidEvent()
        
        // Act
        let isValid = event.verifySignature()
        
        // Assert
        XCTAssertFalse(isValid)
    }
    
    func test_tagAddress_forParameterizedReplaceable() {
        // Arrange
        let event = NDKEvent(
            id: "test",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 30023,
            tags: [["d", "my-article"]],
            content: "",
            sig: ""
        )
        
        // Act
        let address = event.tagAddress
        
        // Assert
        XCTAssertEqual(address, "30023:\(TestKeys.alicePublicKey):my-article")
    }
    
    func test_tagAddress_forRegularReplaceable() {
        // Arrange
        let event = NDKEvent(
            id: "test",
            pubkey: TestKeys.alicePublicKey,
            createdAt: 1640995200,
            kind: 0, // Metadata
            tags: [],
            content: "{}",
            sig: ""
        )
        
        // Act
        let address = event.tagAddress
        
        // Assert
        XCTAssertEqual(address, "0:\(TestKeys.alicePublicKey)")
    }
    
    func test_tagAddress_forRegularEvent() {
        // Arrange
        let event = TestEvents.textNoteEvent()
        
        // Act
        let address = event.tagAddress
        
        // Assert
        XCTAssertEqual(address, event.id)
    }
}

// Extension to check if character is hex digit
private extension Character {
    var isHexDigit: Bool {
        return ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}