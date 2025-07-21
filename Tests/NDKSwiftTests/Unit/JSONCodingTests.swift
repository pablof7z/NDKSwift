import XCTest
@testable import NDKSwift

final class JSONCodingTests: XCTestCase {
    
    // MARK: - Parse Tests
    
    func testParseJSONFromData() throws {
        let json = #"{"key":"value","number":42}"#
        let data = json.data(using: .utf8)!
        
        let result = try JSONCoding.parseJSON(from: data)
        XCTAssertNotNil(result)
        
        let dict = result as? [String: Any]
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?["key"] as? String, "value")
        XCTAssertEqual(dict?["number"] as? Int, 42)
    }
    
    func testParseJSONFromString() throws {
        let json = #"[1, 2, 3, "hello"]"#
        
        let result = try JSONCoding.parseJSON(from: json)
        let array = result as? [Any]
        XCTAssertNotNil(array)
        XCTAssertEqual(array?.count, 4)
        XCTAssertEqual(array?[0] as? Int, 1)
        XCTAssertEqual(array?[3] as? String, "hello")
    }
    
    func testParseDictionary() throws {
        let json = #"{"name":"test","active":true}"#
        
        let dict = try JSONCoding.parseDictionary(from: json)
        XCTAssertEqual(dict["name"] as? String, "test")
        XCTAssertEqual(dict["active"] as? Bool, true)
    }
    
    func testParseDictionaryFailsOnArray() {
        let json = #"[1, 2, 3]"#
        
        XCTAssertThrowsError(try JSONCoding.parseDictionary(from: json)) { error in
            if case NDKError.invalidInput = error {
                // Expected error - parseError factory returns invalidInput
            } else {
                XCTFail("Expected invalidInput error but got \(error)")
            }
        }
    }
    
    func testParseArray() throws {
        let json = #"["EVENT", "sub123", {"id":"123"}]"#
        
        let array = try JSONCoding.parseArray(from: json)
        XCTAssertEqual(array.count, 3)
        XCTAssertEqual(array[0] as? String, "EVENT")
        XCTAssertEqual(array[1] as? String, "sub123")
        XCTAssertNotNil(array[2] as? [String: Any])
    }
    
    func testParseArrayFailsOnDictionary() {
        let json = #"{"not":"array"}"#
        
        XCTAssertThrowsError(try JSONCoding.parseArray(from: json)) { error in
            if case NDKError.invalidInput = error {
                // Expected error - parseError factory returns invalidInput
            } else {
                XCTFail("Expected invalidInput error but got \(error)")
            }
        }
    }
    
    // MARK: - Serialize Tests
    
    func testSerializeArray() throws {
        let array: [Any] = ["REQ", "sub123", ["kinds": [1, 3, 7]]]
        
        let jsonString = try JSONCoding.serializeToString(array)
        XCTAssertTrue(jsonString.contains("REQ"))
        XCTAssertTrue(jsonString.contains("sub123"))
        XCTAssertFalse(jsonString.contains("\\/")) // No escaped slashes
    }
    
    func testSerializeDictionary() throws {
        let dict: [String: Any] = [
            "id": "abc123",
            "pubkey": "def456",
            "created_at": 12345
        ]
        
        let jsonString = try JSONCoding.serializeToString(dict)
        XCTAssertTrue(jsonString.contains("\"id\":\"abc123\""))
        XCTAssertTrue(jsonString.contains("\"created_at\":12345"))
    }
    
    // MARK: - Safe Parse Tests
    
    func testSafeParseJSON() {
        let validJSON = #"{"valid":true}"#.data(using: .utf8)!
        let invalidJSON = "not json".data(using: .utf8)!
        
        XCTAssertNotNil(JSONCoding.safeParseJSON(from: validJSON))
        XCTAssertNil(JSONCoding.safeParseJSON(from: invalidJSON))
    }
    
    func testSafeParseDictionary() {
        let dictJSON = #"{"type":"dict"}"#.data(using: .utf8)!
        let arrayJSON = #"[1,2,3]"#.data(using: .utf8)!
        
        XCTAssertNotNil(JSONCoding.safeParseDictionary(from: dictJSON))
        XCTAssertNil(JSONCoding.safeParseDictionary(from: arrayJSON))
    }
    
    func testSafeParseArray() {
        let arrayJSON = #"["a","b","c"]"#.data(using: .utf8)!
        let dictJSON = #"{"not":"array"}"#.data(using: .utf8)!
        
        XCTAssertNotNil(JSONCoding.safeParseArray(from: arrayJSON))
        XCTAssertNil(JSONCoding.safeParseArray(from: dictJSON))
    }
    
    // MARK: - Integration Tests
    
    func testRoundTripDictionary() throws {
        let original: [String: Any] = [
            "name": "Test User",
            "age": 30,
            "verified": true,
            "tags": ["swift", "nostr", "test"]
        ]
        
        let jsonString = try JSONCoding.serializeToString(original)
        let parsed = try JSONCoding.parseDictionary(from: jsonString)
        
        XCTAssertEqual(parsed["name"] as? String, original["name"] as? String)
        XCTAssertEqual(parsed["age"] as? Int, original["age"] as? Int)
        XCTAssertEqual(parsed["verified"] as? Bool, original["verified"] as? Bool)
        
        let parsedTags = parsed["tags"] as? [String]
        let originalTags = original["tags"] as? [String]
        XCTAssertEqual(parsedTags, originalTags)
    }
    
    func testRoundTripArray() throws {
        let original: [Any] = ["EVENT", "subscription-id", ["id": "event123", "kind": 1]]
        
        let jsonString = try JSONCoding.serializeToString(original)
        let parsed = try JSONCoding.parseArray(from: jsonString)
        
        XCTAssertEqual(parsed[0] as? String, "EVENT")
        XCTAssertEqual(parsed[1] as? String, "subscription-id")
        
        let eventDict = parsed[2] as? [String: Any]
        XCTAssertNotNil(eventDict)
        XCTAssertEqual(eventDict?["id"] as? String, "event123")
        XCTAssertEqual(eventDict?["kind"] as? Int, 1)
    }
}