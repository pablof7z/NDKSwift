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

    // MARK: - Eviction

    func test_eviction_removesSingleEntryKeys() async {
        // Create a small HintIndex to test eviction
        let smallIndex = HintIndex(maxSize: 5)

        // Add 5 entries (at max size)
        for i in 0 ..< 5 {
            await smallIndex.recordHint(pubkey: "pub\(i)", relay: "wss://relay\(i).com", source: .nip19)
        }

        // Verify we have 5 entries
        var count = await smallIndex.count
        XCTAssertEqual(count, 5)

        // Add one more - should trigger eviction
        await smallIndex.recordHint(pubkey: "pub-new", relay: "wss://new-relay.com", source: .nip19)

        // Verify eviction happened (should be under or at 90% of maxSize = ~4-5)
        count = await smallIndex.count
        XCTAssertLessThanOrEqual(count, 5, "Should have evicted entries to stay under maxSize")

        // The newest entry should still be there
        let newHints = await smallIndex.hints(for: "pub-new")
        XCTAssertEqual(newHints.count, 1, "Newest entry should survive eviction")
    }

    func test_eviction_usesLRU() async {
        // Create a small HintIndex to test LRU eviction
        let smallIndex = HintIndex(maxSize: 3)

        // Add entries with a small delay to ensure different timestamps
        await smallIndex.recordHint(pubkey: "oldest", relay: "wss://oldest.com", source: .nip19)
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        await smallIndex.recordHint(pubkey: "middle", relay: "wss://middle.com", source: .nip19)
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        await smallIndex.recordHint(pubkey: "newest", relay: "wss://newest.com", source: .nip19)

        // All 3 should be present
        var count = await smallIndex.count
        XCTAssertEqual(count, 3)

        // Add one more - should trigger LRU eviction of oldest
        await smallIndex.recordHint(pubkey: "very-newest", relay: "wss://very-newest.com", source: .nip19)

        // Oldest should be evicted (LRU)
        let oldestHints = await smallIndex.hints(for: "oldest")
        XCTAssertTrue(oldestHints.isEmpty, "Oldest entry should be evicted (LRU)")

        // Newest entries should still be there
        let newestHints = await smallIndex.hints(for: "very-newest")
        XCTAssertEqual(newestHints.count, 1, "Very newest entry should survive")
    }

    // MARK: - Address Helper

    func test_relayURLs_forAddress_returnsUniqueRelays() async {
        let address = "30023:abc123:my-article"

        await hintIndex.recordHint(address: address, relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(address: address, relay: "wss://relay1.com", source: .eventObserved)
        await hintIndex.recordHint(address: address, relay: "wss://relay2.com", source: .nip19)

        let relays = await hintIndex.relayURLs(forAddress: address)
        XCTAssertEqual(relays.count, 2)
        XCTAssertTrue(relays.contains("wss://relay1.com/"))
        XCTAssertTrue(relays.contains("wss://relay2.com/"))
    }
}
