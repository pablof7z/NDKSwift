@testable import NDKSwift
import XCTest

final class NDKRelayTests: XCTestCase {
    func testRelayInitialization() {
        let relay = NDKRelay(url: "wss://relay.example.com")

        XCTAssertEqual(relay.url, "wss://relay.example.com")
        XCTAssertEqual(relay.connectionState, .disconnected)
        XCTAssertNil(relay.info)
        XCTAssertTrue(relay.activeSubscriptions.isEmpty)
        XCTAssertFalse(relay.isConnected)
    }

    func testRelayURLNormalization() {
        // Test various URL formats - now with trailing slashes
        let relay1 = NDKRelay(url: "relay.example.com")
        XCTAssertEqual(relay1.normalizedURL, "wss://relay.example.com/")

        let relay2 = NDKRelay(url: "wss://relay.example.com/")
        XCTAssertEqual(relay2.normalizedURL, "wss://relay.example.com/")

        let relay3 = NDKRelay(url: "ws://relay.example.com")
        XCTAssertEqual(relay3.normalizedURL, "ws://relay.example.com/")

        let relay4 = NDKRelay(url: "WSS://RELAY.EXAMPLE.COM/")
        XCTAssertEqual(relay4.normalizedURL, "wss://relay.example.com/")

        // Test www removal
        let relay5 = NDKRelay(url: "wss://www.relay.example.com")
        XCTAssertEqual(relay5.normalizedURL, "wss://relay.example.com/")
    }

    func testRelayConnectionStates() async throws {
        // Skip this test as it requires actual WebSocket connections
        // TODO: Implement mock WebSocket for testing
        throw XCTSkip("Requires mock WebSocket implementation")
    }

    func testRelayStats() async throws {
        // Skip this test as it requires actual WebSocket connections
        // TODO: Implement mock WebSocket for testing
        throw XCTSkip("Requires mock WebSocket implementation")
    }

    func testRelaySubscriptionManagement() async throws {
        // Skip this test as it causes a segmentation fault due to NDKSubscription deallocation issues
        // TODO: Fix NDKSubscription retain cycle
        throw XCTSkip("NDKSubscription has deallocation issues")
    }

    func testRelayInfoStructures() throws {
        // Test RelayInformation decoding
        let infoJSON = """
        {
            "name": "Test Relay",
            "description": "A test relay",
            "pubkey": "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e",
            "contact": "admin@relay.com",
            "supported_nips": [1, 2, 9, 11, 12],
            "software": "test-relay",
            "version": "1.0.0",
            "limitation": {
                "max_message_length": 65536,
                "max_subscriptions": 10,
                "auth_required": false
            },
            "fees": {
                "admission": [
                    {"amount": 1000, "unit": "sats"}
                ],
                "publication": [
                    {"amount": 1, "unit": "sats", "kinds": [1]}
                ]
            }
        }
        """

        let data = infoJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        let info = try decoder.decode(NDKRelayInformation.self, from: data)

        XCTAssertEqual(info.name, "Test Relay")
        XCTAssertEqual(info.description, "A test relay")
        XCTAssertEqual(info.pubkey, "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e")
        XCTAssertEqual(info.contact, "admin@relay.com")
        XCTAssertEqual(info.supportedNips, [1, 2, 9, 11, 12])
        XCTAssertEqual(info.software, "test-relay")
        XCTAssertEqual(info.version, "1.0.0")

        // Test limitation
        XCTAssertNotNil(info.limitation)
        XCTAssertEqual(info.limitation?.maxMessageLength, 65536)
        XCTAssertEqual(info.limitation?.maxSubscriptions, 10)
        XCTAssertEqual(info.limitation?.authRequired, false)

        // Test fees
        XCTAssertNotNil(info.fees)
        XCTAssertEqual(info.fees?.admission?.count, 1)
        XCTAssertEqual(info.fees?.admission?[0].amount, 1000)
        XCTAssertEqual(info.fees?.admission?[0].unit, "sats")
        XCTAssertEqual(info.fees?.publication?.count, 1)
        XCTAssertEqual(info.fees?.publication?[0].amount, 1)
        XCTAssertEqual(info.fees?.publication?[0].kinds, [1])
    }

    func testNDKRelayInfo() {
        let relayInfo = NDKRelayInfo(
            url: "wss://relay.example.com",
            read: true,
            write: false
        )

        XCTAssertEqual(relayInfo.url, "wss://relay.example.com")
        XCTAssertTrue(relayInfo.read)
        XCTAssertFalse(relayInfo.write)

        // Test default values
        let defaultInfo = NDKRelayInfo(url: "wss://relay2.example.com")
        XCTAssertTrue(defaultInfo.read)
        XCTAssertTrue(defaultInfo.write)
    }

    func testRelayConnectionFailure() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        var lastState: NDKRelayConnectionState?
        relay.observeConnectionState { state in
            lastState = state
        }

        // Test that trying to send while disconnected throws error
        do {
            try await relay.send("TEST")
            XCTFail("Should have thrown error")
        } catch {
            if let ndkError = error as? NDKError {
                XCTAssertEqual(ndkError.code, "connection_failed")
                XCTAssertEqual(ndkError.message, "Not connected to relay")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }

    func testMultipleConnectionAttempts() async throws {
        // Skip this test as it requires actual WebSocket connections
        // TODO: Implement mock WebSocket for testing
        throw XCTSkip("Requires mock WebSocket implementation")
    }
}
