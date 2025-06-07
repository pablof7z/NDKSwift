import XCTest
@testable import NDKSwift

final class NostrIdentifierTests: XCTestCase {
    
    // MARK: - Hex Event ID Tests
    
    func testCreateFilterFromHexEventId() throws {
        let hexId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
        
        let filter = try NostrIdentifier.createFilter(from: hexId)
        
        XCTAssertEqual(filter.ids?.count, 1)
        XCTAssertEqual(filter.ids?.first, hexId)
        XCTAssertNil(filter.authors)
        XCTAssertNil(filter.kinds)
        XCTAssertNil(filter.tags)
    }
    
    func testCreateFilterFromInvalidHexEventId() {
        // Too short
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: "5c83da77")) { error in
            guard case NDKError.invalidInput = error else {
                XCTFail("Expected invalidInput error")
                return
            }
        }
        
        // Too long
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f3600")) { error in
            guard case NDKError.invalidInput = error else {
                XCTFail("Expected invalidInput error")
                return
            }
        }
    }
    
    // MARK: - Note Bech32 Tests
    
    func testCreateFilterFromNoteBech32() throws {
        // Create a note bech32 string
        let eventId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
        let noteBech32 = try Bech32.note(from: eventId)
        
        let filter = try NostrIdentifier.createFilter(from: noteBech32)
        
        XCTAssertEqual(filter.ids?.count, 1)
        XCTAssertEqual(filter.ids?.first, eventId)
        XCTAssertNil(filter.authors)
        XCTAssertNil(filter.kinds)
        XCTAssertNil(filter.tags)
    }
    
    // MARK: - Nevent Bech32 Tests
    
    func testCreateFilterFromNeventBech32() throws {
        // Create a nevent bech32 string
        let eventId = "5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36"
        let author = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let neventBech32 = try Bech32.nevent(
            eventId: eventId,
            relays: ["wss://relay.damus.io"],
            author: author,
            kind: 1
        )
        
        let filter = try NostrIdentifier.createFilter(from: neventBech32)
        
        XCTAssertEqual(filter.ids?.count, 1)
        XCTAssertEqual(filter.ids?.first, eventId)
        // Note: Current implementation doesn't use author/kind from nevent
        XCTAssertNil(filter.authors)
        XCTAssertNil(filter.kinds)
        XCTAssertNil(filter.tags)
    }
    
    // MARK: - Naddr Bech32 Tests
    
    func testCreateFilterFromNaddrBech32() throws {
        // Create an naddr bech32 string
        let identifier = "1234"
        let kind = 30023
        let author = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let naddrBech32 = try Bech32.naddr(
            identifier: identifier,
            kind: kind,
            author: author,
            relays: ["wss://relay.damus.io"]
        )
        
        let filter = try NostrIdentifier.createFilter(from: naddrBech32)
        
        XCTAssertNil(filter.ids)
        XCTAssertEqual(filter.authors?.count, 1)
        XCTAssertEqual(filter.authors?.first, author)
        XCTAssertEqual(filter.kinds?.count, 1)
        XCTAssertEqual(filter.kinds?.first, kind)
        XCTAssertEqual(filter.tagFilter("d"), [identifier])
    }
    
    func testCreateFilterFromNaddrWithEmptyIdentifier() throws {
        // Create an naddr bech32 string with empty identifier
        let identifier = ""
        let kind = 30023
        let author = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let naddrBech32 = try Bech32.naddr(
            identifier: identifier,
            kind: kind,
            author: author
        )
        
        let filter = try NostrIdentifier.createFilter(from: naddrBech32)
        
        XCTAssertNil(filter.ids)
        XCTAssertEqual(filter.authors?.count, 1)
        XCTAssertEqual(filter.authors?.first, author)
        XCTAssertEqual(filter.kinds?.count, 1)
        XCTAssertEqual(filter.kinds?.first, kind)
        XCTAssertEqual(filter.tagFilter("d"), [""])
    }
    
    // MARK: - Invalid Bech32 Tests
    
    func testCreateFilterFromInvalidBech32() {
        // Invalid bech32 string
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: "invalid1bech32")) { error in
            // Should throw some error when trying to decode
            XCTAssertNotNil(error)
        }
    }
    
    func testCreateFilterFromUnsupportedBech32Type() throws {
        // Create an npub (which is not supported for event fetching)
        let pubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        let npubBech32 = try Bech32.npub(from: pubkey)
        
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: npubBech32)) { error in
            guard case NDKError.invalidInput(let message) = error else {
                XCTFail("Expected invalidInput error")
                return
            }
            XCTAssertTrue(message.contains("Unsupported bech32 type"))
        }
    }
    
    // MARK: - Edge Cases
    
    func testCreateFilterFromEmptyString() {
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: "")) { error in
            guard case NDKError.invalidInput = error else {
                XCTFail("Expected invalidInput error")
                return
            }
        }
    }
    
    func testCreateFilterFromWhitespace() {
        XCTAssertThrowsError(try NostrIdentifier.createFilter(from: "   ")) { error in
            guard case NDKError.invalidInput = error else {
                XCTFail("Expected invalidInput error")
                return
            }
        }
    }
}