import XCTest
@testable import NDKSwiftCore

final class HintIndexIntrospectionTests: XCTestCase {
    // MARK: - All Hints Tests

    func test_allPubkeyHints_returnsAllStoredPubkeys() async {
        let index = HintIndex()

        await index.recordHint(pubkey: "pubkey1", relay: "wss://relay1.example.com", source: .eventObserved)
        await index.recordHint(pubkey: "pubkey2", relay: "wss://relay2.example.com", source: .nip19)
        await index.recordHint(pubkey: "pubkey1", relay: "wss://relay3.example.com", source: .app)

        let allPubkeys = await index.allPubkeyHints
        XCTAssertEqual(allPubkeys.count, 2) // Two unique pubkeys
        XCTAssertTrue(allPubkeys.keys.contains("pubkey1"))
        XCTAssertTrue(allPubkeys.keys.contains("pubkey2"))
    }

    func test_allEventIdHints_returnsAllStoredEventIds() async {
        let index = HintIndex()

        await index.recordHint(eventId: "event1", relay: "wss://relay1.example.com", source: .eventObserved)
        await index.recordHint(eventId: "event2", relay: "wss://relay2.example.com", source: .nip19)

        let allEventIds = await index.allEventIdHints
        XCTAssertEqual(allEventIds.count, 2)
        XCTAssertTrue(allEventIds.keys.contains("event1"))
        XCTAssertTrue(allEventIds.keys.contains("event2"))
    }

    func test_allAddressHints_returnsAllStoredAddresses() async {
        let index = HintIndex()

        await index.recordHint(address: "30023:pubkey:dtag1", relay: "wss://relay1.example.com", source: .nip19)
        await index.recordHint(address: "30023:pubkey:dtag2", relay: "wss://relay2.example.com", source: .nip19)

        let allAddresses = await index.allAddressHints
        XCTAssertEqual(allAddresses.count, 2)
        XCTAssertTrue(allAddresses.keys.contains("30023:pubkey:dtag1"))
        XCTAssertTrue(allAddresses.keys.contains("30023:pubkey:dtag2"))
    }

    // MARK: - Most Known Relays Tests

    func test_mostKnownRelays_returnsMostFrequentRelays() async {
        let index = HintIndex()

        // Record multiple hints for the same relay
        await index.recordHint(pubkey: "p1", relay: "wss://popular.example.com", source: .eventObserved)
        await index.recordHint(pubkey: "p2", relay: "wss://popular.example.com", source: .eventObserved)
        await index.recordHint(pubkey: "p3", relay: "wss://popular.example.com", source: .eventObserved)
        await index.recordHint(pubkey: "p4", relay: "wss://less-popular.example.com", source: .eventObserved)

        let mostKnown = await index.mostKnownRelays(limit: 2)

        XCTAssertEqual(mostKnown.count, 2)
        XCTAssertEqual(mostKnown.first?.relay, "wss://popular.example.com/")
        XCTAssertEqual(mostKnown.first?.mentionCount, 3)
    }

    func test_mostKnownRelays_respectsLimit() async {
        let index = HintIndex()

        for i in 1...10 {
            await index.recordHint(pubkey: "p\(i)", relay: "wss://relay\(i).example.com", source: .eventObserved)
        }

        let mostKnown = await index.mostKnownRelays(limit: 5)
        XCTAssertEqual(mostKnown.count, 5)
    }

    // MARK: - Statistics Tests

    func test_statistics_returnsAccurateStats() async {
        let index = HintIndex()

        await index.recordHint(pubkey: "p1", relay: "wss://r1.example.com", source: .eventObserved)
        await index.recordHint(pubkey: "p2", relay: "wss://r2.example.com", source: .nip19)
        await index.recordHint(eventId: "e1", relay: "wss://r1.example.com", source: .eventObserved)
        await index.recordHint(address: "a1", relay: "wss://r3.example.com", source: .nip19)

        let stats = await index.statistics

        XCTAssertEqual(stats.pubkeyCount, 2)
        XCTAssertEqual(stats.eventIdCount, 1)
        XCTAssertEqual(stats.addressCount, 1)
        XCTAssertEqual(stats.totalEntries, 4)
        XCTAssertEqual(stats.uniqueRelayCount, 3)
    }

    // MARK: - Source Breakdown Tests

    func test_sourceBreakdown_countsHintsBySource() async {
        let index = HintIndex()

        // Add hints with different sources
        await index.recordHint(pubkey: "p1", relay: "wss://r1.example.com", source: .eventObserved)
        await index.recordHint(pubkey: "p2", relay: "wss://r2.example.com", source: .eventObserved)
        await index.recordHint(pubkey: "p3", relay: "wss://r3.example.com", source: .nip19)
        await index.recordHint(pubkey: "p4", relay: "wss://r4.example.com", source: .app)

        let breakdown = await index.sourceBreakdown

        XCTAssertEqual(breakdown[.eventObserved], 2)
        XCTAssertEqual(breakdown[.nip19], 1)
        XCTAssertEqual(breakdown[.app], 1)
    }
}
