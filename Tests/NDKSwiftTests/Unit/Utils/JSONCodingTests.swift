@testable import NDKSwiftCore
import XCTest

final class JSONCodingTests: XCTestCase {
    struct TestModel: Codable, Equatable {
        let id: String
        let name: String
        let count: Int
        let tags: [String]
    }

    struct SnakeCaseModel: Codable, Equatable {
        let userId: String
        let userName: String
        let isActive: Bool
    }

    // MARK: - Encoding Tests

    func testEncode_basicModel() throws {
        let model = TestModel(id: "123", name: "Test", count: 42, tags: ["swift", "nostr"])

        let data = try JSONCoding.encode(model)
        XCTAssertNotNil(data)

        let string = try JSONCoding.encodeToString(model)
        XCTAssertTrue(string.contains("\"id\":\"123\""))
        XCTAssertTrue(string.contains("\"name\":\"Test\""))
        XCTAssertTrue(string.contains("\"count\":42"))
        XCTAssertTrue(string.contains("\"tags\":[\"swift\",\"nostr\"]"))
    }

    func testEncodeToString_sortsKeys() throws {
        let model = TestModel(id: "123", name: "Test", count: 42, tags: ["swift"])
        let string = try JSONCoding.encodeToString(model)

        // Keys should be alphabetically sorted
        let idIndex = string.range(of: "\"count\"")!.lowerBound
        let nameIndex = string.range(of: "\"id\"")!.lowerBound
        XCTAssertTrue(idIndex < nameIndex)
    }

    func testEncodeSnakeCase() throws {
        let model = SnakeCaseModel(userId: "123", userName: "Test User", isActive: true)
        let string = try JSONCoding.encodeSnakeCaseToString(model)

        XCTAssertTrue(string.contains("\"user_id\":\"123\""))
        XCTAssertTrue(string.contains("\"user_name\":\"Test User\""))
        XCTAssertTrue(string.contains("\"is_active\":true"))
        XCTAssertFalse(string.contains("userId"))
        XCTAssertFalse(string.contains("userName"))
    }

    func testEncodeForNostr_noEscapedSlashes() throws {
        let model = TestModel(id: "123", name: "https://nostr.com", count: 1, tags: [])
        let string = try JSONCoding.encodeForNostr(model)

        // Should not escape forward slashes
        XCTAssertTrue(string.contains("https://nostr.com"))
        XCTAssertFalse(string.contains("https:\\/\\/nostr.com"))
    }

    // MARK: - Decoding Tests

    func testDecode_fromData() throws {
        let json = """
        {"id":"456","name":"Decoded","count":100,"tags":["test","decode"]}
        """
        let data = json.data(using: .utf8)!

        let model = try JSONCoding.decode(TestModel.self, from: data)
        XCTAssertEqual(model.id, "456")
        XCTAssertEqual(model.name, "Decoded")
        XCTAssertEqual(model.count, 100)
        XCTAssertEqual(model.tags, ["test", "decode"])
    }

    func testDecode_fromString() throws {
        let json = """
        {"id":"789","name":"String Decode","count":200,"tags":[]}
        """

        let model = try JSONCoding.decode(TestModel.self, from: json)
        XCTAssertEqual(model.id, "789")
        XCTAssertEqual(model.name, "String Decode")
        XCTAssertEqual(model.count, 200)
        XCTAssertEqual(model.tags, [])
    }

    func testDecode_invalidJSON() {
        let invalidJSON = "not a json"

        XCTAssertThrowsError(try JSONCoding.decode(TestModel.self, from: invalidJSON))
    }

    // MARK: - Dictionary Conversion Tests

    func testEncodeToDictionary() throws {
        let model = TestModel(id: "dict", name: "Dictionary", count: 50, tags: ["dict"])
        let dict = try JSONCoding.encodeToDictionary(model)

        XCTAssertEqual(dict["id"] as? String, "dict")
        XCTAssertEqual(dict["name"] as? String, "Dictionary")
        XCTAssertEqual(dict["count"] as? Int, 50)
        XCTAssertEqual(dict["tags"] as? [String], ["dict"])
    }

    func testDecodeFromDictionary() throws {
        let dict: [String: Any] = [
            "id": "fromDict",
            "name": "From Dictionary",
            "count": 75,
            "tags": ["dictionary", "test"],
        ]

        let model = try JSONCoding.decodeFromDictionary(TestModel.self, from: dict)
        XCTAssertEqual(model.id, "fromDict")
        XCTAssertEqual(model.name, "From Dictionary")
        XCTAssertEqual(model.count, 75)
        XCTAssertEqual(model.tags, ["dictionary", "test"])
    }

    // MARK: - Safe Decoding Tests

