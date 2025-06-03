import XCTest
@testable import NDKSwift

final class URLNormalizerTests: XCTestCase {
    
    func testBasicNormalization() throws {
        // Test basic URLs
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("relay.example.com"), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com"), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("ws://relay.example.com"), "ws://relay.example.com/")
    }
    
    func testTrailingSlashHandling() throws {
        // Should always add trailing slash (matching TypeScript behavior)
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com"), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com/"), "wss://relay.example.com/")
    }
    
    func testCaseNormalization() throws {
        // Should lowercase scheme and host
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("WSS://RELAY.EXAMPLE.COM"), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://RELAY.Example.COM/"), "wss://relay.example.com/")
    }
    
    func testWWWRemoval() throws {
        // Should remove www. prefix
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://www.relay.example.com"), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("www.relay.example.com"), "wss://relay.example.com/")
        
        // Should not remove www from middle of hostname
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.www.example.com"), "wss://relay.www.example.com/")
    }
    
    func testAuthenticationStripping() throws {
        // Should remove username and password
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://user:pass@relay.example.com"), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://user@relay.example.com"), "wss://relay.example.com/")
    }
    
    func testHashFragmentRemoval() throws {
        // Should remove hash fragments
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com#section"), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com/#hash"), "wss://relay.example.com/")
    }
    
    func testPortHandling() throws {
        // Should keep non-default ports
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com:8080"), "wss://relay.example.com:8080/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("ws://relay.example.com:3000"), "ws://relay.example.com:3000/")
        
        // Should remove default ports
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("ws://relay.example.com:80"), "ws://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com:443"), "wss://relay.example.com/")
    }
    
    func testPathHandling() throws {
        // Should preserve paths
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com/nostr"), "wss://relay.example.com/nostr/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com/path/to/relay"), "wss://relay.example.com/path/to/relay/")
    }
    
    func testQueryParameterHandling() throws {
        // Should preserve query parameters
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com?param=value"), "wss://relay.example.com/?param=value")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com/path?a=1&b=2"), "wss://relay.example.com/path/?a=1&b=2")
    }
    
    func testComplexURLs() throws {
        // Test complex URLs with multiple features
        XCTAssertEqual(
            try URLNormalizer.normalizeRelayUrl("WSS://user:pass@WWW.RELAY.EXAMPLE.COM:443/path#hash"),
            "wss://relay.example.com/path/"
        )
        
        XCTAssertEqual(
            try URLNormalizer.normalizeRelayUrl("ws://WWW.RELAY.EXAMPLE.COM:80/nostr?debug=true#section"),
            "ws://relay.example.com/nostr/?debug=true"
        )
    }
    
    func testInvalidURLs() {
        // Test that invalid URLs throw errors
        XCTAssertThrowsError(try URLNormalizer.normalizeRelayUrl("not a url")) { error in
            XCTAssertTrue(error is URLNormalizationError)
        }
        
        XCTAssertThrowsError(try URLNormalizer.normalizeRelayUrl("://invalid")) { error in
            XCTAssertTrue(error is URLNormalizationError)
        }
    }
    
    func testTryNormalizeRelayUrl() {
        // Test the non-throwing version
        XCTAssertEqual(URLNormalizer.tryNormalizeRelayUrl("wss://relay.example.com"), "wss://relay.example.com/")
        XCTAssertEqual(URLNormalizer.tryNormalizeRelayUrl("relay.example.com"), "wss://relay.example.com/")
        
        // Invalid URLs should return nil
        XCTAssertNil(URLNormalizer.tryNormalizeRelayUrl("not a url"))
        XCTAssertNil(URLNormalizer.tryNormalizeRelayUrl("://invalid"))
    }
    
    func testNormalizeArray() {
        let urls = [
            "relay1.example.com",
            "WSS://RELAY2.EXAMPLE.COM/",
            "wss://www.relay3.example.com",
            "wss://relay1.example.com/",  // Duplicate of first
            "not a valid url",  // Invalid, should be skipped
            "relay4.example.com:8080"
        ]
        
        let normalized = URLNormalizer.normalize(urls)
        
        // Should have 4 unique, valid URLs
        XCTAssertEqual(normalized.count, 4)
        
        // Should be sorted
        XCTAssertEqual(normalized, [
            "wss://relay1.example.com/",
            "wss://relay2.example.com/",
            "wss://relay3.example.com/",
            "wss://relay4.example.com:8080/"
        ])
    }
    
    func testWhitespaceHandling() throws {
        // Should trim whitespace
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("  wss://relay.example.com  "), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("\nwss://relay.example.com\n"), "wss://relay.example.com/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("\twss://relay.example.com\t"), "wss://relay.example.com/")
    }
    
    func testSpecialCharactersInPath() throws {
        // Should handle encoded characters in paths
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://relay.example.com/path%20with%20spaces"), "wss://relay.example.com/path%20with%20spaces/")
        // URLComponents will percent-encode emoji characters, which is correct behavior
        let emojiURL = try URLNormalizer.normalizeRelayUrl("wss://relay.example.com/emoji/🚀")
        XCTAssertTrue(emojiURL.hasPrefix("wss://relay.example.com/emoji/"))
        XCTAssertTrue(emojiURL.hasSuffix("/"))
    }
    
    func testIPAddresses() throws {
        // Should handle IP addresses
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://192.168.1.1"), "wss://192.168.1.1/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("ws://127.0.0.1:3000"), "ws://127.0.0.1:3000/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://[::1]"), "wss://[::1]/")
        XCTAssertEqual(try URLNormalizer.normalizeRelayUrl("wss://[2001:db8::1]:8080"), "wss://[2001:db8::1]:8080/")
    }
}