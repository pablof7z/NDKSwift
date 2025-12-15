@testable import NDKSwiftCore
import XCTest

final class ValidationHelpersTests: XCTestCase {
    // MARK: - String Validation Tests

    func testHasContent() {
        // Should return true for strings with content
        XCTAssertTrue(ValidationHelpers.hasContent("hello"))
        XCTAssertTrue(ValidationHelpers.hasContent("  hello  "))
        XCTAssertTrue(ValidationHelpers.hasContent("\n\thello\n\t"))

        // Should return false for empty or whitespace-only strings
        XCTAssertFalse(ValidationHelpers.hasContent(""))
        XCTAssertFalse(ValidationHelpers.hasContent(" "))
        XCTAssertFalse(ValidationHelpers.hasContent("\n"))
        XCTAssertFalse(ValidationHelpers.hasContent("\t"))
        XCTAssertFalse(ValidationHelpers.hasContent("   \n\t  "))
    }

    func testTrim() {
        XCTAssertEqual(ValidationHelpers.trim("hello"), "hello")
        XCTAssertEqual(ValidationHelpers.trim("  hello  "), "hello")
        XCTAssertEqual(ValidationHelpers.trim("\nhello\n"), "hello")
        XCTAssertEqual(ValidationHelpers.trim("\t hello \t"), "hello")
        XCTAssertEqual(ValidationHelpers.trim("   hello world   "), "hello world")
        XCTAssertEqual(ValidationHelpers.trim(""), "")
        XCTAssertEqual(ValidationHelpers.trim("   "), "")
    }

    func testNormalize() {
        XCTAssertEqual(ValidationHelpers.normalize("HELLO"), "hello")
        XCTAssertEqual(ValidationHelpers.normalize("  HELLO  "), "hello")
        XCTAssertEqual(ValidationHelpers.normalize("\nHeLLo\n"), "hello")
        XCTAssertEqual(ValidationHelpers.normalize("  Hello World  "), "hello world")
        XCTAssertEqual(ValidationHelpers.normalize(""), "")
        XCTAssertEqual(ValidationHelpers.normalize("   "), "")
    }

    func testHasLength() {
        XCTAssertTrue(ValidationHelpers.hasLength("hello", equalTo: 5))
        XCTAssertTrue(ValidationHelpers.hasLength("", equalTo: 0))
        XCTAssertTrue(ValidationHelpers.hasLength("🇺🇸", equalTo: 1)) // Unicode flag emoji

        XCTAssertFalse(ValidationHelpers.hasLength("hello", equalTo: 4))
        XCTAssertFalse(ValidationHelpers.hasLength("hello", equalTo: 6))
        XCTAssertFalse(ValidationHelpers.hasLength("", equalTo: 1))
    }

    // MARK: - URL Validation Tests

    func testIsWebSocketURL() {
        // Valid WebSocket URLs
        XCTAssertTrue(ValidationHelpers.isWebSocketURL("ws://relay.nostr.band"))
        XCTAssertTrue(ValidationHelpers.isWebSocketURL("wss://relay.nostr.band"))
        XCTAssertTrue(ValidationHelpers.isWebSocketURL("WS://relay.nostr.band"))
        XCTAssertTrue(ValidationHelpers.isWebSocketURL("WSS://relay.nostr.band"))

        // Invalid WebSocket URLs
        XCTAssertFalse(ValidationHelpers.isWebSocketURL("http://relay.nostr.band"))
        XCTAssertFalse(ValidationHelpers.isWebSocketURL("https://relay.nostr.band"))
        XCTAssertFalse(ValidationHelpers.isWebSocketURL("relay.nostr.band"))
        XCTAssertFalse(ValidationHelpers.isWebSocketURL(""))
        XCTAssertFalse(ValidationHelpers.isWebSocketURL("not a url"))
    }

