@testable import NDKSwiftCore
import XCTest

final class HexValidatorTests: XCTestCase {
    func testIsValidHexStringWithValidHex() {
        XCTAssertTrue(HexValidator.isValidHex("abcdef"))
        XCTAssertTrue(HexValidator.isValidHex("0123456789"))
        XCTAssertTrue(HexValidator.isValidHex("ABCDEF"))
        XCTAssertTrue(HexValidator.isValidHex("a1b2c3d4e5f6"))
    }

    func testIsValidHexStringWithInvalidHex() {
        XCTAssertFalse(HexValidator.isValidHex("ghijkl"))
        XCTAssertFalse(HexValidator.isValidHex("xyz123"))
        XCTAssertFalse(HexValidator.isValidHex("!@#$%^"))
        XCTAssertFalse(HexValidator.isValidHex("hello world"))
    }

    func testIsValidHexStringWithEmptyString() {
        XCTAssertTrue(HexValidator.isValidHex(""))
    }

    func testIsValidHexStringWithMixedCase() {
        XCTAssertTrue(HexValidator.isValidHex("aAbBcCdDeEfF"))
    }

    func testIsValidHexPubkeyWithValidPubkey() {
        let validPubkey = "a1b2c3d4e5f67890123456789012345678901234567890123456789012345678"
        XCTAssertTrue(HexValidator.isValid32ByteHex(validPubkey))
    }

    func testIsValidHexPubkeyWithInvalidLength() {
        // Too short
        XCTAssertFalse(HexValidator.isValid32ByteHex("a1b2c3"))
        // Too long
        XCTAssertFalse(HexValidator.isValid32ByteHex("a1b2c3d4e5f678901234567890123456789012345678901234567890123456789"))
        // Wrong length but valid hex
        XCTAssertFalse(HexValidator.isValid32ByteHex("a1b2c3d4e5f678901234567890123456789012345678901234567890123456"))
    }

    func testIsValidHexPubkeyWithInvalidCharacters() {
        let invalidPubkey = "g1b2c3d4e5f6789012345678901234567890123456789012345678901234567"
        XCTAssertFalse(HexValidator.isValid32ByteHex(invalidPubkey))
    }

    func testIsValidEventIdWithValidId() {
        let validEventId = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        XCTAssertTrue(HexValidator.isValid32ByteHex(validEventId))
    }

    func testIsValidEventIdWithInvalidLength() {
        // Too short
        XCTAssertFalse(HexValidator.isValid32ByteHex("0123456789"))
        // Too long
        XCTAssertFalse(HexValidator.isValid32ByteHex("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0"))
    }

    func testIsValidEventIdWithInvalidCharacters() {
        let invalidEventId = "z123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        XCTAssertFalse(HexValidator.isValid32ByteHex(invalidEventId))
    }

    func testIsValidSignatureWithValidSignature() {
        let validSig = String(repeating: "a", count: 128)
        XCTAssertTrue(HexValidator.isValid64ByteHex(validSig))
    }

    func testIsValidSignatureWithInvalidLength() {
        // Too short
        XCTAssertFalse(HexValidator.isValid64ByteHex(String(repeating: "a", count: 127)))
        // Too long
        XCTAssertFalse(HexValidator.isValid64ByteHex(String(repeating: "a", count: 129)))
    }

    func testIsValidSignatureWithInvalidCharacters() {
        let invalidSig = String(repeating: "g", count: 128)
        XCTAssertFalse(HexValidator.isValid64ByteHex(invalidSig))
    }

    // MARK: - Tests for throwing validation methods

    func testValidateHexWithValidInput() throws {
        let hexString = "abcdef0123456789"
        let data = try HexValidator.validateHex(hexString)
        XCTAssertEqual(data.count, 8)
    }

    func testValidateHexWithInvalidInput() {
        let hexString = "xyz123"
        XCTAssertThrowsError(try HexValidator.validateHex(hexString)) { error in
            guard case let HexValidator.HexValidationError.invalidHexString(invalidHex) = error else {
                XCTFail("Expected invalidHexString error")
                return
            }
            XCTAssertEqual(invalidHex, hexString)
        }
    }

