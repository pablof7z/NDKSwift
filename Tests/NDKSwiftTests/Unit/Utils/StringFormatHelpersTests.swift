import XCTest
@testable import NDKSwiftCore

final class StringFormatHelpersTests: XCTestCase {
    
    // MARK: - Validation Message Tests
    
    func testValidationError() {
        let error = StringFormatHelpers.validationError(field: "Email", requirement: "must be valid")
        XCTAssertEqual(error, "Email must be valid")
        
        let error2 = StringFormatHelpers.validationError(field: "Password", requirement: "must be at least 8 characters")
        XCTAssertEqual(error2, "Password must be at least 8 characters")
    }
    
    // MARK: - Relay URL Tests
    
    func testDisplayURL() {
        XCTAssertEqual(StringFormatHelpers.displayURL("wss://relay.example.com/"), "wss://relay.example.com")
        XCTAssertEqual(StringFormatHelpers.displayURL("wss://relay.example.com"), "wss://relay.example.com")
        XCTAssertEqual(StringFormatHelpers.displayURL("wss://relay.example.com//"), "wss://relay.example.com")
    }
    
    func testDisplayURLs() {
        let urls = ["wss://relay1.com/", "wss://relay2.com/", "wss://relay3.com"]
        let result = StringFormatHelpers.displayURLs(urls)
        XCTAssertEqual(result, "wss://relay1.com, wss://relay2.com, wss://relay3.com")
        
        let resultCustomSeparator = StringFormatHelpers.displayURLs(urls, separator: " | ")
        XCTAssertEqual(resultCustomSeparator, "wss://relay1.com | wss://relay2.com | wss://relay3.com")
    }
    
    // MARK: - Hex String Tests
    
    func testFormatHex() {
        XCTAssertEqual(StringFormatHelpers.formatHex("ABC123"), "abc123")
        XCTAssertEqual(StringFormatHelpers.formatHex("0xABC123"), "abc123")
        XCTAssertEqual(StringFormatHelpers.formatHex("0XABC123"), "abc123")
        XCTAssertEqual(StringFormatHelpers.formatHex("abc123"), "abc123")
    }
    
    func testTruncateHex() {
        let longHex = "abc123def456789012345678901234567890"
        XCTAssertEqual(StringFormatHelpers.truncateHex(longHex), "abc123...567890")
        XCTAssertEqual(StringFormatHelpers.truncateHex(longHex, prefixLength: 8, suffixLength: 8), "abc123de...34567890")
        
        // Short hex should not be truncated
        let shortHex = "abc123"
        XCTAssertEqual(StringFormatHelpers.truncateHex(shortHex), "abc123")
    }
    
    // MARK: - JSON Formatting Tests
    
    func testPrettyJSONFromDictionary() {
        let dict: [String: Any] = ["name": "test", "value": 123]
        let pretty = StringFormatHelpers.prettyJSON(from: dict)
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\"name\" : \"test\""))
        XCTAssertTrue(pretty!.contains("\"value\" : 123"))
    }
    
    func testPrettyJSONFromArray() {
        let array = ["item1", "item2", "item3"]
        let pretty = StringFormatHelpers.prettyJSON(from: array)
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\"item1\""))
        XCTAssertTrue(pretty!.contains("\"item2\""))
        XCTAssertTrue(pretty!.contains("\"item3\""))
    }
    
    func testPrettyJSONFromData() {
        let json = "{\"key\":\"value\"}"
        let data = json.data(using: .utf8)!
        let pretty = StringFormatHelpers.prettyJSON(from: data)
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\"key\" : \"value\""))
    }
    
    func testPrettyJSONFromInvalidData() {
        let invalidData = "not json".data(using: .utf8)!
        let pretty = StringFormatHelpers.prettyJSON(from: invalidData)
        XCTAssertNil(pretty)
    }
    
    // MARK: - Time Formatting Tests
    
    func testFormatTimestamp() {
        let timestamp: Timestamp = 1700000000
        let formatted = StringFormatHelpers.formatTimestamp(timestamp)
        XCTAssertFalse(formatted.isEmpty)
        // The exact format depends on locale and DateFormatters.display configuration
    }
    
    func testFormatTimeInterval() {
        XCTAssertEqual(StringFormatHelpers.formatTimeInterval(60), "1 minute")
        XCTAssertEqual(StringFormatHelpers.formatTimeInterval(3600), "1 hour")
        XCTAssertEqual(StringFormatHelpers.formatTimeInterval(86400), "1 day")
        XCTAssertEqual(StringFormatHelpers.formatTimeInterval(45), "45 seconds")
        XCTAssertEqual(StringFormatHelpers.formatTimeInterval(90), "1 minute") // Rounds to nearest unit
    }
    
    // MARK: - Edge Cases
    
    func testFormatHexWithEmptyString() {
        XCTAssertEqual(StringFormatHelpers.formatHex(""), "")
    }
    
    func testTruncateHexWithEmptyString() {
        XCTAssertEqual(StringFormatHelpers.truncateHex(""), "")
    }
    
    func testDisplayURLWithEmptyString() {
        XCTAssertEqual(StringFormatHelpers.displayURL(""), "")
    }
    
    func testDisplayURLsWithEmptyArray() {
        XCTAssertEqual(StringFormatHelpers.displayURLs([]), "")
    }
    
    func testFormatTimeIntervalWithZero() {
        XCTAssertEqual(StringFormatHelpers.formatTimeInterval(0), "0 seconds")
    }
    
    func testFormatTimeIntervalWithNegative() {
        XCTAssertEqual(StringFormatHelpers.formatTimeInterval(-60), "0 seconds")
    }
    
    func testValidationErrorWithEmptyStrings() {
        let error = StringFormatHelpers.validationError(field: "", requirement: "")
        XCTAssertEqual(error, " ")
    }
    
    func testTruncateHexWithCustomLengthsExceedingString() {
        let hex = "abc123"
        XCTAssertEqual(StringFormatHelpers.truncateHex(hex, prefixLength: 10, suffixLength: 10), "abc123")
    }
    
    func testFormatHexWithMixedCase0xPrefix() {
        XCTAssertEqual(StringFormatHelpers.formatHex("0XaBc123"), "abc123")
        XCTAssertEqual(StringFormatHelpers.formatHex("0xAbC123"), "abc123")
    }
    
    func testDisplayURLWithMultipleTrailingSlashes() {
        XCTAssertEqual(StringFormatHelpers.displayURL("wss://relay.example.com///"), "wss://relay.example.com")
    }
    
    func testPrettyJSONWithEmptyDictionary() {
        let dict: [String: Any] = [:]
        let pretty = StringFormatHelpers.prettyJSON(from: dict)
        XCTAssertNotNil(pretty)
        XCTAssertEqual(pretty, "{\n\n}")
    }
    
    func testPrettyJSONWithEmptyArray() {
        let array: [String] = []
        let pretty = StringFormatHelpers.prettyJSON(from: array)
        XCTAssertNotNil(pretty)
        XCTAssertEqual(pretty, "[\n\n]")
    }
}