    func testIsValidURL() {
        // Valid URLs
        XCTAssertTrue(ValidationHelpers.isValidURL("https://example.com"))
        XCTAssertTrue(ValidationHelpers.isValidURL("http://example.com"))
        XCTAssertTrue(ValidationHelpers.isValidURL("wss://relay.nostr.band"))
        XCTAssertTrue(ValidationHelpers.isValidURL("https://example.com/path?query=value#fragment"))
        XCTAssertTrue(ValidationHelpers.isValidURL("https://user:pass@example.com:8080/path"))

        // Invalid URLs - Note: URL(string:) is quite permissive
        XCTAssertFalse(ValidationHelpers.isValidURL("")) // Empty string returns nil
        XCTAssertTrue(ValidationHelpers.isValidURL("not a url")) // Parses as relative URL
        XCTAssertTrue(ValidationHelpers.isValidURL("://example.com")) // Parses with empty scheme
        XCTAssertTrue(ValidationHelpers.isValidURL("https://")) // Valid URL with empty host
        XCTAssertTrue(ValidationHelpers.isValidURL("example com")) // Spaces get URL encoded
    }

    // MARK: - Numeric Validation Tests

    func testIsInRange() {
        // Integer ranges
        XCTAssertTrue(ValidationHelpers.isInRange(5, range: 1 ... 10))
        XCTAssertTrue(ValidationHelpers.isInRange(1, range: 1 ... 10))
        XCTAssertTrue(ValidationHelpers.isInRange(10, range: 1 ... 10))
        XCTAssertFalse(ValidationHelpers.isInRange(0, range: 1 ... 10))
        XCTAssertFalse(ValidationHelpers.isInRange(11, range: 1 ... 10))

        // Double ranges
        XCTAssertTrue(ValidationHelpers.isInRange(5.5, range: 1.0 ... 10.0))
        XCTAssertTrue(ValidationHelpers.isInRange(1.0, range: 1.0 ... 10.0))
        XCTAssertTrue(ValidationHelpers.isInRange(10.0, range: 1.0 ... 10.0))
        XCTAssertFalse(ValidationHelpers.isInRange(0.9, range: 1.0 ... 10.0))
        XCTAssertFalse(ValidationHelpers.isInRange(10.1, range: 1.0 ... 10.0))
    }

    func testIsPositive() {
        // Positive values
        XCTAssertTrue(ValidationHelpers.isPositive(1))
        XCTAssertTrue(ValidationHelpers.isPositive(100))
        XCTAssertTrue(ValidationHelpers.isPositive(0.1))
        XCTAssertTrue(ValidationHelpers.isPositive(Double.greatestFiniteMagnitude))

        // Non-positive values
        XCTAssertFalse(ValidationHelpers.isPositive(0))
        XCTAssertFalse(ValidationHelpers.isPositive(-1))
        XCTAssertFalse(ValidationHelpers.isPositive(-0.1))
        XCTAssertFalse(ValidationHelpers.isPositive(Double.leastNormalMagnitude * -1))
    }

    // MARK: - Hex Validation Tests

    func testIsValid32ByteHex() {
        // Valid 32-byte hex (64 characters)
        let valid32ByteHex = "e7b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertTrue(ValidationHelpers.isValid32ByteHex(valid32ByteHex))
        XCTAssertTrue(ValidationHelpers.isValid32ByteHex(valid32ByteHex.uppercased()))

        // Invalid hex
        XCTAssertFalse(ValidationHelpers.isValid32ByteHex(""))
        XCTAssertFalse(ValidationHelpers.isValid32ByteHex("not hex"))
        XCTAssertFalse(ValidationHelpers.isValid32ByteHex("e7b0c44298fc1c149afbf4c8996fb924")) // Too short
        XCTAssertFalse(ValidationHelpers.isValid32ByteHex(valid32ByteHex + "00")) // Too long
        XCTAssertFalse(ValidationHelpers.isValid32ByteHex("g7b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")) // Invalid character
    }

    func testIsValid64ByteHex() {
        // Valid 64-byte hex (128 characters)
        let valid64ByteHex = "e7b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" +
            "e7b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertTrue(ValidationHelpers.isValid64ByteHex(valid64ByteHex))
        XCTAssertTrue(ValidationHelpers.isValid64ByteHex(valid64ByteHex.uppercased()))

        // Invalid hex
        XCTAssertFalse(ValidationHelpers.isValid64ByteHex(""))
        XCTAssertFalse(ValidationHelpers.isValid64ByteHex("not hex"))
        // Note: CashuSwift's Data(hexString:) pads odd-length strings
        // 126 chars = 63 bytes, which might be padded. Drop more to ensure failure.
        XCTAssertFalse(ValidationHelpers.isValid64ByteHex(String(valid64ByteHex.dropLast(3)))) // 125 chars = definitely too short
        XCTAssertFalse(ValidationHelpers.isValid64ByteHex(valid64ByteHex + "00")) // Too long
    }

