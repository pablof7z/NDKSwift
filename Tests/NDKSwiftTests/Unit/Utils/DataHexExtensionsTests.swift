@testable import NDKSwiftCore
import XCTest

final class DataHexExtensionsTests: XCTestCase {
    // MARK: - Data from hex string tests

    func testDataFromValidHexString() {
        let hex = "48656c6c6f" // "Hello" in hex
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 5)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    func testDataFromHexStringWith0xPrefix() {
        let hex = "0x48656c6c6f"
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    func testDataFromHexStringWith0XPrefix() {
        let hex = "0X48656c6c6f"
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    func testDataFromOddLengthHexString() {
        let hex = "123" // Odd length, should be padded to "0123"
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 2)
        XCTAssertEqual(data?[0], 0x01)
        XCTAssertEqual(data?[1], 0x23)
    }

    func testDataFromHexStringWithWhitespace() {
        let hex = "  48656c6c6f  \n"
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    func testDataFromInvalidHexString() {
        let invalidHex = "48656c6c6g" // 'g' is not a hex character
        let data = Data(hexString: invalidHex)
        XCTAssertNil(data)
    }

    func testDataFromEmptyHexString() {
        let hex = ""
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 0)
    }

    // MARK: - Data to hex string tests

    func testDataToHexString() {
        let data = "Hello".data(using: .utf8)!
        let hex = data.hexString
        XCTAssertEqual(hex, "48656c6c6f")
    }

    func testEmptyDataToHexString() {
        let data = Data()
        let hex = data.hexString
        XCTAssertEqual(hex, "")
    }

    func testBinaryDataToHexString() {
        let data = Data([0x00, 0xFF, 0xAB, 0xCD])
        let hex = data.hexString
        XCTAssertEqual(hex, "00ffabcd")
    }

    // MARK: - Data padding tests

    func testPaddingToLongerLength() {
        let data = Data([0x12, 0x34])
        let padded = data.paddedToLength(5)
        XCTAssertEqual(padded.count, 5)
        XCTAssertEqual([UInt8](padded), [0x12, 0x34, 0x00, 0x00, 0x00])
    }

    func testPaddingToSameLength() {
        let data = Data([0x12, 0x34])
        let padded = data.paddedToLength(2)
        XCTAssertEqual(padded.count, 2)
        XCTAssertEqual([UInt8](padded), [0x12, 0x34])
    }

    func testPaddingToShorterLength() {
        let data = Data([0x12, 0x34, 0x56])
        let padded = data.paddedToLength(2)
        XCTAssertEqual(padded.count, 3) // Should not truncate
        XCTAssertEqual([UInt8](padded), [0x12, 0x34, 0x56])
    }

    // MARK: - String hex decoding tests

    func testStringHexDecoded() {
        let hex = "48656c6c6f"
        let data = hex.hexDecoded()
        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    func testStringBytesProperty() {
        let hex = "48656c6c6f"
        let bytes = hex.bytes
        XCTAssertEqual(bytes, [0x48, 0x65, 0x6C, 0x6C, 0x6F])
    }

    func testStringBytesPropertyWithInvalidHex() {
        let hex = "invalid"
        let bytes = hex.bytes
        XCTAssertEqual(bytes, []) // Should return empty array for invalid hex
    }

    // MARK: - Edge cases

    func testUppercaseHex() {
        let hex = "48656C6C6F"
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }

    func testMixedCaseHex() {
        let hex = "48656c6C6f"
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(String(data: data!, encoding: .utf8), "Hello")
    }
}
