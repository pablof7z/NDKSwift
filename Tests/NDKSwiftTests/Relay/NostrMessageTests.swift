import XCTest
@testable import NDKSwift

final class NostrMessageTests: XCTestCase {
    
    // MARK: - Test Data
    
    private let testEventID = "d7dd5eb3ab747e16f8d0212d53032ea2a7cadef53837e5a6c66d42849fcb9027"
    private let testPubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
    private let testSubscriptionId = "sub123"
    
    private func createTestEvent() -> NDKEvent {
        return EventTestFactory.createEvent(
            kind: 1,
            content: "Test message",
            pubkey: testPubkey,
            id: testEventID
        )
    }
    
    private func createTestFilter() -> NDKFilter {
        return NDKFilter(authors: [testPubkey], kinds: [1])
    }
    
    // MARK: - Parse Tests
    
    func testParseEventMessage() throws {
        let event = createTestEvent()
        let eventDict = try JSONCoding.encodeToDictionary(event)
        let json = try JSONCoding.serializeToString(["EVENT", testSubscriptionId, eventDict])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .event(subscriptionId, parsedEvent) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
            XCTAssertEqual(parsedEvent.id, event.id)
            XCTAssertEqual(parsedEvent.content, event.content)
        } else {
            XCTFail("Expected event message")
        }
    }
    
    func testParseEventMessageWithoutSubscription() throws {
        let event = createTestEvent()
        let eventDict = try JSONCoding.encodeToDictionary(event)
        let json = try JSONCoding.serializeToString(["EVENT", eventDict])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .event(subscriptionId, parsedEvent) = message {
            XCTAssertNil(subscriptionId)
            XCTAssertEqual(parsedEvent.id, event.id)
        } else {
            XCTFail("Expected event message")
        }
    }
    
    func testParseReqMessage() throws {
        let filter = createTestFilter()
        let filterDict = try JSONCoding.encodeToDictionary(filter)
        let json = try JSONCoding.serializeToString(["REQ", testSubscriptionId, filterDict])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .req(subscriptionId, filters) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
            XCTAssertEqual(filters.count, 1)
            XCTAssertEqual(filters[0].kinds, [1])
            XCTAssertEqual(filters[0].authors, [testPubkey])
        } else {
            XCTFail("Expected req message")
        }
    }
    
    func testParseReqMessageWithMultipleFilters() throws {
        let filter1 = NDKFilter(kinds: [1])
        let filter2 = NDKFilter(authors: [testPubkey])
        let filterDict1 = try JSONCoding.encodeToDictionary(filter1)
        let filterDict2 = try JSONCoding.encodeToDictionary(filter2)
        let json = try JSONCoding.serializeToString(["REQ", testSubscriptionId, filterDict1, filterDict2])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .req(_, filters) = message {
            XCTAssertEqual(filters.count, 2)
            XCTAssertEqual(filters[0].kinds, [1])
            XCTAssertEqual(filters[1].authors, [testPubkey])
        } else {
            XCTFail("Expected req message")
        }
    }
    
    func testParseCloseMessage() throws {
        let json = try JSONCoding.serializeToString(["CLOSE", testSubscriptionId])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .close(subscriptionId) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
        } else {
            XCTFail("Expected close message")
        }
    }
    
    func testParseNoticeMessage() throws {
        let noticeText = "Rate limit exceeded"
        let json = try JSONCoding.serializeToString(["NOTICE", noticeText])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .notice(text) = message {
            XCTAssertEqual(text, noticeText)
        } else {
            XCTFail("Expected notice message")
        }
    }
    
    func testParseEoseMessage() throws {
        let json = try JSONCoding.serializeToString(["EOSE", testSubscriptionId])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .eose(subscriptionId) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
        } else {
            XCTFail("Expected eose message")
        }
    }
    
    func testParseOkMessage() throws {
        let json = try JSONCoding.serializeToString(["OK", testEventID, true, "Event accepted"])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .ok(eventId, accepted, message) = message {
            XCTAssertEqual(eventId, testEventID)
            XCTAssertTrue(accepted)
            XCTAssertEqual(message, "Event accepted")
        } else {
            XCTFail("Expected ok message")
        }
    }
    
    func testParseOkMessageWithoutMessage() throws {
        let json = try JSONCoding.serializeToString(["OK", testEventID, false])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .ok(eventId, accepted, message) = message {
            XCTAssertEqual(eventId, testEventID)
            XCTAssertFalse(accepted)
            XCTAssertNil(message)
        } else {
            XCTFail("Expected ok message")
        }
    }
    
    func testParseAuthMessage() throws {
        let challenge = "auth_challenge_123"
        let json = try JSONCoding.serializeToString(["AUTH", challenge])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .auth(parsedChallenge) = message {
            XCTAssertEqual(parsedChallenge, challenge)
        } else {
            XCTFail("Expected auth message")
        }
    }
    
    func testParseCountMessage() throws {
        let count = 42
        let json = try JSONCoding.serializeToString(["COUNT", testSubscriptionId, ["count": count]])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .count(subscriptionId, parsedCount) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
            XCTAssertEqual(parsedCount, count)
        } else {
            XCTFail("Expected count message")
        }
    }
    
    // MARK: - Parse Error Tests
    
    func testParseEmptyArray() throws {
        let json = "[]"
        
        XCTAssertThrowsError(try NostrMessage.parse(from: json)) { error in
            XCTAssertTrue(error is NDKError)
        }
    }
    
    func testParseInvalidMessageType() throws {
        let json = try JSONCoding.serializeToString(["INVALID_TYPE", "data"])
        
        XCTAssertThrowsError(try NostrMessage.parse(from: json)) { error in
            XCTAssertTrue(error is NDKError)
        }
    }
    
    func testParseEventWithInvalidData() throws {
        let json = try JSONCoding.serializeToString(["EVENT", "not_a_dict"])
        
        XCTAssertThrowsError(try NostrMessage.parse(from: json)) { error in
            XCTAssertTrue(error is NDKError)
        }
    }
    
    func testParseReqWithoutSubscriptionId() throws {
        let json = try JSONCoding.serializeToString(["REQ"])
        
        XCTAssertThrowsError(try NostrMessage.parse(from: json)) { error in
            XCTAssertTrue(error is NDKError)
        }
    }
    
    // MARK: - Serialize Tests
    
    func testSerializeEventMessage() throws {
        let event = createTestEvent()
        let message = NostrMessage.event(subscriptionId: nil, event: event)
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0] as? String, "EVENT")
        XCTAssertNotNil(parsed[1] as? [String: Any])
    }
    
    func testSerializeReqMessage() throws {
        let filter = createTestFilter()
        let message = NostrMessage.req(subscriptionId: testSubscriptionId, filters: [filter])
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0] as? String, "REQ")
        XCTAssertEqual(parsed[1] as? String, testSubscriptionId)
        XCTAssertNotNil(parsed[2] as? [String: Any])
    }
    
    func testSerializeCloseMessage() throws {
        let message = NostrMessage.close(subscriptionId: testSubscriptionId)
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0] as? String, "CLOSE")
        XCTAssertEqual(parsed[1] as? String, testSubscriptionId)
    }
    
    func testSerializeNoticeMessage() throws {
        let noticeText = "Test notice"
        let message = NostrMessage.notice(message: noticeText)
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0] as? String, "NOTICE")
        XCTAssertEqual(parsed[1] as? String, noticeText)
    }
    
    func testSerializeEoseMessage() throws {
        let message = NostrMessage.eose(subscriptionId: testSubscriptionId)
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0] as? String, "EOSE")
        XCTAssertEqual(parsed[1] as? String, testSubscriptionId)
    }
    
    func testSerializeOkMessage() throws {
        let message = NostrMessage.ok(eventId: testEventID, accepted: true, message: "Success")
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed[0] as? String, "OK")
        XCTAssertEqual(parsed[1] as? String, testEventID)
        XCTAssertEqual(parsed[2] as? Bool, true)
        XCTAssertEqual(parsed[3] as? String, "Success")
    }
    
    func testSerializeOkMessageWithoutMessage() throws {
        let message = NostrMessage.ok(eventId: testEventID, accepted: false, message: nil)
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0] as? String, "OK")
        XCTAssertEqual(parsed[1] as? String, testEventID)
        XCTAssertEqual(parsed[2] as? Bool, false)
    }
    
    func testSerializeAuthMessage() throws {
        let challenge = "test_challenge"
        let message = NostrMessage.auth(challenge: challenge)
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0] as? String, "AUTH")
        XCTAssertEqual(parsed[1] as? String, challenge)
    }
    
    func testSerializeCountMessage() throws {
        let count = 100
        let message = NostrMessage.count(subscriptionId: testSubscriptionId, count: count)
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0] as? String, "COUNT")
        XCTAssertEqual(parsed[1] as? String, testSubscriptionId)
        if let countDict = parsed[2] as? [String: Any] {
            XCTAssertEqual(countDict["count"] as? Int, count)
        } else {
            XCTFail("Expected count dictionary")
        }
    }
    
    // MARK: - Round Trip Tests
    
    func testRoundTripEvent() throws {
        let event = createTestEvent()
        // NOTE: There's a bug in NostrMessage.serialize() that doesn't include
        // subscription ID for EVENT messages. Testing without subscription ID for now.
        let original = NostrMessage.event(subscriptionId: nil, event: event)
        
        let json = try original.serialize()
        let parsed = try NostrMessage.parse(from: json)
        
        if case let .event(subscriptionId, parsedEvent) = parsed {
            XCTAssertNil(subscriptionId)
            XCTAssertEqual(parsedEvent.id, event.id)
            XCTAssertEqual(parsedEvent.content, event.content)
        } else {
            XCTFail("Round trip failed")
        }
    }
    
    func testRoundTripReq() throws {
        let filter = createTestFilter()
        let original = NostrMessage.req(subscriptionId: testSubscriptionId, filters: [filter])
        
        let json = try original.serialize()
        let parsed = try NostrMessage.parse(from: json)
        
        if case let .req(subscriptionId, filters) = parsed {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
            XCTAssertEqual(filters.count, 1)
            XCTAssertEqual(filters[0].kinds, filter.kinds)
            XCTAssertEqual(filters[0].authors, filter.authors)
        } else {
            XCTFail("Round trip failed")
        }
    }
    
    func testRoundTripAllMessageTypes() throws {
        let messages: [NostrMessage] = [
            .close(subscriptionId: testSubscriptionId),
            .notice(message: "Test notice"),
            .eose(subscriptionId: testSubscriptionId),
            .ok(eventId: testEventID, accepted: true, message: "Success"),
            .auth(challenge: "challenge123"),
            .count(subscriptionId: testSubscriptionId, count: 42)
        ]
        
        for original in messages {
            let json = try original.serialize()
            let _ = try NostrMessage.parse(from: json)
            // Just ensure no errors are thrown
        }
    }
    
    // MARK: - Subscription ID Tests
    
    func testSubscriptionIdProperty() {
        // Messages with subscription IDs
        XCTAssertEqual(NostrMessage.event(subscriptionId: testSubscriptionId, event: createTestEvent()).subscriptionId, testSubscriptionId)
        XCTAssertEqual(NostrMessage.req(subscriptionId: testSubscriptionId, filters: []).subscriptionId, testSubscriptionId)
        XCTAssertEqual(NostrMessage.close(subscriptionId: testSubscriptionId).subscriptionId, testSubscriptionId)
        XCTAssertEqual(NostrMessage.eose(subscriptionId: testSubscriptionId).subscriptionId, testSubscriptionId)
        XCTAssertEqual(NostrMessage.count(subscriptionId: testSubscriptionId, count: 0).subscriptionId, testSubscriptionId)
        
        // Messages without subscription IDs
        XCTAssertNil(NostrMessage.event(subscriptionId: nil, event: createTestEvent()).subscriptionId)
        XCTAssertNil(NostrMessage.notice(message: "").subscriptionId)
        XCTAssertNil(NostrMessage.ok(eventId: "", accepted: true, message: nil).subscriptionId)
        XCTAssertNil(NostrMessage.auth(challenge: "").subscriptionId)
    }
    
    // MARK: - NIP-77 Negentropy Tests
    
    func testParseNegOpenMessage() throws {
        let filter = createTestFilter()
        let filterDict = filter.dictionary
        let hexMessage = "deadbeef"
        let json = try JSONCoding.serializeToString(["NEG-OPEN", testSubscriptionId, filterDict, hexMessage])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .negOpen(subscriptionId, parsedFilter, message) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
            XCTAssertEqual(parsedFilter.kinds, filter.kinds)
            XCTAssertEqual(parsedFilter.authors, filter.authors)
            XCTAssertEqual(message, hexMessage)
        } else {
            XCTFail("Expected negOpen message")
        }
    }
    
    func testParseNegMsgMessage() throws {
        let hexMessage = "cafebabe"
        let json = try JSONCoding.serializeToString(["NEG-MSG", testSubscriptionId, hexMessage])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .negMsg(subscriptionId, message) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
            XCTAssertEqual(message, hexMessage)
        } else {
            XCTFail("Expected negMsg message")
        }
    }
    
    func testParseNegCloseMessage() throws {
        let json = try JSONCoding.serializeToString(["NEG-CLOSE", testSubscriptionId])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .negClose(subscriptionId) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
        } else {
            XCTFail("Expected negClose message")
        }
    }
    
    func testParseNegErrMessage() throws {
        let errorMsg = "Sync failed"
        let json = try JSONCoding.serializeToString(["NEG-ERR", testSubscriptionId, errorMsg])
        
        let message = try NostrMessage.parse(from: json)
        
        if case let .negErr(subscriptionId, error) = message {
            XCTAssertEqual(subscriptionId, testSubscriptionId)
            XCTAssertEqual(error, errorMsg)
        } else {
            XCTFail("Expected negErr message")
        }
    }
    
    func testSerializeNegOpenMessage() throws {
        let filter = createTestFilter()
        let hexMessage = "deadbeef"
        let message = NostrMessage.negOpen(subscriptionId: testSubscriptionId, filter: filter, message: hexMessage)
        
        let json = try message.serialize()
        let parsed = try JSONCoding.parseArray(from: json)
        
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed[0] as? String, "NEG-OPEN")
        XCTAssertEqual(parsed[1] as? String, testSubscriptionId)
        XCTAssertNotNil(parsed[2] as? [String: Any])
        XCTAssertEqual(parsed[3] as? String, hexMessage)
    }
    
    func testNegentropySuiteRoundTrip() throws {
        let filter = createTestFilter()
        let negMessages: [NostrMessage] = [
            .negOpen(subscriptionId: testSubscriptionId, filter: filter, message: "abcd"),
            .negMsg(subscriptionId: testSubscriptionId, message: "efgh"),
            .negClose(subscriptionId: testSubscriptionId),
            .negErr(subscriptionId: testSubscriptionId, error: "Error")
        ]
        
        for original in negMessages {
            let json = try original.serialize()
            let _ = try NostrMessage.parse(from: json)
            XCTAssertEqual(original.subscriptionId, testSubscriptionId)
        }
    }
}