import XCTest
@testable import NDKSwift

final class HexValidatorTests: XCTestCase {
    
    func testIsValidHexStringWithValidHex() {
        XCTAssertTrue(HexValidator.isValidHexString("abcdef"))
        XCTAssertTrue(HexValidator.isValidHexString("0123456789"))
        XCTAssertTrue(HexValidator.isValidHexString("ABCDEF"))
        XCTAssertTrue(HexValidator.isValidHexString("a1b2c3d4e5f6"))
    }
    
    func testIsValidHexStringWithInvalidHex() {
        XCTAssertFalse(HexValidator.isValidHexString("ghijkl"))
        XCTAssertFalse(HexValidator.isValidHexString("xyz123"))
        XCTAssertFalse(HexValidator.isValidHexString("!@#$%^"))
        XCTAssertFalse(HexValidator.isValidHexString("hello world"))
    }
    
    func testIsValidHexStringWithEmptyString() {
        XCTAssertTrue(HexValidator.isValidHexString(""))
    }
    
    func testIsValidHexStringWithMixedCase() {
        XCTAssertTrue(HexValidator.isValidHexString("aAbBcCdDeEfF"))
    }
    
    func testIsValidHexPubkeyWithValidPubkey() {
        let validPubkey = "a1b2c3d4e5f6789012345678901234567890123456789012345678901234567"
        XCTAssertTrue(HexValidator.isValidHexPubkey(validPubkey))
    }
    
    func testIsValidHexPubkeyWithInvalidLength() {
        // Too short
        XCTAssertFalse(HexValidator.isValidHexPubkey("a1b2c3"))
        // Too long
        XCTAssertFalse(HexValidator.isValidHexPubkey("a1b2c3d4e5f67890123456789012345678901234567890123456789012345678"))
        // Wrong length but valid hex
        XCTAssertFalse(HexValidator.isValidHexPubkey("a1b2c3d4e5f678901234567890123456789012345678901234567890123456"))
    }
    
    func testIsValidHexPubkeyWithInvalidCharacters() {
        let invalidPubkey = "g1b2c3d4e5f6789012345678901234567890123456789012345678901234567"
        XCTAssertFalse(HexValidator.isValidHexPubkey(invalidPubkey))
    }
    
    func testIsValidEventIdWithValidId() {
        let validEventId = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        XCTAssertTrue(HexValidator.isValidEventId(validEventId))
    }
    
    func testIsValidEventIdWithInvalidLength() {
        // Too short
        XCTAssertFalse(HexValidator.isValidEventId("0123456789"))
        // Too long
        XCTAssertFalse(HexValidator.isValidEventId("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0"))
    }
    
    func testIsValidEventIdWithInvalidCharacters() {
        let invalidEventId = "z123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        XCTAssertFalse(HexValidator.isValidEventId(invalidEventId))
    }
    
    func testIsValidSignatureWithValidSignature() {
        let validSig = String(repeating: "a", count: 128)
        XCTAssertTrue(HexValidator.isValidSignature(validSig))
    }
    
    func testIsValidSignatureWithInvalidLength() {
        // Too short
        XCTAssertFalse(HexValidator.isValidSignature(String(repeating: "a", count: 127)))
        // Too long
        XCTAssertFalse(HexValidator.isValidSignature(String(repeating: "a", count: 129)))
    }
    
    func testIsValidSignatureWithInvalidCharacters() {
        let invalidSig = String(repeating: "g", count: 128)
        XCTAssertFalse(HexValidator.isValidSignature(invalidSig))
    }
}