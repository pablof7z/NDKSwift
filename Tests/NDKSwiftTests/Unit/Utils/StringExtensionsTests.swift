import XCTest
@testable import NDKSwift

final class StringExtensionsTests: XCTestCase {
    
    // MARK: - nilIfEmpty Tests
    
    func testNilIfEmpty_EmptyString_ReturnsNil() {
        let emptyString = ""
        XCTAssertNil(emptyString.nilIfEmpty)
    }
    
    func testNilIfEmpty_NonEmptyString_ReturnsString() {
        let nonEmptyString = "Hello"
        XCTAssertEqual(nonEmptyString.nilIfEmpty, "Hello")
    }
    
    func testNilIfEmpty_WhitespaceString_ReturnsString() {
        let whitespaceString = "   "
        XCTAssertEqual(whitespaceString.nilIfEmpty, "   ")
    }
    
    // MARK: - hasContent Tests
    
    func testHasContent_EmptyString_ReturnsFalse() {
        XCTAssertFalse("".hasContent)
    }
    
    func testHasContent_WhitespaceString_ReturnsFalse() {
        XCTAssertFalse("   ".hasContent)
        XCTAssertFalse("\t\n".hasContent)
        XCTAssertFalse(" \t \n ".hasContent)
    }
    
    func testHasContent_NonEmptyString_ReturnsTrue() {
        XCTAssertTrue("Hello".hasContent)
        XCTAssertTrue(" Hello ".hasContent)
        XCTAssertTrue("\tWorld\n".hasContent)
    }
    
    // MARK: - trimmed Tests
    
    func testTrimmed_RemovesWhitespace() {
        XCTAssertEqual("  Hello  ".trimmed, "Hello")
        XCTAssertEqual("\tWorld\n".trimmed, "World")
        XCTAssertEqual(" \t Test \n ".trimmed, "Test")
    }
    
    func testTrimmed_EmptyString_ReturnsEmpty() {
        XCTAssertEqual("".trimmed, "")
        XCTAssertEqual("   ".trimmed, "")
        XCTAssertEqual("\t\n".trimmed, "")
    }
    
    func testTrimmed_NoWhitespace_ReturnsSame() {
        XCTAssertEqual("Hello".trimmed, "Hello")
        XCTAssertEqual("HelloWorld".trimmed, "HelloWorld")
    }
    
    // MARK: - normalized Tests
    
    func testNormalized_TrimsAndLowercases() {
        XCTAssertEqual("  HELLO  ".normalized, "hello")
        XCTAssertEqual("\tWORLD\n".normalized, "world")
        XCTAssertEqual(" Test String ".normalized, "test string")
    }
    
    func testNormalized_EmptyString_ReturnsEmpty() {
        XCTAssertEqual("".normalized, "")
        XCTAssertEqual("   ".normalized, "")
    }
    
    // MARK: - startsWithAny Tests
    
    func testStartsWithAny_MatchesPrefix() {
        let string = "wss://relay.example.com"
        XCTAssertTrue(string.startsWithAny(of: ["ws://", "wss://"]))
        XCTAssertTrue(string.startsWithAny(of: ["http://", "wss://"]))
    }
    
    func testStartsWithAny_CaseInsensitive() {
        let string = "WSS://relay.example.com"
        XCTAssertTrue(string.startsWithAny(of: ["ws://", "wss://"]))
        
        let string2 = "wss://relay.example.com"
        XCTAssertTrue(string2.startsWithAny(of: ["WS://", "WSS://"]))
    }
    
    func testStartsWithAny_NoMatch() {
        let string = "https://example.com"
        XCTAssertFalse(string.startsWithAny(of: ["ws://", "wss://"]))
    }
    
    func testStartsWithAny_EmptyPrefixes() {
        let string = "test"
        XCTAssertFalse(string.startsWithAny(of: []))
    }
    
    // MARK: - isWebSocketURL Tests
    
    func testIsWebSocketURL_ValidURLs() {
        XCTAssertTrue("wss://relay.example.com".isWebSocketURL)
        XCTAssertTrue("ws://relay.example.com".isWebSocketURL)
        XCTAssertTrue("WSS://RELAY.EXAMPLE.COM".isWebSocketURL)
    }
    
    func testIsWebSocketURL_InvalidURLs() {
        XCTAssertFalse("https://example.com".isWebSocketURL)
        XCTAssertFalse("relay.example.com".isWebSocketURL)
        XCTAssertFalse("".isWebSocketURL)
    }
    
    // MARK: - isValidURL Tests
    
    func testIsValidURL_ValidURLs() {
        XCTAssertTrue("https://example.com".isValidURL)
        XCTAssertTrue("http://example.com".isValidURL)
        XCTAssertTrue("wss://relay.example.com".isValidURL)
        XCTAssertTrue("ftp://server.com".isValidURL)
    }
    
    func testIsValidURL_InvalidURLs() {
        // Foundation's URL(string:) is quite permissive, so we test what it actually considers invalid
        XCTAssertFalse("".isValidURL)
        
        // Test some edge cases that URL(string:) does handle
        XCTAssertTrue("not a url".isValidURL) // URL(string:) treats this as a relative URL
        XCTAssertTrue("://invalid".isValidURL) // URL(string:) accepts malformed schemes
        XCTAssertTrue("http://".isValidURL)    // URL(string:) accepts URLs without paths
        
        // Test truly invalid URLs that URL(string:) rejects
        // URLs with null characters are rejected by Foundation
        let nullCharURL = "http://example.com\0invalid"
        XCTAssertFalse(nullCharURL.isValidURL)
    }
    