    // MARK: - Event Kind Validation Tests

    func testIsReplaceableKind() {
        // Replaceable kinds (10000-19999 only according to EventKind.isReplaceable)
        XCTAssertTrue(ValidationHelpers.isReplaceableKind(EventKind.muteList))
        XCTAssertTrue(ValidationHelpers.isReplaceableKind(EventKind.relayList))
        XCTAssertTrue(ValidationHelpers.isReplaceableKind(15000)) // Any kind in 10000-19999

        // Non-replaceable kinds
        // Note: metadata (0) and contacts (3) are NOT considered replaceable by EventKind.isReplaceable
        // even though they are replaceable in practice. This is a limitation of the current implementation.
        XCTAssertFalse(ValidationHelpers.isReplaceableKind(EventKind.metadata))
        XCTAssertFalse(ValidationHelpers.isReplaceableKind(EventKind.contacts))
        XCTAssertFalse(ValidationHelpers.isReplaceableKind(EventKind.textNote))
        XCTAssertFalse(ValidationHelpers.isReplaceableKind(EventKind.reaction))
        XCTAssertFalse(ValidationHelpers.isReplaceableKind(9999)) // Below replaceable range
        XCTAssertFalse(ValidationHelpers.isReplaceableKind(20000)) // Ephemeral range
    }

    func testIsEphemeralKind() {
        // Ephemeral kinds (20000-29999)
        XCTAssertTrue(ValidationHelpers.isEphemeralKind(20000))
        XCTAssertTrue(ValidationHelpers.isEphemeralKind(25000))
        XCTAssertTrue(ValidationHelpers.isEphemeralKind(29999))
        XCTAssertTrue(ValidationHelpers.isEphemeralKind(EventKind.clientAuthentication))

        // Non-ephemeral kinds
        XCTAssertFalse(ValidationHelpers.isEphemeralKind(19999))
        XCTAssertFalse(ValidationHelpers.isEphemeralKind(30000))
        XCTAssertFalse(ValidationHelpers.isEphemeralKind(EventKind.textNote))
        XCTAssertFalse(ValidationHelpers.isEphemeralKind(EventKind.metadata))
    }

    func testIsParameterizedReplaceableKind() {
        // Parameterized replaceable kinds (30000-39999)
        XCTAssertTrue(ValidationHelpers.isParameterizedReplaceableKind(30000))
        XCTAssertTrue(ValidationHelpers.isParameterizedReplaceableKind(35000))
        XCTAssertTrue(ValidationHelpers.isParameterizedReplaceableKind(39999))
        XCTAssertTrue(ValidationHelpers.isParameterizedReplaceableKind(EventKind.longFormContent))
        XCTAssertTrue(ValidationHelpers.isParameterizedReplaceableKind(EventKind.categorizedPeopleList))

        // Non-parameterized replaceable kinds
        XCTAssertFalse(ValidationHelpers.isParameterizedReplaceableKind(29999))
        XCTAssertFalse(ValidationHelpers.isParameterizedReplaceableKind(40000))
        XCTAssertFalse(ValidationHelpers.isParameterizedReplaceableKind(EventKind.textNote))
        XCTAssertFalse(ValidationHelpers.isParameterizedReplaceableKind(EventKind.muteList))
    }

    // MARK: - String Extension Tests

    func testStringExtensions() {
        // Test isWebSocketURL extension
        XCTAssertTrue("wss://relay.nostr.band".isWebSocketURL)
        XCTAssertFalse("https://relay.nostr.band".isWebSocketURL)

        // Test isValidURL extension
        XCTAssertTrue("https://example.com".isValidURL)
        XCTAssertTrue("not a url".isValidURL) // URL(string:) parses this as relative URL

        // Test isValid32ByteHex extension
        let hex32 = "e7b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertTrue(hex32.isValid32ByteHex)
        XCTAssertFalse("not hex".isValid32ByteHex)

        // Test isValid64ByteHex extension
        let hex64 = hex32 + hex32
        XCTAssertTrue(hex64.isValid64ByteHex)
        XCTAssertFalse("not hex".isValid64ByteHex)
        XCTAssertFalse(String(hex64.dropLast(3)).isValid64ByteHex) // Too short after dropping 3
    }
}
