import XCTest
@testable import NDKSwift

final class NDKFilterConvenienceTests: XCTestCase {
    
    func testProfileFilterConvenience() {
        let pubkey = "test_pubkey"
        let filter = NDKFilter.profile(for: pubkey)
        
        XCTAssertEqual(filter.kinds, [0])
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertEqual(filter.limit, 1)
    }
    
    func testProfileFilterWithCustomLimit() {
        let pubkey = "test_pubkey"
        let filter = NDKFilter.profile(for: pubkey, limit: 5)
        
        XCTAssertEqual(filter.kinds, [0])
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertEqual(filter.limit, 5)
    }
    
    func testTextNotesFilterConvenience() {
        let pubkey = "test_pubkey"
        let filter = NDKFilter.textNotes(by: pubkey)
        
        XCTAssertEqual(filter.kinds, [1])
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertNil(filter.limit)
        XCTAssertNil(filter.since)
        XCTAssertNil(filter.until)
    }
    
    func testTextNotesFilterWithTimeRange() {
        let pubkey = "test_pubkey"
        let since: Timestamp = 1000
        let until: Timestamp = 2000
        let filter = NDKFilter.textNotes(by: pubkey, limit: 20, since: since, until: until)
        
        XCTAssertEqual(filter.kinds, [1])
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertEqual(filter.limit, 20)
        XCTAssertEqual(filter.since, since)
        XCTAssertEqual(filter.until, until)
    }
    
    func testContactListFilterConvenience() {
        let pubkey = "test_pubkey"
        let filter = NDKFilter.contactList(for: pubkey)
        
        XCTAssertEqual(filter.kinds, [3])
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertEqual(filter.limit, 1)
    }
    
    func testReactionsFilterConvenience() {
        let eventId = "test_event_id"
        let filter = NDKFilter.reactions(to: eventId)
        
        XCTAssertEqual(filter.kinds, [7])
        XCTAssertEqual(filter.events, [eventId])
        XCTAssertNil(filter.limit)
    }
    
    func testReactionsFilterWithLimit() {
        let eventId = "test_event_id"
        let filter = NDKFilter.reactions(to: eventId, limit: 50)
        
        XCTAssertEqual(filter.kinds, [7])
        XCTAssertEqual(filter.events, [eventId])
        XCTAssertEqual(filter.limit, 50)
    }
    
    func testDeletionsFilterConvenience() {
        let pubkey = "test_pubkey"
        let filter = NDKFilter.deletions(by: pubkey)
        
        XCTAssertEqual(filter.kinds, [5])
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertNil(filter.limit)
    }
    
    func testRelayListFilterConvenience() {
        let pubkey = "test_pubkey"
        let filter = NDKFilter.relayList(for: pubkey)
        
        XCTAssertEqual(filter.kinds, [10002])
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertNil(filter.limit)
    }
    
    func testMultipleKindsFilterConvenience() {
        let pubkey = "test_pubkey"
        let kinds: [Kind] = [1, 6, 7]
        let filter = NDKFilter.multipleKinds(kinds, by: pubkey)
        
        XCTAssertEqual(filter.kinds, kinds)
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertNil(filter.limit)
    }
    
    func testMultipleKindsFilterWithLimit() {
        let pubkey = "test_pubkey"
        let kinds: [Kind] = [1, 6]
        let filter = NDKFilter.multipleKinds(kinds, by: pubkey, limit: 100)
        
        XCTAssertEqual(filter.kinds, kinds)
        XCTAssertEqual(filter.authors, [pubkey])
        XCTAssertEqual(filter.limit, 100)
    }
}