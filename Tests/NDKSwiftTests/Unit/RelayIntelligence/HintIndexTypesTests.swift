import XCTest
@testable import NDKSwiftCore

final class HintIndexTypesTests: XCTestCase {
    func test_hintSource_equatable() {
        XCTAssertEqual(HintSource.nip19, HintSource.nip19)
        XCTAssertNotEqual(HintSource.nip19, HintSource.eventObserved)
    }

    func test_hintEntry_creation() {
        let entry = HintEntry(
            relay: "wss://relay.example.com",
            source: .nip19,
            recordedAt: Date()
        )
        XCTAssertEqual(entry.relay, "wss://relay.example.com")
        XCTAssertEqual(entry.source, .nip19)
    }

    func test_hintSource_allCases() {
        // Verify all expected sources exist
        let nip19 = HintSource.nip19
        let eventObserved = HintSource.eventObserved
        let userRelayList = HintSource.userRelayList
        let explicit = HintSource.app

        // Each should be distinct
        XCTAssertNotEqual(nip19, eventObserved)
        XCTAssertNotEqual(eventObserved, userRelayList)
        XCTAssertNotEqual(userRelayList, explicit)
        XCTAssertNotEqual(nip19, explicit)
    }

    func test_hintEntry_defaultDate() {
        let before = Date()
        let entry = HintEntry(relay: "wss://relay.example.com", source: .nip19)
        let after = Date()

        XCTAssertGreaterThanOrEqual(entry.recordedAt, before)
        XCTAssertLessThanOrEqual(entry.recordedAt, after)
    }
}
