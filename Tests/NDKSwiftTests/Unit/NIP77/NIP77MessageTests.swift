@testable import NDKSwiftCore
import XCTest

final class NIP77MessageTests: XCTestCase {
    func testNIP77MessageConstruction() throws {
        // Test NEG-OPEN message
        let openMessage = NIP77Message.negOpen(
            subscriptionId: "test-sub-123",
            filter: NDKFilter(kinds: [1]),
            initialMessage: "0102030405"
        )

        XCTAssertEqual(openMessage.subscriptionId, "test-sub-123")
        XCTAssertEqual(openMessage.messageType, .negOpen)
        XCTAssertNotNil(openMessage.filter)
        XCTAssertEqual(openMessage.filter?.kinds, [1])
        XCTAssertEqual(openMessage.initialMessage, "0102030405")

        // Test NEG-MSG message
        let msgMessage = NIP77Message.negMsg(
            subscriptionId: "test-sub-123",
            message: "deadbeef"
        )

        XCTAssertEqual(msgMessage.subscriptionId, "test-sub-123")
        XCTAssertEqual(msgMessage.messageType, .negMsg)
        XCTAssertNil(msgMessage.filter)
        XCTAssertEqual(msgMessage.message, "deadbeef")
    }

    func testNIP77MessageJSONEncoding() throws {
        let message = NIP77Message.negOpen(
            subscriptionId: "sub123",
            filter: NDKFilter(authors: ["pubkey1"], kinds: [1, 3]),
            initialMessage: "abc123"
        )

        let json = try message.toJSON()

        // Parse the JSON array
        guard let array = json as? [Any],
              array.count >= 4,
              let type = array[0] as? String,
              let subId = array[1] as? String,
              let filterJSON = array[2] as? [String: Any],
              let initialMsg = array[3] as? String
        else {
            XCTFail("Invalid JSON structure")
            return
        }

        XCTAssertEqual(type, "NEG-OPEN")
        XCTAssertEqual(subId, "sub123")
        XCTAssertEqual(initialMsg, "abc123")

        // Verify filter
        XCTAssertEqual(filterJSON["kinds"] as? [Int], [1, 3])
        XCTAssertEqual(filterJSON["authors"] as? [String], ["pubkey1"])
    }

    func testNIP77MessageParsing() throws {
        // Test parsing NEG-OPEN
        let openJSON: [Any] = ["NEG-OPEN", "sub456", ["kinds": [1]], "def456"]
        let openMessage = try NIP77Message.parse(from: openJSON)

        XCTAssertEqual(openMessage.messageType, .negOpen)
        XCTAssertEqual(openMessage.subscriptionId, "sub456")
        XCTAssertNotNil(openMessage.filter)
        XCTAssertEqual(openMessage.initialMessage, "def456")

        // Test parsing NEG-MSG
        let msgJSON: [Any] = ["NEG-MSG", "sub456", "f00d1234"]
        let msgMessage = try NIP77Message.parse(from: msgJSON)

        XCTAssertEqual(msgMessage.messageType, .negMsg)
        XCTAssertEqual(msgMessage.subscriptionId, "sub456")
        XCTAssertEqual(msgMessage.message, "f00d1234")

        // Test parsing NEG-CLOSE
        let closeJSON: [Any] = ["NEG-CLOSE", "sub456"]
        let closeMessage = try NIP77Message.parse(from: closeJSON)

        XCTAssertEqual(closeMessage.messageType, .negClose)
        XCTAssertEqual(closeMessage.subscriptionId, "sub456")

        // Test parsing NEG-ERR
        let errJSON: [Any] = ["NEG-ERR", "sub456", "error: something went wrong"]
        let errMessage = try NIP77Message.parse(from: errJSON)

        XCTAssertEqual(errMessage.messageType, .negErr)
        XCTAssertEqual(errMessage.subscriptionId, "sub456")
        XCTAssertEqual(errMessage.reason, "error: something went wrong")
    }

    func testNIP77MessageParsingErrors() {
        // Test invalid message type
        XCTAssertThrowsError(try NIP77Message.parse(from: ["INVALID", "sub"])) { error in
            guard case NIP77Error.invalidMessageType = error else {
                XCTFail("Expected invalidMessageType error")
                return
            }
        }

        // Test missing subscription ID
        XCTAssertThrowsError(try NIP77Message.parse(from: ["NEG-OPEN"])) { error in
            guard case NIP77Error.invalidMessageFormat = error else {
                XCTFail("Expected invalidMessageFormat error")
                return
            }
        }

        // Test invalid array structure
        XCTAssertThrowsError(try NIP77Message.parse(from: "not an array")) { error in
            guard case NIP77Error.invalidMessageFormat = error else {
                XCTFail("Expected invalidMessageFormat error")
                return
            }
        }

        XCTAssertThrowsError(try NIP77Message.parse(from: ["NEG-MSG", "sub", "not-hex"]))
        XCTAssertThrowsError(try NIP77Message.parse(from: ["NEG-MSG", "sub", "abc"]))
        XCTAssertThrowsError(try NIP77Message.parse(from: ["NEG-MSG", "sub", "0x61"]))
        XCTAssertThrowsError(try NIP77Message.parse(from: ["NEG-CLOSE", "sub", "extra"]))
        XCTAssertThrowsError(try NIP77Message.parse(from: ["NEG-OPEN", "sub", ["kinds": [1]], "61", "extra"]))
    }

    func testNIP77MessageAllowsNegErrRecordLimit() throws {
        let message = try NIP77Message.parse(from: ["NEG-ERR", "sub", "blocked: too many records", 10_000])

        XCTAssertEqual(message.messageType, .negErr)
        XCTAssertEqual(message.subscriptionId, "sub")
        XCTAssertEqual(message.reason, "blocked: too many records")
    }

    func testNIP77MessageEncodingRejectsInvalidHexPayload() {
        let message = NIP77Message.negMsg(subscriptionId: "sub", message: "not-hex")

        XCTAssertThrowsError(try message.toJSON())
    }

    func testNIP77ErrorLocalizedDescription() {
        let errors: [(NIP77Error, String)] = [
            (.invalidMessageType("UNKNOWN"), "Invalid NIP-77 message type: UNKNOWN"),
            (.invalidMessageFormat("test"), "Invalid NIP-77 message format: test"),
            (.missingRequiredField("filter"), "Missing required field: filter"),
            (.syncFailed("timeout"), "Negentropy sync failed: timeout"),
        ]

        for (error, expectedDescription) in errors {
            XCTAssertEqual(error.localizedDescription, expectedDescription)
        }
    }
}
