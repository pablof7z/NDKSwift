import XCTest
@testable import NDKSwift

final class NDKEventTests: NDKTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        // Given
        let id = "test_event_id_32_bytes_hex_string_here_1234567890abcdef"
        let pubkey = TestFixtures.Keys.alice.publicKey
        let createdAt = Timestamp(1234567890)
        let kind = EventKind.textNote
        let tags: [Tag] = [["e", "referenced_event_id"], ["p", "referenced_pubkey"]]
        let content = "Hello, Nostr!"
        let sig = "test_signature_64_bytes_hex_string_here_1234567890abcdef1234567890abcdef"
        
        // When
        let event = NDKEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
        
        // Then
        XCTAssertEqual(event.id, id)
        XCTAssertEqual(event.pubkey, pubkey)
        XCTAssertEqual(event.createdAt, createdAt)
        XCTAssertEqual(event.kind, kind)
        XCTAssertEqual(event.tags, tags)
        XCTAssertEqual(event.content, content)
        XCTAssertEqual(event.sig, sig)
    }
    
    // MARK: - Codable Tests
    
    func testEncodingDecoding() throws {
        // Given
        let originalEvent = EventTestFactory.createEvent(
            kind: EventKind.textNote,
            content: "Test content",
            tags: [["t", "test"], ["p", TestFixtures.Keys.bob.publicKey]]
        )
        
        // When
        let encoded = try JSONEncoder().encode(originalEvent)
        let decoded = try JSONDecoder().decode(NDKEvent.self, from: encoded)
        
        // Then
        XCTAssertEqual(decoded.id, originalEvent.id)
        XCTAssertEqual(decoded.pubkey, originalEvent.pubkey)
        XCTAssertEqual(decoded.createdAt, originalEvent.createdAt)
        XCTAssertEqual(decoded.kind, originalEvent.kind)
        XCTAssertEqual(decoded.tags, originalEvent.tags)
        XCTAssertEqual(decoded.content, originalEvent.content)
        XCTAssertEqual(decoded.sig, originalEvent.sig)
    }
    
    func testDecodingFromJSON() throws {
        // Given
        let json = """
        {
            "id": "44e1827635450ebb3251586e486e3dac13607d2bd4c7225a9b9d0cf105711a26",
            "pubkey": "32e1827635450ebb3251586e486e3dac13607d2bd4c7225a9b9d0cf105711a26",
            "created_at": 1234567890,
            "kind": 1,
            "tags": [["e", "ref_event"], ["p", "ref_pubkey"]],
            "content": "Test event",
            "sig": "signature_hex_64_bytes_1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab"
        }
        """
        
        // When
        let data = json.data(using: .utf8)!
        let event = try JSONDecoder().decode(NDKEvent.self, from: data)
        
        // Then
        XCTAssertEqual(event.id, "44e1827635450ebb3251586e486e3dac13607d2bd4c7225a9b9d0cf105711a26")
        XCTAssertEqual(event.pubkey, "32e1827635450ebb3251586e486e3dac13607d2bd4c7225a9b9d0cf105711a26")
        XCTAssertEqual(event.createdAt, 1234567890)
        XCTAssertEqual(event.kind, 1)
        XCTAssertEqual(event.tags.count, 2)
        XCTAssertEqual(event.content, "Test event")
    }
    
    func testDecodingWithMissingID() throws {
        // Given
        let json = """
        {
            "pubkey": "32e1827635450ebb3251586e486e3dac13607d2bd4c7225a9b9d0cf105711a26",
            "created_at": 1234567890,
            "kind": 1,
            "tags": [],
            "content": "Test event",
            "sig": "signature_hex"
        }
        """
        
        // When/Then
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(NDKEvent.self, from: data))
    }
    
    func testDecodingWithMissingSignature() throws {
        // Given
        let json = """
        {
            "id": "44e1827635450ebb3251586e486e3dac13607d2bd4c7225a9b9d0cf105711a26",
            "pubkey": "32e1827635450ebb3251586e486e3dac13607d2bd4c7225a9b9d0cf105711a26",
            "created_at": 1234567890,
            "kind": 1,
            "tags": [],
            "content": "Test event"
        }
        """
        
        // When/Then
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(NDKEvent.self, from: data))
    }
    
    // MARK: - Equatable & Hashable Tests
    
    func testEquality() {
        // Given
        let event1 = EventTestFactory.createEvent(content: "Content 1", id: "same_id")
        let event2 = EventTestFactory.createEvent(content: "Content 2", id: "same_id")
        let event3 = EventTestFactory.createEvent(content: "Content 1", id: "different_id")
        
        // Then
        XCTAssertEqual(event1, event2) // Same ID, different content
        XCTAssertNotEqual(event1, event3) // Different ID
    }
    
    func testHashable() {
        // Given
        let event1 = EventTestFactory.createEvent(id: "same_id")
        let event2 = EventTestFactory.createEvent(id: "same_id")
        let event3 = EventTestFactory.createEvent(id: "different_id")
        
        var set = Set<NDKEvent>()
        
        // When
        set.insert(event1)
        set.insert(event2)
        set.insert(event3)
        
        // Then
        XCTAssertEqual(set.count, 2) // event1 and event2 are considered the same
    }
    
    // MARK: - Validation Tests
    
    func testValidateWithValidEvent() async throws {
        // Given
        let ndk = createTestNDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let (event, _) = try await ndk.publish {
            $0.kind(EventKind.textNote)
              .content("Valid event")
        }
        
        // When/Then
        XCTAssertNoThrow(try event.validate())
    }
    
    func testValidateWithInvalidPublicKey() {
        // Given
        let event = EventTestFactory.createEvent(pubkey: "invalid_pubkey")
        
        // When/Then
        XCTAssertThrowsError(try event.validate()) { error in
            if case NDKError.invalidPublicKey = error {
                // Expected error
            } else {
                XCTFail("Expected invalidPublicKey error, got \(error)")
            }
        }
    }
    
    func testValidateWithInvalidEventID() {
        // Given
        let event = EventTestFactory.createEvent(id: "invalid_id")
        
        // When/Then
        XCTAssertThrowsError(try event.validate()) { error in
            if case NDKError.invalidEventID = error {
                // Expected error
            } else {
                XCTFail("Expected invalidEventID error, got \(error)")
            }
        }
    }
    
    func testValidateWithInvalidSignature() {
        // Given
        let event = EventTestFactory.createEvent(sig: "invalid_sig")
        
        // When/Then
        XCTAssertThrowsError(try event.validate()) { error in
            if case NDKError.invalidSignature = error {
                // Expected error
            } else {
                XCTFail("Expected invalidSignature error, got \(error)")
            }
        }
    }
    
    // MARK: - Tag Helper Tests
    
    func testTagsWithName() {
        // Given
        let event = EventTestFactory.createEvent(
            tags: [
                ["e", "event1"],
                ["p", "pubkey1"],
                ["e", "event2"],
                ["p", "pubkey2"],
                ["t", "hashtag"]
            ]
        )
        
        // When
        let eTags = event.tags(withName: "e")
        let pTags = event.tags(withName: "p")
        let tTags = event.tags(withName: "t")
        let nonExistent = event.tags(withName: "x")
        
        // Then
        XCTAssertEqual(eTags.count, 2)
        XCTAssertEqual(eTags[0], ["e", "event1"])
        XCTAssertEqual(eTags[1], ["e", "event2"])
        
        XCTAssertEqual(pTags.count, 2)
        XCTAssertEqual(tTags.count, 1)
        XCTAssertEqual(nonExistent.count, 0)
    }
    
    func testTagWithName() {
        // Given
        let event = EventTestFactory.createEvent(
            tags: [
                ["e", "event1"],
                ["p", "pubkey1"],
                ["e", "event2"]
            ]
        )
        
        // When
        let firstETag = event.tag(withName: "e")
        let pTag = event.tag(withName: "p")
        let nonExistent = event.tag(withName: "x")
        
        // Then
        XCTAssertEqual(firstETag, ["e", "event1"])
        XCTAssertEqual(pTag, ["p", "pubkey1"])
        XCTAssertNil(nonExistent)
    }
    
    func testReferencedEventIds() {
        // Given
        let event = EventTestFactory.createEvent(
            tags: [
                ["e", "event1"],
                ["e", "event2", "relay"],
                ["e"], // Invalid tag with no ID
                ["p", "pubkey1"]
            ]
        )
        
        // When
        let eventIds = event.referencedEventIds
        
        // Then
        XCTAssertEqual(eventIds.count, 2)
        XCTAssertEqual(eventIds[0], "event1")
        XCTAssertEqual(eventIds[1], "event2")
    }
    
    func testReferencedPubkeys() {
        // Given
        let event = EventTestFactory.createEvent(
            tags: [
                ["p", "pubkey1"],
                ["p", "pubkey2", "relay"],
                ["p"], // Invalid tag with no pubkey
                ["e", "event1"]
            ]
        )
        
        // When
        let pubkeys = event.referencedPubkeys
        
        // Then
        XCTAssertEqual(pubkeys.count, 2)
        XCTAssertEqual(pubkeys[0], "pubkey1")
        XCTAssertEqual(pubkeys[1], "pubkey2")
    }
    
    func testTagValue() {
        // Given
        let event = EventTestFactory.createEvent(
            tags: [
                ["d", "identifier"],
                ["t", "hashtag"],
                ["empty"],
                ["p", "pubkey", "relay"]
            ]
        )
        
        // When
        let dValue = event.tagValue("d")
        let tValue = event.tagValue("t")
        let emptyValue = event.tagValue("empty")
        let nonExistent = event.tagValue("x")
        let pValue = event.tagValue("p")
        
        // Then
        XCTAssertEqual(dValue, "identifier")
        XCTAssertEqual(tValue, "hashtag")
        XCTAssertNil(emptyValue)
        XCTAssertNil(nonExistent)
        XCTAssertEqual(pValue, "pubkey")
    }
    
    func testClientTag() {
        // Given
        let eventWithFullClient = EventTestFactory.createEvent(
            tags: [["client", "MyClient", "31990:pubkey:identifier", "wss://relay.com"]]
        )
        let eventWithPartialClient = EventTestFactory.createEvent(
            tags: [["client", "MyClient", "", ""]]
        )
        let eventWithMinimalClient = EventTestFactory.createEvent(
            tags: [["client", "MyClient"]]
        )
        let eventWithoutClient = EventTestFactory.createEvent(tags: [])
        
        // When
        let fullClient = eventWithFullClient.clientTag
        let partialClient = eventWithPartialClient.clientTag
        let minimalClient = eventWithMinimalClient.clientTag
        let noClient = eventWithoutClient.clientTag
        
        // Then
        XCTAssertNotNil(fullClient)
        XCTAssertEqual(fullClient?.name, "MyClient")
        XCTAssertEqual(fullClient?.address, "31990:pubkey:identifier")
        XCTAssertEqual(fullClient?.relay, "wss://relay.com")
        
        XCTAssertNotNil(partialClient)
        XCTAssertEqual(partialClient?.name, "MyClient")
        XCTAssertNil(partialClient?.address)
        XCTAssertNil(partialClient?.relay)
        
        XCTAssertNotNil(minimalClient)
        XCTAssertEqual(minimalClient?.name, "MyClient")
        XCTAssertNil(minimalClient?.address)
        XCTAssertNil(minimalClient?.relay)
        
        XCTAssertNil(noClient)
    }
    
    // MARK: - Event Type Tests
    
    func testIsReply() {
        // Given
        let replyEvent = EventTestFactory.createEvent(
            tags: [["e", "parent_event", "", "reply"]]
        )
        let mentionEvent = EventTestFactory.createEvent(
            tags: [["e", "mentioned_event", "", "mention"]]
        )
        let simpleEvent = EventTestFactory.createEvent(
            tags: [["e", "some_event"]]
        )
        
        // Then
        XCTAssertTrue(replyEvent.isReply)
        XCTAssertFalse(mentionEvent.isReply)
        XCTAssertFalse(simpleEvent.isReply)
    }
    
    func testReplyEventId() {
        // Given
        let replyEvent = EventTestFactory.createEvent(
            tags: [
                ["e", "parent_event", "", "reply"],
                ["e", "another_event", "", "mention"]
            ]
        )
        let noReplyEvent = EventTestFactory.createEvent(
            tags: [["e", "some_event", "", "mention"]]
        )
        
        // Then
        XCTAssertEqual(replyEvent.replyEventId, "parent_event")
        XCTAssertNil(noReplyEvent.replyEventId)
    }
    
    func testIsEphemeral() {
        // Given
        let regularEvent = EventTestFactory.createEvent(kind: 1)
        let ephemeralEvent1 = EventTestFactory.createEvent(kind: 20000)
        let ephemeralEvent2 = EventTestFactory.createEvent(kind: 25000)
        let ephemeralEvent3 = EventTestFactory.createEvent(kind: 29999)
        let notEphemeral = EventTestFactory.createEvent(kind: 30000)
        
        // Then
        XCTAssertFalse(regularEvent.isEphemeral)
        XCTAssertTrue(ephemeralEvent1.isEphemeral)
        XCTAssertTrue(ephemeralEvent2.isEphemeral)
        XCTAssertTrue(ephemeralEvent3.isEphemeral)
        XCTAssertFalse(notEphemeral.isEphemeral)
    }
    
    func testIsReplaceable() {
        // Given
        let metadataEvent = EventTestFactory.createEvent(kind: EventKind.metadata)
        let contactsEvent = EventTestFactory.createEvent(kind: EventKind.contacts)
        let replaceableEvent1 = EventTestFactory.createEvent(kind: 10000)
        let replaceableEvent2 = EventTestFactory.createEvent(kind: 15000)
        let replaceableEvent3 = EventTestFactory.createEvent(kind: 19999)
        let regularEvent = EventTestFactory.createEvent(kind: 1)
        let ephemeralEvent = EventTestFactory.createEvent(kind: 20000)
        
        // Then
        XCTAssertTrue(metadataEvent.isReplaceable)
        XCTAssertTrue(contactsEvent.isReplaceable)
        XCTAssertTrue(replaceableEvent1.isReplaceable)
        XCTAssertTrue(replaceableEvent2.isReplaceable)
        XCTAssertTrue(replaceableEvent3.isReplaceable)
        XCTAssertFalse(regularEvent.isReplaceable)
        XCTAssertFalse(ephemeralEvent.isReplaceable)
    }
    
    func testIsParameterizedReplaceable() {
        // Given
        let paramReplaceable1 = EventTestFactory.createEvent(kind: 30000)
        let paramReplaceable2 = EventTestFactory.createEvent(kind: 35000)
        let paramReplaceable3 = EventTestFactory.createEvent(kind: 39999)
        let regularEvent = EventTestFactory.createEvent(kind: 1)
        let replaceableEvent = EventTestFactory.createEvent(kind: 10000)
        let notParamReplaceable = EventTestFactory.createEvent(kind: 40000)
        
        // Then
        XCTAssertTrue(paramReplaceable1.isParameterizedReplaceable)
        XCTAssertTrue(paramReplaceable2.isParameterizedReplaceable)
        XCTAssertTrue(paramReplaceable3.isParameterizedReplaceable)
        XCTAssertFalse(regularEvent.isParameterizedReplaceable)
        XCTAssertFalse(replaceableEvent.isParameterizedReplaceable)
        XCTAssertFalse(notParamReplaceable.isParameterizedReplaceable)
    }
    
    func testIsProtected() {
        // Given
        let protectedEvent = EventTestFactory.createEvent(
            tags: [["-"]]
        )
        let unprotectedEvent = EventTestFactory.createEvent(
            tags: [["e", "some_event"]]
        )
        
        // Then
        XCTAssertTrue(protectedEvent.isProtected)
        XCTAssertFalse(unprotectedEvent.isProtected)
    }
    
    // MARK: - Tag Address Tests
    
    func testTagAddressForParameterizedReplaceable() {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let event = EventTestFactory.createEvent(
            kind: 30000,
            tags: [["d", "my-identifier"]],
            pubkey: pubkey
        )
        
        // When
        let tagAddress = event.tagAddress
        
        // Then
        XCTAssertEqual(tagAddress, "30000:\(pubkey):my-identifier")
    }
    
    func testTagAddressForParameterizedReplaceableWithoutDTag() {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let event = EventTestFactory.createEvent(
            kind: 30000,
            tags: [],
            pubkey: pubkey
        )
        
        // When
        let tagAddress = event.tagAddress
        
        // Then
        XCTAssertEqual(tagAddress, "30000:\(pubkey):")
    }
    
    func testTagAddressForReplaceable() {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let event = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            pubkey: pubkey
        )
        
        // When
        let tagAddress = event.tagAddress
        
        // Then
        XCTAssertEqual(tagAddress, "0:\(pubkey):")
    }
    
    func testTagAddressForRegularEvent() {
        // Given
        let event = EventTestFactory.createEvent(kind: 1)
        
        // When
        let tagAddress = event.tagAddress
        
        // Then
        XCTAssertEqual(tagAddress, event.id)
    }
    
    // MARK: - Tag Reference Tests
    
    func testTagReferenceForParameterizedReplaceable() {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let event = EventTestFactory.createEvent(
            kind: 30000,
            tags: [["d", "identifier"]],
            pubkey: pubkey
        )
        
        // When
        let tagRef = event.tagReference()
        
        // Then
        XCTAssertEqual(tagRef.count, 5)
        XCTAssertEqual(tagRef[0], "a")
        XCTAssertEqual(tagRef[1], "30000:\(pubkey):identifier")
        XCTAssertEqual(tagRef[2], "")
        XCTAssertEqual(tagRef[3], "")
        XCTAssertEqual(tagRef[4], pubkey)
    }
    
    func testTagReferenceForReplaceable() {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let event = EventTestFactory.createEvent(
            kind: EventKind.metadata,
            pubkey: pubkey
        )
        
        // When
        let tagRef = event.tagReference()
        
        // Then
        XCTAssertEqual(tagRef.count, 5)
        XCTAssertEqual(tagRef[0], "a")
        XCTAssertEqual(tagRef[1], "0:\(pubkey):")
        XCTAssertEqual(tagRef[2], "")
        XCTAssertEqual(tagRef[3], "")
        XCTAssertEqual(tagRef[4], pubkey)
    }
    
    func testTagReferenceForRegularEvent() {
        // Given
        let pubkey = TestFixtures.Keys.alice.publicKey
        let event = EventTestFactory.createEvent(kind: 1, pubkey: pubkey)
        
        // When
        let tagRef = event.tagReference()
        
        // Then
        XCTAssertEqual(tagRef.count, 5)
        XCTAssertEqual(tagRef[0], "e")
        XCTAssertEqual(tagRef[1], event.id)
        XCTAssertEqual(tagRef[2], "")
        XCTAssertEqual(tagRef[3], "")
        XCTAssertEqual(tagRef[4], pubkey)
    }
    
    // MARK: - Serialization Tests
    
    func testRawEvent() {
        // Given
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Test",
            tags: [["t", "test"]]
        )
        
        // When
        let raw = event.rawEvent()
        
        // Then
        XCTAssertEqual(raw["id"] as? String, event.id)
        XCTAssertEqual(raw["pubkey"] as? String, event.pubkey)
        XCTAssertEqual(raw["created_at"] as? Timestamp, event.createdAt)
        XCTAssertEqual(raw["kind"] as? Kind, event.kind)
        XCTAssertEqual(raw["content"] as? String, event.content)
        XCTAssertEqual(raw["sig"] as? String, event.sig)
        
        if let tags = raw["tags"] as? [[String]] {
            XCTAssertEqual(tags, event.tags)
        } else {
            XCTFail("Tags not properly serialized")
        }
    }
    
    func testSerialize() throws {
        // Given
        let event = EventTestFactory.createEvent()
        
        // When
        let json = try event.serialize()
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NDKEvent.self, from: data)
        
        // Then
        XCTAssertEqual(decoded, event)
    }
    
    func testToJSON() throws {
        // Given
        let event = EventTestFactory.createEvent()
        
        // When
        let json1 = try event.serialize()
        let json2 = try event.toJSON()
        
        // Then
        XCTAssertEqual(json1, json2)
    }
    
    // MARK: - Mentions Tests
    
    func testMentions() {
        // Given
        let event = EventTestFactory.createEvent(
            tags: [
                ["p", "pubkey1"],
                ["p", "pubkey2"],
                ["e", "event1"]
            ]
        )
        
        // When
        let mentions = event.mentions
        
        // Then
        XCTAssertEqual(mentions.count, 2)
        XCTAssertEqual(mentions[0], "pubkey1")
        XCTAssertEqual(mentions[1], "pubkey2")
    }
    
    // MARK: - Signature Verification Tests
    
    func testVerifySignatureWithValidEvent() async throws {
        // Given
        let ndk = createTestNDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let (event, _) = try await ndk.publish {
            $0.kind(EventKind.textNote)
              .content("Valid signed event")
        }
        
        // When
        let isValid = event.verifySignature()
        
        // Then
        XCTAssertTrue(isValid)
    }
    
    func testVerifySignatureWithInvalidSignature() {
        // Given
        let event = EventTestFactory.createEvent(
            sig: "0000000000000000000000000000000000000000000000000000000000000000"
        )
        
        // When
        let isValid = event.verifySignature()
        
        // Then
        XCTAssertFalse(isValid)
    }
    
    func testVerifySignatureWithMismatchedID() {
        // Given
        let event = EventTestFactory.createEvent(
            id: "1111111111111111111111111111111111111111111111111111111111111111"
        )
        
        // When
        let isValid = event.verifySignature()
        
        // Then
        XCTAssertFalse(isValid)
    }
    
    // MARK: - Calculate ID Tests
    
    func testCalculateID() async throws {
        // Given
        let ndk = createTestNDK()
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let (event, _) = try await ndk.publish {
            $0.kind(EventKind.textNote)
              .content("Test event for ID calculation")
        }
        
        // When
        let calculatedID = try event.calculateID()
        
        // Then
        XCTAssertEqual(calculatedID, event.id)
    }
    
    // MARK: - NIP-19 Encoding Tests
    
    func testEncodeRegularEventAsNote() throws {
        // Given
        let event = EventTestFactory.createEvent(
            kind: EventKind.textNote,
            tags: []
        )
        
        // When
        let encoded = try event.encode()
        
        // Then
        XCTAssertTrue(encoded.hasPrefix("note1"))
    }
    
    func testEncodeRegularEventAsNevent() throws {
        // Given
        let event = EventTestFactory.createEvent(
            kind: EventKind.textNote,
            tags: [["e", "referenced_event"]] // Has references, should use nevent
        )
        
        // When
        let encoded = try event.encode()
        
        // Then
        XCTAssertTrue(encoded.hasPrefix("nevent1"))
    }
    
    func testEncodeParameterizedReplaceableAsNaddr() throws {
        // Given
        let event = EventTestFactory.createEvent(
            kind: 30000,
            tags: [["d", "identifier"]]
        )
        
        // When
        let encoded = try event.encode()
        
        // Then
        XCTAssertTrue(encoded.hasPrefix("naddr1"))
    }
    
    func testEncodeReplaceableAsNaddr() throws {
        // Given
        let event = EventTestFactory.createEvent(kind: EventKind.metadata)
        
        // When
        let encoded = try event.encode()
        
        // Then
        XCTAssertTrue(encoded.hasPrefix("naddr1"))
    }
    
    func testEncodeWithRelayHints() throws {
        // Given
        let event = EventTestFactory.createEvent(kind: EventKind.textNote)
        let relays = ["wss://relay1.com", "wss://relay2.com"]
        
        // When
        let encoded = try event.encode(includeRelays: true, relayHints: relays)
        
        // Then
        XCTAssertTrue(encoded.hasPrefix("nevent1"))
    }
}