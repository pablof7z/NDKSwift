@testable import NDKSwiftCore
import XCTest

final class NdbFilterTests: XCTestCase {
    func testEmptyNativeElementListsAreRejectedBeforeEnteringNostrDB() throws {
        XCTAssertThrowsError(try NdbFilter(from: NostrFilter(ids: [])))
        XCTAssertThrowsError(try NdbFilter(from: NostrFilter(kinds: [])))
        XCTAssertThrowsError(try NdbFilter(from: NostrFilter(referenced_ids: [])))
        XCTAssertThrowsError(try NdbFilter(from: NostrFilter(pubkeys: [])))
        XCTAssertThrowsError(try NdbFilter(from: NostrFilter(authors: [])))
        XCTAssertThrowsError(try NdbFilter(from: NostrFilter(hashtag: [])))
        XCTAssertThrowsError(try NdbFilter(from: NostrFilter(parameter: [])))
        XCTAssertThrowsError(try NdbFilter(from: NostrFilter(quotes: [])))
    }
}
