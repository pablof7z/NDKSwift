@testable import NDKSwiftCore
import XCTest

final class RelayConstantsTests: XCTestCase {
    // MARK: - WebSocketScheme Tests

    func testWebSocketScheme_Constants() {
        XCTAssertEqual(RelayConstants.WebSocketScheme.secure, "wss://")
        XCTAssertEqual(RelayConstants.WebSocketScheme.insecure, "ws://")
    }

    func testIsWebSocketURL_ValidURLs() {
        let validURLs = [
            "wss://relay.example.com",
            "ws://relay.example.com",
            "WSS://RELAY.EXAMPLE.COM",
            "WS://RELAY.EXAMPLE.COM",
            "wss://relay.example.com/path",
            "ws://relay.example.com:8080",
        ]

        for url in validURLs {
            XCTAssertTrue(RelayConstants.WebSocketScheme.isWebSocketURL(url), "Expected '\(url)' to be recognized as WebSocket URL")
        }
    }

    func testIsWebSocketURL_InvalidURLs() {
        let invalidURLs = [
            "https://relay.example.com",
            "http://relay.example.com",
            "relay.example.com",
            "ftp://relay.example.com",
            "",
            " ",
            "not a url",
        ]

        for url in invalidURLs {
            XCTAssertFalse(RelayConstants.WebSocketScheme.isWebSocketURL(url), "Expected '\(url)' to not be recognized as WebSocket URL")
        }
    }

    func testEnsureWebSocketScheme_AddsSchemeWhenMissing() {
        let urlsWithoutScheme = [
            ("relay.example.com", "wss://relay.example.com"),
            ("relay.example.com:8080", "wss://relay.example.com:8080"),
            ("relay.example.com/path", "wss://relay.example.com/path"),
            ("  relay.example.com  ", "wss://relay.example.com"), // Tests trimming
        ]

        for (input, expected) in urlsWithoutScheme {
            let result = RelayConstants.WebSocketScheme.ensureWebSocketScheme(input)
            XCTAssertEqual(result, expected, "Expected '\(input)' to become '\(expected)'")
        }
    }

    func testEnsureWebSocketScheme_PreservesExistingScheme() {
        let urlsWithScheme = [
            "wss://relay.example.com",
            "ws://relay.example.com",
            "WSS://RELAY.EXAMPLE.COM",
            "WS://RELAY.EXAMPLE.COM",
            "  wss://relay.example.com  ", // Tests trimming with existing scheme
        ]

        for input in urlsWithScheme {
            let result = RelayConstants.WebSocketScheme.ensureWebSocketScheme(input)
            XCTAssertEqual(result, input.trimmed, "Expected '\(input)' to remain as '\(input.trimmed)'")
        }
    }

    // MARK: - Popular Relays Tests

    func testPopularRelays_HaveValidWebSocketURLs() {
        let popularRelays = [
            RelayConstants.damus,
            RelayConstants.nostrBand,
            RelayConstants.nosLol,
            RelayConstants.primal,
            RelayConstants.snortSocial,
            RelayConstants.nostrWine,
            RelayConstants.currentFyi,
            RelayConstants.oxtrDev,
        ]

        for relay in popularRelays {
            XCTAssertTrue(RelayConstants.WebSocketScheme.isWebSocketURL(relay), "Popular relay '\(relay)' should have WebSocket scheme")
            XCTAssertNotNil(URLUtils.safeURL(relay), "Popular relay '\(relay)' should be a valid URL")
        }
    }

    func testDefaultRelaySets_ContainValidRelays() {
        let relaySets = [
            ("defaultRelays", RelayConstants.defaultRelays),
            ("extendedRelays", RelayConstants.extendedRelays),
            ("testRelays", RelayConstants.testRelays),
            ("walletRelays", RelayConstants.walletRelays),
        ]

        for (name, relays) in relaySets {
            XCTAssertFalse(relays.isEmpty, "\(name) should not be empty")

            for relay in relays {
                XCTAssertTrue(RelayConstants.WebSocketScheme.isWebSocketURL(relay), "Relay '\(relay)' in \(name) should have WebSocket scheme")
                XCTAssertNotNil(URLUtils.safeURL(relay), "Relay '\(relay)' in \(name) should be a valid URL")
            }
        }
    }

    func testDefaultOutboxRelays_ContainValidRelays() {
        XCTAssertFalse(RelayConstants.defaultOutboxRelays.isEmpty, "defaultOutboxRelays should not be empty")

        for relay in RelayConstants.defaultOutboxRelays {
            XCTAssertTrue(RelayConstants.WebSocketScheme.isWebSocketURL(relay), "Outbox relay '\(relay)' should have WebSocket scheme")
            XCTAssertNotNil(URLUtils.safeURL(relay), "Outbox relay '\(relay)' should be a valid URL")
        }
    }

    func testExampleRelay_IsValid() {
        XCTAssertEqual(RelayConstants.example, "wss://relay.example.com")
        XCTAssertTrue(RelayConstants.WebSocketScheme.isWebSocketURL(RelayConstants.example))
    }
}