    func testValidateHexWithExpectedByteCount() throws {
        let hexString = "abcd"
        let data = try HexValidator.validateHex(hexString, expectedByteCount: 2)
        XCTAssertEqual(data.count, 2)
    }

    func testValidateHexWithWrongByteCount() {
        let hexString = "abcd"
        XCTAssertThrowsError(try HexValidator.validateHex(hexString, expectedByteCount: 3)) { error in
            guard case let HexValidator.HexValidationError.invalidLength(expected, actual) = error else {
                XCTFail("Expected invalidLength error")
                return
            }
            XCTAssertEqual(expected, 3)
            XCTAssertEqual(actual, 2)
        }
    }

    func testValidate32ByteHex() throws {
        let hex32 = String(repeating: "a", count: 64)
        let data = try HexValidator.validate32ByteHex(hex32)
        XCTAssertEqual(data.count, 32)
    }

    func testValidate32ByteHexWithWrongLength() {
        let hexWrong = String(repeating: "a", count: 62)
        XCTAssertThrowsError(try HexValidator.validate32ByteHex(hexWrong))
    }

    func testValidate64ByteHex() throws {
        let hex64 = String(repeating: "b", count: 128)
        let data = try HexValidator.validate64ByteHex(hex64)
        XCTAssertEqual(data.count, 64)
    }

    func testValidate64ByteHexWithWrongLength() {
        let hexWrong = String(repeating: "b", count: 126)
        XCTAssertThrowsError(try HexValidator.validate64ByteHex(hexWrong))
    }

    // MARK: - Tests for new convenience methods

    func testIsValidHexWithExpectedByteCount() {
        XCTAssertTrue(HexValidator.isValidHex("abcd", expectedByteCount: 2))
        XCTAssertFalse(HexValidator.isValidHex("abcd", expectedByteCount: 3))
        XCTAssertTrue(HexValidator.isValidHex("abcdef", expectedByteCount: nil))
    }

    func testIsValid32ByteHex() {
        let valid32 = String(repeating: "c", count: 64)
        let invalid32 = String(repeating: "c", count: 63)
        XCTAssertTrue(HexValidator.isValid32ByteHex(valid32))
        XCTAssertFalse(HexValidator.isValid32ByteHex(invalid32))
    }

    func testIsValid64ByteHex() {
        let valid64 = String(repeating: "d", count: 128)
        let invalid64 = String(repeating: "d", count: 127)
        XCTAssertTrue(HexValidator.isValid64ByteHex(valid64))
        XCTAssertFalse(HexValidator.isValid64ByteHex(invalid64))
    }

    // MARK: - Tests for safe data conversion methods

    func testDataFromHexString() {
        XCTAssertNotNil(HexValidator.data(from: "abcdef"))
        XCTAssertNil(HexValidator.data(from: "xyz"))
        XCTAssertNotNil(HexValidator.data(from: ""))
    }

    func testData32FromHexString() {
        let valid32 = String(repeating: "e", count: 64)
        let invalid32 = String(repeating: "e", count: 63)
        XCTAssertNotNil(HexValidator.data32(from: valid32))
        XCTAssertNil(HexValidator.data32(from: invalid32))
        XCTAssertNil(HexValidator.data32(from: "xyz"))
    }

    func testData64FromHexString() {
        let valid64 = String(repeating: "f", count: 128)
        let invalid64 = String(repeating: "f", count: 127)
        XCTAssertNotNil(HexValidator.data64(from: valid64))
        XCTAssertNil(HexValidator.data64(from: invalid64))
        XCTAssertNil(HexValidator.data64(from: "xyz"))
    }

    // MARK: - Error description tests

    func testHexValidationErrorDescriptions() {
        let invalidHexError = HexValidator.HexValidationError.invalidHexString("xyz")
        XCTAssertEqual(invalidHexError.errorDescription, "Invalid hex string: xyz")

        let invalidLengthError = HexValidator.HexValidationError.invalidLength(expected: 32, actual: 31)
        XCTAssertEqual(invalidLengthError.errorDescription, "Invalid hex string length: expected 32 bytes, got 31 bytes")

        let invalidFormatError = HexValidator.HexValidationError.invalidFormat
        XCTAssertEqual(invalidFormatError.errorDescription, "Invalid hex string format")
    }
}
