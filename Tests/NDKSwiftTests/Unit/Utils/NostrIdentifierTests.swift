import XCTest
@testable import NDKSwift

final class NostrIdentifierTests: XCTestCase {
    
    // MARK: - Hex ID Tests
    
    func testCreateFilterFromHexEventId() throws {
        let hexEventId = "d7dd5eb3ab747e16f8d0212d53032ea2a7cadef53837e5a6c66d42849fcb9027"
        
        let filter = try NostrIdentifier.createFilter(from: hexEventId)
        
        XCTAssertEqual(filter.ids, [hexEventId])
        XCTAssertNil(filter.authors)
        XCTAssertNil(filter.kinds)
    }
    
    func testCreateFilterFromInvalidHexEventId() {
        let invalidHex = "not-a-valid-hex-id"
        
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: invalidHex)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            
            if case .invalidEventID(let message) = ndkError {
                XCTAssertTrue(message.contains("64-character hex"))
            } else {
                XCTFail("Expected invalidEventID error")
            }
        }
    }
    
    func testCreateFilterFromShortHexId() {
        let shortHex = "d7dd5eb3ab747e16"
        
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: shortHex)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            
            if case .invalidEventID = ndkError {
                // Expected error
            } else {
                XCTFail("Expected invalidEventID error")
            }
        }
    }
    
    // MARK: - Note Bech32 Tests
    
    func testCreateFilterFromNoteBech32() throws {
        let noteId = "note1g7r4q7vzqxkwz9k5ppkne4tzdy0n5r58j58v93snc5e5u9pm2jjqhyfhaa"
        
        let filter = try NostrIdentifier.createFilter(from: noteId)
        
        XCTAssertNotNil(filter.ids)
        XCTAssertEqual(filter.ids?.count, 1)
        XCTAssertNil(filter.authors)
        XCTAssertNil(filter.kinds)
    }
    
    // MARK: - Nevent Bech32 Tests
    
    func testCreateFilterFromNeventBech32() throws {
        // Create a test nevent with known values
        let testEventId = "d7dd5eb3ab747e16f8d0212d53032ea2a7cadef53837e5a6c66d42849fcb9027"
        let testRelay = "wss://relay.damus.io"
        
        // Build nevent manually
        var tlvData = Data()
        
        // Add event ID (type 0)
        tlvData.append(0x00) // type
        tlvData.append(0x20) // length (32 bytes)
        tlvData.append(Data(hex: testEventId))
        
        // Add relay (type 1)
        let relayData = testRelay.data(using: .utf8)!
        tlvData.append(0x01) // type
        tlvData.append(UInt8(relayData.count)) // length
        tlvData.append(relayData)
        
        let nevent = try Bech32.encode(hrp: "nevent", data: tlvData.bytes)
        
        let filter = try NostrIdentifier.createFilter(from: nevent)
        
        XCTAssertEqual(filter.ids, [testEventId])
        XCTAssertNil(filter.authors)
        XCTAssertNil(filter.kinds)
    }
    
    // MARK: - Naddr Bech32 Tests
    
    func testCreateFilterFromNaddrBech32() throws {
        // Create a test naddr with known values
        let testPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let testDTag = "test-article"
        let testKind: Int32 = 30023 // Long-form content
        
        // Build naddr manually
        var tlvData = Data()
        
        // Add d tag (type 0)
        let dTagData = testDTag.data(using: .utf8)!
        tlvData.append(0x00) // type
        tlvData.append(UInt8(dTagData.count)) // length
        tlvData.append(dTagData)
        
        // Add author (type 2)
        tlvData.append(0x02) // type
        tlvData.append(0x20) // length (32 bytes)
        tlvData.append(Data(hex: testPubkey))
        
        // Add kind (type 3)
        tlvData.append(0x03) // type
        tlvData.append(0x04) // length (4 bytes)
        var kindBigEndian = testKind.bigEndian
        tlvData.append(Data(bytes: &kindBigEndian, count: 4))
        
        let naddr = try Bech32.encode(hrp: "naddr", data: tlvData.bytes)
        
        let filter = try NostrIdentifier.createFilter(from: naddr)
        
        XCTAssertEqual(filter.authors, [testPubkey])
        XCTAssertEqual(filter.kinds, [Int(testKind)])
        XCTAssertEqual(filter.tags?["d"], Set([testDTag]))
    }
    
    // MARK: - Error Cases
    
    func testCreateFilterFromUnsupportedBech32Type() throws {
        // Create an npub (which is not supported for creating filters)
        let hexPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let npub = try Bech32.encode(hrp: "npub", data: Data(hex: hexPubkey).bytes)
        
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: npub)) { error in
            guard let ndkError = error as? NDKError else {
                XCTFail("Expected NDKError")
                return
            }
            
            switch ndkError {
            case .invalidDataFormat(let type, let details):
                XCTAssertEqual(type, "bech32")
                XCTAssertTrue(details?.contains("Unsupported type") ?? false)
            default:
                XCTFail("Expected invalidDataFormat error")
            }
        }
    }
    
    func testCreateFilterFromInvalidBech32() {
        let invalidBech32 = "invalid1bech32string"
        
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: invalidBech32)) { error in
            // Should throw an error when trying to decode
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Mixed Case Tests
    
    func testCreateFilterFromUppercaseHex() throws {
        let uppercaseHex = "D7DD5EB3AB747E16F8D0212D53032EA2A7CADEF53837E5A6C66D42849FCB9027"
        
        let filter = try NostrIdentifier.createFilter(from: uppercaseHex)
        
        // Should normalize to lowercase
        XCTAssertEqual(filter.ids, [uppercaseHex.lowercased()])
    }
}