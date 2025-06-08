import XCTest
@testable import NDKSwift

final class JSONCodingTests: XCTestCase {
    
    struct TestModel: Codable, Equatable {
        let id: String
        let value: Int
        let tags: [String]
    }
    
    let testModel = TestModel(id: "test123", value: 42, tags: ["nostr", "swift"])
    
    func testEncodeAndDecode() throws {
        // Test encode/decode cycle
        let data = try JSONCoding.encode(testModel)
        let decoded = try JSONCoding.decode(TestModel.self, from: data)
        XCTAssertEqual(decoded, testModel)
    }
    
    func testEncodeToString() throws {
        let jsonString = try JSONCoding.encodeToString(testModel)
        XCTAssertTrue(jsonString.contains("\"id\":\"test123\""))
        XCTAssertTrue(jsonString.contains("\"value\":42"))
        XCTAssertFalse(jsonString.contains("\\/")) // No escaped slashes
    }
    
    func testDecodeFromString() throws {
        let jsonString = """
        {"id":"test123","tags":["nostr","swift"],"value":42}
        """
        let decoded = try JSONCoding.decode(TestModel.self, from: jsonString)
        XCTAssertEqual(decoded, testModel)
    }
    
    func testEncodeToDictionary() throws {
        let dict = try JSONCoding.encodeToDictionary(testModel)
        XCTAssertEqual(dict["id"] as? String, "test123")
        XCTAssertEqual(dict["value"] as? Int, 42)
        XCTAssertEqual(dict["tags"] as? [String], ["nostr", "swift"])
    }
    
    func testDecodeFromDictionary() throws {
        let dict: [String: Any] = [
            "id": "test123",
            "value": 42,
            "tags": ["nostr", "swift"]
        ]
        let decoded = try JSONCoding.decodeFromDictionary(TestModel.self, from: dict)
        XCTAssertEqual(decoded, testModel)
    }
    
    func testSafeDecode() {
        // Valid JSON
        let validJSON = """
        {"id":"test123","tags":["nostr","swift"],"value":42}
        """
        let decoded = JSONCoding.safeDecode(TestModel.self, from: validJSON)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, testModel)
        
        // Invalid JSON
        let invalidJSON = "not json"
        let failedDecode = JSONCoding.safeDecode(TestModel.self, from: invalidJSON)
        XCTAssertNil(failedDecode)
    }
    
    func testEncodeForNostr() throws {
        // Ensure Nostr encoding produces compact JSON
        let nostrJSON = try JSONCoding.encodeForNostr(testModel)
        XCTAssertFalse(nostrJSON.contains(" ")) // No extra spaces
        XCTAssertFalse(nostrJSON.contains("\n")) // No newlines
        XCTAssertTrue(nostrJSON.contains("\"id\":\"test123\""))
    }
    
    func testEncoderSettings() throws {
        // Test that encoder has sorted keys
        let model = TestModel(id: "abc", value: 123, tags: ["z", "a"])
        let json = try JSONCoding.encodeToString(model)
        
        // Check that keys appear in alphabetical order
        let idIndex = json.range(of: "\"id\"")!.lowerBound
        let tagsIndex = json.range(of: "\"tags\"")!.lowerBound
        let valueIndex = json.range(of: "\"value\"")!.lowerBound
        
        XCTAssertTrue(idIndex < tagsIndex)
        XCTAssertTrue(tagsIndex < valueIndex)
    }
    
    func testErrorHandling() {
        // Test invalid UTF-8 string error
        XCTAssertThrowsError(try JSONCoding.decode(TestModel.self, from: "")) { error in
            XCTAssertTrue(error is DecodingError)
        }
        
        // Test invalid dictionary conversion
        struct NotDictionaryModel: Codable {
            let value: String
        }
        
        let arrayModel = [NotDictionaryModel(value: "test")]
        XCTAssertThrowsError(try JSONCoding.encodeToDictionary(arrayModel)) { error in
            XCTAssertTrue(error is NDKError)
        }
    }
}