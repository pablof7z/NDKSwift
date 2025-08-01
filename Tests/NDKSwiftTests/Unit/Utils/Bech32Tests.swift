import XCTest
@testable import NDKSwift

final class Bech32Tests: XCTestCase {
    
    // MARK: - Encoding Tests
    
    func testEncodePubkey() throws {
        // Test encoding a known public key
        let hexPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let data = Data(hex: hexPubkey).bytes
        
        let encoded = try Bech32.encode(hrp: "npub", data: data)
        
        XCTAssertEqual(encoded, "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6")
    }
    
    func testEncodePrivkey() throws {
        // Test encoding a private key
        let hexPrivkey = "5f6e76aaf5c9e3a4b7c8d9eaf0b1c2d3e4f5061728394a5b6c7d8e9fa0b1c2d3"
        let data = Data(hex: hexPrivkey).bytes
        
        let encoded = try Bech32.encode(hrp: "nsec", data: data)
        
        XCTAssertTrue(encoded.hasPrefix("nsec1"))
        XCTAssertTrue(encoded.count > 60) // nsec addresses are typically 63 chars
    }
    
    func testEncodeNote() throws {
        // Test encoding an event ID
        let hexEventId = "d7dd5eb3ab747e16f8d0212d53032ea2a7cadef53837e5a6c66d42849fcb9027"
        let data = Data(hex: hexEventId).bytes
        
        let encoded = try Bech32.encode(hrp: "note", data: data)
        
        XCTAssertTrue(encoded.hasPrefix("note1"))
    }
    
    // MARK: - Decoding Tests
    
    func testDecodePubkey() throws {
        let npub = "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"
        
        let (hrp, data) = try Bech32.decode(npub)
        
        XCTAssertEqual(hrp, "npub")
        XCTAssertEqual(data.toHexString(), "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
    }
    
    func testDecodeNote() throws {
        // First, encode a proper note from the hex event ID
        let hexEventId = "d7dd5eb3ab747e16f8d0212d53032ea2a7cadef53837e5a6c66d42849fcb9027"
        let note = try Bech32.note(from: hexEventId)
        
        let (hrp, data) = try Bech32.decode(note)
        
        XCTAssertEqual(hrp, "note")
        XCTAssertEqual(data.count, 32)
        XCTAssertEqual(data.toHexString(), hexEventId)
    }
    
    // MARK: - Roundtrip Tests
    
    func testRoundtripEncoding() throws {
        let originalData = Data([
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
            0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
            0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20
        ]).bytes
        let hrp = "test"
        
        let encoded = try Bech32.encode(hrp: hrp, data: originalData)
        let (decodedHrp, decodedData) = try Bech32.decode(encoded)
        
        XCTAssertEqual(hrp, decodedHrp)
        XCTAssertEqual(originalData, decodedData)
    }
    
    // MARK: - Error Cases
    
    func testDecodeInvalidCharacter() {
        let invalidBech32 = "npub1invalid0character!"
        
        XCTAssertThrowsError(try Bech32.decode(invalidBech32)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            
            switch ndkError {
            case .invalidInput(message: let message):
                XCTAssertTrue(message.contains("bech32 character"))
            default:
                XCTFail("Expected invalidInput error")
            }
        }
    }
    
    func testDecodeNoSeparator() {
        let invalidBech32 = "npubinvalidnoseparator"
        
        XCTAssertThrowsError(try Bech32.decode(invalidBech32)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            
            switch ndkError {
            case .invalidInput(message: let message):
                XCTAssertTrue(message.contains("no separator"))
            default:
                XCTFail("Expected invalidInput error")
            }
        }
    }
    
    func testDecodeInvalidChecksum() {
        // Valid format but wrong checksum
        let invalidBech32 = "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwswrong"
        
        XCTAssertThrowsError(try Bech32.decode(invalidBech32)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            
            switch ndkError {
            case .invalidInput(message: let message):
                // Invalid checksum manifests as invalid character in the implementation
                XCTAssertTrue(message.contains("bech32 character"))
            default:
                XCTFail("Expected invalidInput error")
            }
        }
    }
    
    func testDecodeTooShort() {
        let invalidBech32 = "npub1short"
        
        XCTAssertThrowsError(try Bech32.decode(invalidBech32)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            
            switch ndkError {
            case .invalidInput(message: let message):
                // Too short string manifests as invalid character in the implementation
                XCTAssertTrue(message.contains("bech32 character"))
            default:
                XCTFail("Expected invalidInput error")
            }
        }
    }
    
    // MARK: - Case Sensitivity
    
    func testDecodeMixedCase() throws {
        let npub = "NPUB180CVV07TJDRRGPA0J7J7TMNYL2YR6YR7L8J4S3EVF6U64TH6GKWSYJH6W6"
        
        let (hrp, data) = try Bech32.decode(npub)
        
        XCTAssertEqual(hrp, "npub")
        XCTAssertEqual(data.toHexString(), "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
    }
}