    // MARK: - Hex Validation Tests
    
    func testIsValid32ByteHex() {
        let valid32ByteHex = String(repeating: "a", count: 64)
        XCTAssertTrue(valid32ByteHex.isValid32ByteHex)
        
        let invalid = [
            String(repeating: "a", count: 63),  // Too short
            String(repeating: "a", count: 65),  // Too long
            String(repeating: "g", count: 64),  // Invalid hex char
            ""
        ]
        
        for hex in invalid {
            XCTAssertFalse(hex.isValid32ByteHex)
        }
    }
    
    func testIsValid64ByteHex() {
        let valid64ByteHex = String(repeating: "b", count: 128)
        XCTAssertTrue(valid64ByteHex.isValid64ByteHex)
        
        let invalid = [
            String(repeating: "b", count: 127),  // Too short
            String(repeating: "b", count: 129),  // Too long
            String(repeating: "z", count: 128),  // Invalid hex char
            ""
        ]
        
        for hex in invalid {
            XCTAssertFalse(hex.isValid64ByteHex)
        }
    }
    
    // MARK: - Nostr Format Tests
    
    func testToNpub_ValidHex() throws {
        let pubkey = String(repeating: "a", count: 64)
        let npub = try String.toNpub(pubkey)
        XCTAssertTrue(npub.hasPrefix("npub1"))
    }
    
    func testFromNpub_ValidNpub() throws {
        // Generate a valid npub from a known public key
        let expectedPubkey = String(repeating: "0", count: 64)
        let npub = try String.toNpub(expectedPubkey)
        
        // Now decode it back
        let decodedPubkey = try String.fromNpub(npub)
        XCTAssertNotNil(decodedPubkey)
        XCTAssertEqual(decodedPubkey, expectedPubkey)
        XCTAssertEqual(decodedPubkey?.count, 64)
    }
    
    func testNormalizedRelayURL() {
        let tests = [
            ("wss://relay.example.com", "wss://relay.example.com/"),
            ("WSS://RELAY.EXAMPLE.COM", "wss://relay.example.com/"),
            ("wss://relay.example.com/", "wss://relay.example.com/"),
            ("relay.example.com", "wss://relay.example.com/")
        ]
        
        for (input, expected) in tests {
            let normalized = input.normalizedRelayURL
            XCTAssertEqual(normalized, expected, "Failed to normalize '\(input)'")
        }
    }
    
    // MARK: - Formatted Relay URL Tests
    
    func testFormattedRelayURL() {
        let tests = [
            ("wss://relay.example.com/", "relay.example.com"),
            ("ws://relay.example.com/", "relay.example.com"),
            ("wss://relay.example.com", "relay.example.com"),
            ("https://relay.example.com/", "https://relay.example.com"), // Non-WebSocket URLs just remove trailing slash
            ("relay.example.com", "relay.example.com")
        ]
        
        for (input, expected) in tests {
            let formatted = input.formattedRelayURL
            XCTAssertEqual(formatted, expected, "Failed to format '\(input)'")
        }
    }
    
    func testTruncatedRelayURL() {
        // Test truncation with default max length (25)
        let longRelay = "wss://very-long-relay-name-that-exceeds-limit.example.com/"
        let truncated = longRelay.truncatedRelayURL()
        XCTAssertLessThanOrEqual(truncated.count, 25)
        XCTAssertTrue(truncated.hasSuffix("..."))
        
        // Test truncation with custom max length
        let customTruncated = longRelay.truncatedRelayURL(maxLength: 15)
        XCTAssertLessThanOrEqual(customTruncated.count, 15)
        XCTAssertTrue(customTruncated.hasSuffix("..."))
        
        // Test short URL doesn't get truncated
        let shortRelay = "wss://short.com/"
        let notTruncated = shortRelay.truncatedRelayURL()
        XCTAssertEqual(notTruncated, "short.com")
        XCTAssertFalse(notTruncated.hasSuffix("..."))
    }
    
    // MARK: - Collection Extensions Tests
    
    func testStringCollectionNilIfEmpty() {
        let emptyArray: [String] = []
        XCTAssertNil(emptyArray.nilIfEmpty)
        
        let nonEmptyArray = ["a", "b", "c"]
        XCTAssertNotNil(nonEmptyArray.nilIfEmpty)
        XCTAssertEqual(nonEmptyArray.nilIfEmpty?.count, 3)
    }
    
    func testStringCollectionSetOrNil() {
        let emptyArray: [String] = []
        XCTAssertNil(emptyArray.setOrNil)
        
        let nonEmptyArray = ["a", "b", "c", "a"] // Includes duplicate
        let resultSet = nonEmptyArray.setOrNil
        XCTAssertNotNil(resultSet)
        XCTAssertEqual(resultSet?.count, 3) // Should deduplicate
        XCTAssertTrue(resultSet?.contains("a") == true)
        XCTAssertTrue(resultSet?.contains("b") == true)
        XCTAssertTrue(resultSet?.contains("c") == true)
    }
}