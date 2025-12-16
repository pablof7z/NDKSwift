import XCTest
@testable import NDKSwiftCore

final class HintIndexTests: XCTestCase {
    var hintIndex: HintIndex!

    override func setUp() async throws {
        hintIndex = HintIndex(maxSize: 100)
    }

    // MARK: - Recording Hints

    func test_recordHint_forPubkey_storesHint() async {
        let pubkey = "abc123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .nip19)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.relay, relay.normalizedRelayURL)
        XCTAssertEqual(hints.first?.source, .nip19)
    }

    func test_recordHint_forEventId_storesHint() async {
        let eventId = "event123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(eventId: eventId, relay: relay, source: .eventObserved)

        let hints = await hintIndex.hints(forEventId: eventId)
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.relay, relay.normalizedRelayURL)
    }

    func test_recordHint_forAddress_storesHint() async {
        let address = "30023:abc123:my-article"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(address: address, relay: relay, source: .userRelayList)

        let hints = await hintIndex.hints(forAddress: address)
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.relay, relay.normalizedRelayURL)
    }

    // MARK: - Retrieving Hints

    func test_hints_returnsEmpty_whenNoHintsRecorded() async {
        let hints = await hintIndex.hints(for: "unknown")
        XCTAssertTrue(hints.isEmpty)
    }

    // MARK: - Deduplication

    func test_recordHint_deduplicates_sameRelaySource() async {
        let pubkey = "abc123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .nip19)
        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .nip19)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 1)
    }

    func test_recordHint_allowsDifferentSources_forSameRelay() async {
        let pubkey = "abc123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .nip19)
        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .eventObserved)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 2)
    }

    func test_recordHint_allowsDifferentRelays_forSamePubkey() async {
        let pubkey = "abc123"

        await hintIndex.recordHint(pubkey: pubkey, relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(pubkey: pubkey, relay: "wss://relay2.com", source: .nip19)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 2)
    }

    // MARK: - URL Normalization

    func test_recordHint_normalizesRelayURL() async {
        let pubkey = "abc123"

        // URLs with and without trailing slash should be normalized
        await hintIndex.recordHint(pubkey: pubkey, relay: "wss://relay.example.com/", source: .nip19)
        await hintIndex.recordHint(pubkey: pubkey, relay: "wss://relay.example.com", source: .nip19)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 1) // Should be deduplicated after normalization
    }

    // MARK: - Relay URL Set

    func test_relayURLs_returnsUniqueRelays() async {
        let pubkey = "abc123"

        await hintIndex.recordHint(pubkey: pubkey, relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(pubkey: pubkey, relay: "wss://relay1.com", source: .eventObserved)
        await hintIndex.recordHint(pubkey: pubkey, relay: "wss://relay2.com", source: .nip19)

        let relays = await hintIndex.relayURLs(for: pubkey)
        XCTAssertEqual(relays.count, 2)
    }

    // MARK: - Statistics

    func test_count_returnsCorrectTotal() async {
        await hintIndex.recordHint(pubkey: "pub1", relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(pubkey: "pub2", relay: "wss://relay2.com", source: .nip19)
        await hintIndex.recordHint(eventId: "event1", relay: "wss://relay3.com", source: .eventObserved)

        let count = await hintIndex.count
        XCTAssertEqual(count, 3)
    }

    func test_pubkeyCount_returnsCorrectCount() async {
        await hintIndex.recordHint(pubkey: "pub1", relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(pubkey: "pub2", relay: "wss://relay2.com", source: .nip19)

        let count = await hintIndex.pubkeyCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Clear

    func test_clear_removesAllHints() async {
        await hintIndex.recordHint(pubkey: "pub1", relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(eventId: "event1", relay: "wss://relay2.com", source: .eventObserved)

        await hintIndex.clear()

        let pubkeyHints = await hintIndex.hints(for: "pub1")
        let eventHints = await hintIndex.hints(forEventId: "event1")
        let count = await hintIndex.count

        XCTAssertTrue(pubkeyHints.isEmpty)
        XCTAssertTrue(eventHints.isEmpty)
        XCTAssertEqual(count, 0)
    }
}
