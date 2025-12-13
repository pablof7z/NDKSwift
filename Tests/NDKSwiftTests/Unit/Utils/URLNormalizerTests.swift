@testable import NDKSwiftCore
import XCTest

final class URLNormalizerTests: XCTestCase {
    // MARK: - Basic Normalization Tests

    func testBasicNormalization() throws {
        // Test basic WebSocket URLs
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("ws://relay.nostr.band"), "ws://relay.nostr.band/")
    }

    func testProtocolAddition() throws {
        // Test URLs without protocol default to wss://
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("relay.nostr.band"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("example.com:8080"), "wss://example.com:8080/")
    }

    func testTrailingSlashAddition() throws {
        // Test that trailing slash is always added
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band/"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band/path"), "wss://relay.nostr.band/path/")
    }

    // MARK: - Case Normalization Tests

    func testCaseNormalization() throws {
        // Test that scheme and host are lowercased
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("WSS://RELAY.NOSTR.BAND"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("WsS://ReLaY.NoStR.BaNd"), "wss://relay.nostr.band/")
    }

    // MARK: - Authentication Removal Tests

    func testAuthenticationRemoval() throws {
        // Test that username and password are removed
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://user:pass@relay.nostr.band"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://user@relay.nostr.band"), "wss://relay.nostr.band/")
    }

    // MARK: - Fragment Removal Tests

    func testFragmentRemoval() throws {
        // Test that fragments (hash) are removed
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band#fragment"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band/path#section"), "wss://relay.nostr.band/path/")
    }

    // MARK: - WWW Prefix Removal Tests

    func testWWWPrefixRemoval() throws {
        // Test that www. prefix is removed from hostname
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://www.relay.nostr.band"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://WWW.relay.nostr.band"), "wss://relay.nostr.band/")
    }

    // MARK: - Default Port Removal Tests

    func testDefaultPortRemoval() throws {
        // Test that default ports are removed
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band:443"), "wss://relay.nostr.band/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("ws://relay.nostr.band:80"), "ws://relay.nostr.band/")

        // Non-default ports should be preserved
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band:8080"), "wss://relay.nostr.band:8080/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("ws://relay.nostr.band:8000"), "ws://relay.nostr.band:8000/")
    }

    // MARK: - Query Parameter Tests

    func testQueryParameterHandling() throws {
        // Test that query parameters are preserved and slash comes before query
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band?param=value"), "wss://relay.nostr.band/?param=value")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band/path?param=value"), "wss://relay.nostr.band/path/?param=value")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band/?param=value"), "wss://relay.nostr.band/?param=value")
    }

    // MARK: - Complex URL Tests

    func testComplexURLNormalization() throws {
        // Test complex URLs with multiple normalizations needed
        let input = "WSS://user:pass@WWW.RELAY.NOSTR.BAND:443/path#fragment"
        let expected = "wss://relay.nostr.band/path/"
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl(input), expected)
    }

    func testComplexURLWithQuery() throws {
        // Test complex URL with query parameters
        let input = "WSS://WWW.RELAY.NOSTR.BAND:443/path?key=value&foo=bar#fragment"
        let expected = "wss://relay.nostr.band/path/?key=value&foo=bar"
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl(input), expected)
    }

    // MARK: - Error Handling Tests

    func testInvalidURLsThrowErrors() {
        // Test empty string
        XCTAssertThrowsError(try URLNormalizer.normalizeRelayUrl("")) { error in
            XCTAssertTrue(error is URLNormalizationError)
        }

        // Test URL with spaces
        XCTAssertThrowsError(try URLNormalizer.normalizeRelayUrl("wss://relay nostr band")) { error in
            XCTAssertTrue(error is URLNormalizationError)
        }

        // Test URL starting with ://
        XCTAssertThrowsError(try URLNormalizer.normalizeRelayUrl("://relay.nostr.band")) { error in
            XCTAssertTrue(error is URLNormalizationError)
        }

        // Test completely invalid URL
        XCTAssertThrowsError(try URLNormalizer.normalizeRelayUrl("not a url at all")) { error in
            XCTAssertTrue(error is URLNormalizationError)
        }
    }

    // MARK: - Try Normalize Tests

    func testTryNormalizeReturnsNilForInvalidURLs() {
        XCTAssertNil(URLNormalizer.tryNormalizeRelayUrl(""))
        XCTAssertNil(URLNormalizer.tryNormalizeRelayUrl("wss://relay nostr band"))
        XCTAssertNil(URLNormalizer.tryNormalizeRelayUrl("://relay.nostr.band"))

        // Valid URLs should return normalized value
        XCTAssertEqual(URLNormalizer.tryNormalizeRelayUrl("wss://relay.nostr.band"), "wss://relay.nostr.band/")
    }

    // MARK: - Array Normalization Tests

    func testArrayNormalization() {
        let urls = [
            "wss://relay1.nostr.band",
            "WSS://RELAY2.NOSTR.BAND",
            "relay3.nostr.band",
            "wss://www.relay1.nostr.band", // Duplicate after normalization
            "invalid url", // Should be filtered out
            "wss://relay2.nostr.band/", // Duplicate after normalization
        ]

        let normalized = URLNormalizer.normalize(urls)

        // Should have 3 unique, normalized URLs in sorted order
        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized, [
            "wss://relay1.nostr.band/",
            "wss://relay2.nostr.band/",
            "wss://relay3.nostr.band/",
        ])
    }

    // MARK: - WebSocket to HTTP Conversion Tests

    func testWebSocketToHTTPConversion() {
        // Test ws:// to http:// conversion
        let wsURL = URL(string: "ws://relay.nostr.band:8080/path")!
        let httpURL = URLNormalizer.convertWebSocketToHTTP(wsURL)
        XCTAssertEqual(httpURL?.absoluteString, "http://relay.nostr.band:8080/path")

        // Test wss:// to https:// conversion
        let wssURL = URL(string: "wss://relay.nostr.band/path?query=value")!
        let httpsURL = URLNormalizer.convertWebSocketToHTTP(wssURL)
        XCTAssertEqual(httpsURL?.absoluteString, "https://relay.nostr.band/path?query=value")

        // Test that non-WebSocket URLs are returned unchanged
        let httpOriginal = URL(string: "http://example.com")!
        let httpResult = URLNormalizer.convertWebSocketToHTTP(httpOriginal)
        XCTAssertEqual(httpResult, httpOriginal)

        let httpsOriginal = URL(string: "https://example.com")!
        let httpsResult = URLNormalizer.convertWebSocketToHTTP(httpsOriginal)
        XCTAssertEqual(httpsResult, httpsOriginal)
    }

    // MARK: - Edge Cases

    func testEdgeCases() throws {
        // Test URL with only protocol
        XCTAssertThrowsError(try URLNormalizer.normalizeRelayUrl("wss://")) { error in
            XCTAssertTrue(error is URLNormalizationError)
        }

        // Test URL with whitespace that should be trimmed
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("  wss://relay.nostr.band  "), "wss://relay.nostr.band/")

        // Test URL with multiple slashes in path - normalizer only adds slash if not present
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band//path///"), "wss://relay.nostr.band//path///")

        // Test URL with encoded characters
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.nostr.band/path%20with%20spaces"), "wss://relay.nostr.band/path%20with%20spaces/")
    }

    // MARK: - WebSocket to HTTP Conversion Tests

    func testConvertWebSocketToHTTP() {
        // Test ws:// to http:// conversion
        let wsURL = URL(string: "ws://relay.example.com/path")!
        let httpURL = URLNormalizer.convertWebSocketToHTTP(wsURL)
        XCTAssertEqual(httpURL?.absoluteString, "http://relay.example.com/path")

        // Test wss:// to https:// conversion
        let wssURL = URL(string: "wss://relay.example.com/path")!
        let httpsURL = URLNormalizer.convertWebSocketToHTTP(wssURL)
        XCTAssertEqual(httpsURL?.absoluteString, "https://relay.example.com/path")

        // Test non-WebSocket URLs remain unchanged
        let regularURL = URL(string: "https://example.com/path")!
        let unchangedURL = URLNormalizer.convertWebSocketToHTTP(regularURL)
        XCTAssertEqual(unchangedURL?.absoluteString, "https://example.com/path")

        // Test URL with query parameters
        let urlWithQuery = URL(string: "wss://relay.example.com/path?param=value")!
        let convertedWithQuery = URLNormalizer.convertWebSocketToHTTP(urlWithQuery)
        XCTAssertEqual(convertedWithQuery?.absoluteString, "https://relay.example.com/path?param=value")

        // Test URL with fragment
        let urlWithFragment = URL(string: "ws://relay.example.com/path#section")!
        let convertedWithFragment = URLNormalizer.convertWebSocketToHTTP(urlWithFragment)
        XCTAssertEqual(convertedWithFragment?.absoluteString, "http://relay.example.com/path#section")
    }
}
