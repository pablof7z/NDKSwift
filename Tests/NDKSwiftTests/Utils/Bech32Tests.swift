import XCTest
@testable import NDKSwift

final class Bech32Tests: XCTestCase {
    
    func testBech32EncodeDecode() throws {
        // Test basic encode/decode
        let data: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
        print("Test data: \(data)")
        let encoded = try Bech32.encode(hrp: "test", data: data)
        print("Encoded: \(encoded)")
        
        XCTAssertTrue(encoded.hasPrefix("test1"))
        
        let (hrp, decoded) = try Bech32.decode(encoded)
        print("Decoded hrp: \(hrp)")
        print("Decoded data: \(decoded)")
        XCTAssertEqual(hrp, "test")
        XCTAssertEqual(decoded, data)
    }
    
    func testNpubEncoding() throws {
        let pubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        print("Testing npub encoding for pubkey: \(pubkey)")
        
        guard let data = Data(hexString: pubkey) else {
            XCTFail("Failed to create data from hex string")
            return
        }
        print("Data count: \(data.count)")
        print("Data hex: \(data.hexString)")
        
        let npub = try Bech32.npub(from: pubkey)
        
        XCTAssertTrue(npub.hasPrefix("npub1"))
        
        // Decode back
        let decodedPubkey = try Bech32.pubkey(from: npub)
        XCTAssertEqual(decodedPubkey, pubkey)
    }
    
    func testNsecEncoding() throws {
        let privateKey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let nsec = try Bech32.nsec(from: privateKey)
        
        XCTAssertTrue(nsec.hasPrefix("nsec1"))
        
        // Decode back
        let decodedPrivateKey = try Bech32.privateKey(from: nsec)
        XCTAssertEqual(decodedPrivateKey, privateKey)
    }
    
    func testNoteEncoding() throws {
        let eventId = "e0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59f"
        let note = try Bech32.note(from: eventId)
        
        XCTAssertTrue(note.hasPrefix("note1"))
        
        // Decode back
        let decodedEventId = try Bech32.eventId(from: note)
        XCTAssertEqual(decodedEventId, eventId)
    }
    
    func testInvalidBech32() {
        // Test invalid characters
        XCTAssertThrowsError(try Bech32.decode("test1invalid!character")) { error in
            if case Bech32.Bech32Error.invalidCharacter = error {
                // Success
            } else {
                XCTFail("Expected invalid character error")
            }
        }
        
        // Test invalid checksum (using valid characters but wrong checksum)
        XCTAssertThrowsError(try Bech32.decode("test1qqqsyqcyq5rqwzqfpg9scrgwpuccg6ks")) { error in
            if case Bech32.Bech32Error.invalidChecksum = error {
                // Success
            } else {
                XCTFail("Expected invalid checksum error, got: \(error)")
            }
        }
        
        // Test invalid HRP
        XCTAssertThrowsError(try Bech32.decode("noseparator")) { error in
            if case Bech32.Bech32Error.invalidHRP = error {
                // Success
            } else {
                XCTFail("Expected invalid HRP error")
            }
        }
    }
    
    func testWrongHRP() throws {
        let pubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let npub = try Bech32.npub(from: pubkey)
        
        // Try to decode npub as nsec
        XCTAssertThrowsError(try Bech32.privateKey(from: npub)) { error in
            if case Bech32.Bech32Error.invalidHRP = error {
                // Success
            } else {
                XCTFail("Expected invalid HRP error")
            }
        }
    }
    
    func testCaseInsensitive() throws {
        let pubkey = "d0a1ffb8761b974cec4a3be8cbcb2e96a7090dcf465ffeac839aa4ca20c9a59e"
        let npub = try Bech32.npub(from: pubkey)
        
        // Should decode uppercase
        let decodedUpper = try Bech32.pubkey(from: npub.uppercased())
        XCTAssertEqual(decodedUpper, pubkey)
        
        // Should decode mixed case
        let mixedCase = String(npub.enumerated().map { index, char in
            index % 2 == 0 ? Character(String(char).uppercased()) : char
        })
        let decodedMixed = try Bech32.pubkey(from: mixedCase)
        XCTAssertEqual(decodedMixed, pubkey)
    }
    
    func testDataHexConversion() {
        // Test hex to data
        let hex = "deadbeef"
        let data = Data(hexString: hex)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.count, 4)
        
        // Test data to hex
        XCTAssertEqual(data?.hexString, hex)
        
        // Test invalid hex
        XCTAssertNil(Data(hexString: "invalid"))
        XCTAssertNil(Data(hexString: "deadbee")) // Odd length
    }
    
    func testRoundTripConversions() throws {
        // Generate random data and test round trips
        for _ in 0..<10 {
            let randomBytes = Crypto.randomBytes(count: 32)
            let hex = randomBytes.hexString
            
            // Test npub round trip
            let npub = try Bech32.npub(from: hex)
            let decodedNpub = try Bech32.pubkey(from: npub)
            XCTAssertEqual(decodedNpub, hex)
            
            // Test nsec round trip
            let nsec = try Bech32.nsec(from: hex)
            let decodedNsec = try Bech32.privateKey(from: nsec)
            XCTAssertEqual(decodedNsec, hex)
            
            // Test note round trip
            let note = try Bech32.note(from: hex)
            let decodedNote = try Bech32.eventId(from: note)
            XCTAssertEqual(decodedNote, hex)
        }
    }
}