    func testSafeDecode_validData() {
        let json = """
        {"id":"safe","name":"Safe Decode","count":1,"tags":[]}
        """
        let data = json.data(using: .utf8)!

        let model = JSONCoding.safeDecode(TestModel.self, from: data)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.id, "safe")
    }

    func testSafeDecode_invalidData() {
        let invalidData = "invalid".data(using: .utf8)!

        let model = JSONCoding.safeDecode(TestModel.self, from: invalidData)
        XCTAssertNil(model)
    }

    func testSafeDecode_validString() {
        let json = """
        {"id":"safeString","name":"Safe String","count":2,"tags":["safe"]}
        """

        let model = JSONCoding.safeDecode(TestModel.self, from: json)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.name, "Safe String")
    }

    // MARK: - JSONSerialization Helper Tests

    func testParseJSON_dictionary() throws {
        let json = """
        {"key":"value","number":42,"array":[1,2,3]}
        """
        let data = json.data(using: .utf8)!

        let parsed = try JSONCoding.parseJSON(from: data)
        let dict = parsed as? [String: Any]
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?["key"] as? String, "value")
        XCTAssertEqual(dict?["number"] as? Int, 42)
    }

    func testParseJSON_array() throws {
        let json = """
        [1, "two", {"three": 3}]
        """
        let data = json.data(using: .utf8)!

        let parsed = try JSONCoding.parseJSON(from: data)
        let array = parsed as? [Any]
        XCTAssertNotNil(array)
        XCTAssertEqual(array?.count, 3)
        XCTAssertEqual(array?[0] as? Int, 1)
        XCTAssertEqual(array?[1] as? String, "two")
    }

    func testParseDictionary_validDictionary() throws {
        let json = """
        {"valid":"dictionary","test":true}
        """

        let dict = try JSONCoding.parseDictionary(from: json)
        XCTAssertEqual(dict["valid"] as? String, "dictionary")
        XCTAssertEqual(dict["test"] as? Bool, true)
    }

    func testParseDictionary_invalidType() {
        let json = "[1,2,3]" // Array, not dictionary

        XCTAssertThrowsError(try JSONCoding.parseDictionary(from: json)) { error in
            if let ndkError = error as? NDKError {
                switch ndkError {
                case let .invalidInput(message):
                    XCTAssertTrue(message.contains("JSON dictionary"))
                    XCTAssertTrue(message.contains("Expected dictionary"))
                default:
                    XCTFail("Wrong error type: \(ndkError)")
                }
            }
        }
    }

    func testParseArray_validArray() throws {
        let json = """
        ["item1", "item2", "item3"]
        """

        let array = try JSONCoding.parseArray(from: json)
        XCTAssertEqual(array.count, 3)
        XCTAssertEqual(array[0] as? String, "item1")
    }

    func testParseArray_emptyString() {
        XCTAssertThrowsError(try JSONCoding.parseArray(from: "")) { error in
            if let ndkError = error as? NDKError {
                switch ndkError {
                case let .invalidInput(message):
                    XCTAssertTrue(message.contains("Empty string"))
                default:
                    XCTFail("Wrong error type: \(ndkError)")
                }
            }
        }
    }

    // MARK: - Serialization Tests

    func testSerialize_dictionary() throws {
        let dict: [String: Any] = ["key": "value", "number": 123]
        let data = try JSONCoding.serialize(dict)

        let parsed = try JSONCoding.parseDictionary(from: data)
        XCTAssertEqual(parsed["key"] as? String, "value")
        XCTAssertEqual(parsed["number"] as? Int, 123)
    }

    func testSerializeToString_array() throws {
        let array = ["one", "two", "three"]
        let string = try JSONCoding.serializeToString(array)

        XCTAssertTrue(string.contains("\"one\""))
        XCTAssertTrue(string.contains("\"two\""))
        XCTAssertTrue(string.contains("\"three\""))
    }

    // MARK: - Safe Parsing Tests

    func testSafeParseJSON_validData() {
        let json = """
        {"safe":"parse"}
        """
        let data = json.data(using: .utf8)!

        let parsed = JSONCoding.safeParseJSON(from: data)
        XCTAssertNotNil(parsed)
    }

    func testSafeParseDictionary_invalidData() {
        let data = "not json".data(using: .utf8)!

        let dict = JSONCoding.safeParseDictionary(from: data)
        XCTAssertNil(dict)
    }

    func testSafeParseArray_validData() {
        let json = "[1,2,3]"
        let data = json.data(using: .utf8)!

        let array = JSONCoding.safeParseArray(from: data)
        XCTAssertNotNil(array)
        XCTAssertEqual(array?.count, 3)
    }
}
