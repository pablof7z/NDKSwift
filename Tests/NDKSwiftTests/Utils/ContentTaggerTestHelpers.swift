import Foundation
@testable import NDKSwift

// Helper to generate valid test entities
struct TestEntities {
    static let testPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
    static let testPubkey2 = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
    static let testEventId = "3fa020984203d3a5f10466b195927e4403065ea262daa2007b9c70e975454c80"
    static let testRelay = "wss://relay.damus.io"
    
    static var validNpub: String {
        do {
            let data = try Data(fromHex: testPubkey)
            return try Bech32.encode(hrp: "npub", data: Array(data))
        } catch {
            return "npub1deadbeef"
        }
    }
    
    static var validNpub2: String {
        do {
            let data = try Data(fromHex: testPubkey2)
            return try Bech32.encode(hrp: "npub", data: Array(data))
        } catch {
            return "npub1deadbeef2"
        }
    }
    
    static var validNote: String {
        do {
            let data = try Data(fromHex: testEventId)
            return try Bech32.encode(hrp: "note", data: Array(data))
        } catch {
            return "note1deadbeef"
        }
    }
    
    static var validNevent: String {
        do {
            // Construct TLV data for nevent
            var tlvData: [UInt8] = []
            
            // Type 0: event id (32 bytes)
            tlvData.append(0) // type
            tlvData.append(32) // length
            tlvData.append(contentsOf: try Data(fromHex: testEventId))
            
            // Type 1: relay url
            let relayData = testRelay.data(using: .utf8)!
            tlvData.append(1) // type
            tlvData.append(UInt8(relayData.count)) // length
            tlvData.append(contentsOf: relayData)
            
            // Type 2: author pubkey (32 bytes)
            tlvData.append(2) // type
            tlvData.append(32) // length
            tlvData.append(contentsOf: try Data(fromHex: testPubkey))
            
            return try Bech32.encode(hrp: "nevent", data: tlvData)
        } catch {
            return "nevent1deadbeef"
        }
    }
    
    static var validNprofile: String {
        do {
            // Construct TLV data for nprofile
            var tlvData: [UInt8] = []
            
            // Type 2: pubkey (32 bytes)
            tlvData.append(2) // type
            tlvData.append(32) // length
            tlvData.append(contentsOf: try Data(fromHex: testPubkey))
            
            // Type 1: relay url
            let relayData = testRelay.data(using: .utf8)!
            tlvData.append(1) // type
            tlvData.append(UInt8(relayData.count)) // length
            tlvData.append(contentsOf: relayData)
            
            return try Bech32.encode(hrp: "nprofile", data: tlvData)
        } catch {
            return "nprofile1deadbeef"
        }
    }
    
    static var validNaddr: String {
        do {
            // Construct TLV data for naddr
            var tlvData: [UInt8] = []
            
            // Type 0: identifier
            let identifier = "test-article"
            let identifierData = identifier.data(using: .utf8)!
            tlvData.append(0) // type
            tlvData.append(UInt8(identifierData.count)) // length
            tlvData.append(contentsOf: identifierData)
            
            // Type 2: pubkey (32 bytes)
            tlvData.append(2) // type
            tlvData.append(32) // length
            tlvData.append(contentsOf: try Data(fromHex: testPubkey))
            
            // Type 3: kind (4 bytes, big-endian)
            let kind: UInt32 = 30023 // long-form content
            tlvData.append(3) // type
            tlvData.append(4) // length
            tlvData.append(UInt8((kind >> 24) & 0xFF))
            tlvData.append(UInt8((kind >> 16) & 0xFF))
            tlvData.append(UInt8((kind >> 8) & 0xFF))
            tlvData.append(UInt8(kind & 0xFF))
            
            // Type 1: relay url
            let relayData = testRelay.data(using: .utf8)!
            tlvData.append(1) // type
            tlvData.append(UInt8(relayData.count)) // length
            tlvData.append(contentsOf: relayData)
            
            return try Bech32.encode(hrp: "naddr", data: tlvData)
        } catch {
            return "naddr1deadbeef"
        }
    }
}

// Extension to convert hex string to Data
extension Data {
    init(fromHex hex: String) throws {
        var hex = hex
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }
        
        var data = Data()
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            
            guard let byte = UInt8(byteString, radix: 16) else {
                throw NDKError.invalidInput(message: "Invalid hex string")
            }
            
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}