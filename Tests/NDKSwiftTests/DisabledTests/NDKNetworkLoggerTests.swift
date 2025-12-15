@testable import NDKSwiftCore
import XCTest

final class NDKNetworkLoggerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        NDKLogger.setLogLevel(.trace)
        NDKLogger.setLogNetworkTraffic(true)
    }

    override func tearDown() async throws {
        NDKLogger.setLogHandler(nil)
        NDKLogger.setLogLevel(.off)
        NDKLogger.setLogNetworkTraffic(false)
        try await super.tearDown()
    }

    func testLogNetworkSend() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        let testURL = URL(string: "wss://relay.example.com")!
        let message = "[\"REQ\",\"sub123\",{\"kinds\":[1]}]"

        NDKNetworkLogger.logNetworkSend(to: testURL, message: message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(capturedOutput)
        XCTAssertTrue(capturedOutput!.contains("📤 SENDING TO relay.example.com"))
        XCTAssertTrue(capturedOutput!.contains(message))
    }

    func testLogNetworkReceive() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        let testURL = URL(string: "wss://relay.example.com")!
        let message = "[\"EVENT\",\"sub123\",{\"id\":\"event123\",\"kind\":1}]"

        NDKNetworkLogger.logNetworkReceive(from: testURL, message: message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(capturedOutput)
        XCTAssertTrue(capturedOutput!.contains("📥 RECEIVED FROM relay.example.com"))
        XCTAssertTrue(capturedOutput!.contains(message))
    }

    func testLogNetworkParseError() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        let testURL = URL(string: "wss://relay.example.com")!
        let message = "[invalid json"
        let error = NSError(domain: "JSONError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])

        NDKNetworkLogger.logNetworkParseError(from: testURL, message: message, error: error)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(capturedOutput)
        XCTAssertTrue(capturedOutput!.contains("📥 RECEIVED FROM relay.example.com"))
        XCTAssertTrue(capturedOutput!.contains("❌ PARSE ERROR:"))
        XCTAssertTrue(capturedOutput!.contains("Invalid JSON"))
    }

    func testLogNetworkTrafficDisabled() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        NDKLogger.setLogNetworkTraffic(false)

        let testURL = URL(string: "wss://relay.example.com")!
        let message = "[\"REQ\",\"sub123\",{\"kinds\":[1]}]"

        NDKNetworkLogger.logNetworkSend(to: testURL, message: message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(capturedOutput)
    }

    func testLoggerDisabled() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        NDKLogger.setLogLevel(.off)

        let testURL = URL(string: "wss://relay.example.com")!
        let message = "[\"REQ\",\"sub123\",{\"kinds\":[1]}]"

        NDKNetworkLogger.logNetworkSend(to: testURL, message: message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(capturedOutput)
    }

    func testLogParsedMessage_Event() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        let event = EventTestFactory.createEvent(kind: 1, content: "Hello, world!")
        let message = NostrMessage.event(subscriptionId: "sub123", event: event)

        NDKNetworkLogger.logParsedMessage(message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(capturedOutput)
        XCTAssertTrue(capturedOutput!.contains("TYPE: EVENT"))
        XCTAssertTrue(capturedOutput!.contains("SUBSCRIPTION: sub123"))
        XCTAssertTrue(capturedOutput!.contains("KIND: 1"))
        XCTAssertTrue(capturedOutput!.contains("CONTENT: Hello, world!"))
    }

    func testLogParsedMessage_REQ() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        let filter = NDKFilter(kinds: [1, 3], since: Timestamp(1000), until: Timestamp(2000), limit: 10)
        let message = NostrMessage.req(subscriptionId: "sub123", filters: [filter])

        NDKNetworkLogger.logParsedMessage(message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(capturedOutput)
        XCTAssertTrue(capturedOutput!.contains("TYPE: REQ"))
        XCTAssertTrue(capturedOutput!.contains("SUBSCRIPTION: sub123"))
        XCTAssertTrue(capturedOutput!.contains("KINDS: [1, 3]"))
        XCTAssertTrue(capturedOutput!.contains("LIMIT: 10"))
        XCTAssertTrue(capturedOutput!.contains("SINCE:"))
        XCTAssertTrue(capturedOutput!.contains("UNTIL:"))
    }

    func testLogParsedMessage_OK() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        let message = NostrMessage.ok(eventId: "event123", accepted: true, message: "Event published successfully")

        NDKNetworkLogger.logParsedMessage(message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(capturedOutput)
        XCTAssertTrue(capturedOutput!.contains("TYPE: OK"))
        XCTAssertTrue(capturedOutput!.contains("EVENT ID: event123"))
        XCTAssertTrue(capturedOutput!.contains("ACCEPTED: true"))
        XCTAssertTrue(capturedOutput!.contains("MESSAGE: Event published successfully"))
    }

    func testLogParsedMessage_EOSE() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        let message = NostrMessage.eose(subscriptionId: "sub123")

        NDKNetworkLogger.logParsedMessage(message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(capturedOutput)
        XCTAssertTrue(capturedOutput!.contains("TYPE: EOSE (End of Stored Events)"))
        XCTAssertTrue(capturedOutput!.contains("SUBSCRIPTION: sub123"))
    }

    func testLogParsedMessage_ContentTruncation() async throws {
        var capturedOutput: String?
        NDKLogger.setLogHandler { output in
            capturedOutput = output
        }

        let longContent = String(repeating: "A", count: 150)
        let event = EventTestFactory.createEvent(kind: 1, content: longContent)
        let message = NostrMessage.event(subscriptionId: nil, event: event)

        NDKNetworkLogger.logParsedMessage(message)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(capturedOutput)
        XCTAssertTrue(capturedOutput!.contains("CONTENT:"))
        XCTAssertTrue(capturedOutput!.contains("..."))
        XCTAssertFalse(capturedOutput!.contains(longContent))
    }
}
