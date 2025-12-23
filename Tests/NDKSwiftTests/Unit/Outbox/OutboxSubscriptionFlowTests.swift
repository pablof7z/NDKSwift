@testable import NDKSwiftCore
import XCTest

/// Tests for outbox subscription flow - strategy level
/// Verifies getOutboxStrategy() produces correct relay-author mappings
final class OutboxSubscriptionFlowTests: XCTestCase {
    var ndk: NDK!
    var cache: MemoryCache!

    // Test relay URLs
    let relay1URL: RelayURL = "wss://relay1.test/"
    let relay2URL: RelayURL = "wss://relay2.test/"
    let relay3URL: RelayURL = "wss://relay3.test/"
    let relay4URL: RelayURL = "wss://relay4.test/"
    let outboxRelayURL: RelayURL = "wss://outbox.test/"
    let fallbackRelayURL: RelayURL = "wss://fallback.test/"

    // Test pubkeys (64 hex chars)
    let pubkey1 = "1111111111111111111111111111111111111111111111111111111111111111"
    let pubkey2 = "2222222222222222222222222222222222222222222222222222222222222222"
    let pubkey3 = "3333333333333333333333333333333333333333333333333333333333333333"

    override func setUp() async throws {
        cache = MemoryCache()
        let outboxConfig = NDKOutboxConfig(
            blacklistedRelays: [],
            outboxRelays: [outboxRelayURL]
        )
        ndk = NDK(
            relayURLs: [fallbackRelayURL],
            cache: cache,
            outboxConfig: outboxConfig
        )
    }

    override func tearDown() async throws {
        await ndk?.disconnect()
        ndk = nil
        cache = nil
    }

    // MARK: - Test 1: Unknown authors identified correctly

    func testUnknownAuthorsIdentifiedInStrategy() async throws {
        // Given: A filter with 3 pubkeys, none with cached 10002
        let filter = NDKFilter(authors: [pubkey1, pubkey2, pubkey3], kinds: [1])

        // When: We get the outbox strategy
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)

        // Then: All authors should be marked as unknown
        XCTAssertEqual(strategy.unknownAuthors, Set([pubkey1, pubkey2, pubkey3]),
                       "All authors should be unknown when no 10002 cached")
        XCTAssertTrue(strategy.filtersByRelay.isEmpty,
                      "No relay-specific filters should exist for unknown authors")
        XCTAssertEqual(strategy.authorsToDiscover, Set([pubkey1, pubkey2, pubkey3]),
                       "All unknown authors should be marked for discovery")
    }

    // MARK: - Test 2: Pre-cached 10002 produces correct filtersByRelay

    func testPreCachedRelayListProducesCorrectFilters() async throws {
        // Given: Pre-cached relay lists with overlapping relays
        // pubkey1 → relay1, relay2, relay3
        // pubkey2 → relay1, relay4
        // pubkey3 → relay2, relay4
        await ndk.outbox.track(
            pubkey: pubkey1,
            readRelays: [relay1URL, relay2URL, relay3URL],
            writeRelays: [],
            source: .nip65
        )
        await ndk.outbox.track(
            pubkey: pubkey2,
            readRelays: [relay1URL, relay4URL],
            writeRelays: [],
            source: .nip65
        )
        await ndk.outbox.track(
            pubkey: pubkey3,
            readRelays: [relay2URL, relay4URL],
            writeRelays: [],
            source: .nip65
        )

        // When: We get the outbox strategy
        let filter = NDKFilter(authors: [pubkey1, pubkey2, pubkey3], kinds: [1])
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)

        // Then: All authors should be known
        XCTAssertTrue(strategy.unknownAuthors.isEmpty,
                      "All authors should be known after tracking")
        XCTAssertTrue(strategy.authorsToDiscover.isEmpty,
                      "No authors should need discovery")

        // Verify relay-specific author assignments
        // relay1 should have pubkey1, pubkey2
        XCTAssertEqual(
            Set(strategy.filtersByRelay[relay1URL]?.authors ?? []),
            Set([pubkey1, pubkey2]),
            "relay1 should serve pubkey1 and pubkey2"
        )

        // relay2 should have pubkey1, pubkey3
        XCTAssertEqual(
            Set(strategy.filtersByRelay[relay2URL]?.authors ?? []),
            Set([pubkey1, pubkey3]),
            "relay2 should serve pubkey1 and pubkey3"
        )

        // relay3 should have only pubkey1
        XCTAssertEqual(
            Set(strategy.filtersByRelay[relay3URL]?.authors ?? []),
            Set([pubkey1]),
            "relay3 should serve only pubkey1"
        )

        // relay4 should have pubkey2, pubkey3
        XCTAssertEqual(
            Set(strategy.filtersByRelay[relay4URL]?.authors ?? []),
            Set([pubkey2, pubkey3]),
            "relay4 should serve pubkey2 and pubkey3"
        )
    }

    // MARK: - Test 3: Partial cache produces mixed strategy

    func testPartialCacheProducesMixedStrategy() async throws {
        // Given: Only pubkey1 has cached relay list
        await ndk.outbox.track(
            pubkey: pubkey1,
            readRelays: [relay1URL, relay2URL],
            writeRelays: [],
            source: .nip65
        )
        // pubkey2 and pubkey3 have NO cached relay lists

        // When: We get the outbox strategy
        let filter = NDKFilter(authors: [pubkey1, pubkey2, pubkey3], kinds: [1])
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)

        // Then: pubkey1 should have relay-specific filters
        XCTAssertTrue(
            strategy.filtersByRelay[relay1URL]?.authors?.contains(pubkey1) ?? false,
            "relay1 should serve pubkey1"
        )
        XCTAssertTrue(
            strategy.filtersByRelay[relay2URL]?.authors?.contains(pubkey1) ?? false,
            "relay2 should serve pubkey1"
        )

        // pubkey2 and pubkey3 should be unknown
        XCTAssertEqual(
            strategy.unknownAuthors,
            Set([pubkey2, pubkey3]),
            "pubkey2 and pubkey3 should be unknown"
        )

        // pubkey1 should NOT be in filtersByRelay for any other relay
        for (relay, filter) in strategy.filtersByRelay {
            if relay != relay1URL && relay != relay2URL {
                XCTAssertFalse(
                    filter.authors?.contains(pubkey1) ?? false,
                    "pubkey1 should only be in relay1 and relay2"
                )
            }
        }
    }

    // MARK: - Test 4: Fallback to write relays when no read relays

    func testFallbackToWriteRelaysWhenNoReadRelays() async throws {
        // Given: pubkey1 has only write relays, no read relays
        await ndk.outbox.track(
            pubkey: pubkey1,
            readRelays: [],
            writeRelays: [relay1URL, relay2URL],
            source: .nip65
        )

        // When: We get the outbox strategy
        let filter = NDKFilter(authors: [pubkey1], kinds: [1])
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)

        // Then: Should fallback to write relays
        XCTAssertTrue(strategy.unknownAuthors.isEmpty,
                      "Author should be known even with only write relays")

        // Check that write relays are used as fallback
        let hasRelay1 = strategy.filtersByRelay[relay1URL]?.authors?.contains(pubkey1) ?? false
        let hasRelay2 = strategy.filtersByRelay[relay2URL]?.authors?.contains(pubkey1) ?? false

        XCTAssertTrue(hasRelay1 || hasRelay2,
                      "Should fallback to at least one write relay")
    }

    // MARK: - Test 5: Filter without authors returns empty strategy

    func testFilterWithoutAuthorsReturnsEmptyStrategy() async throws {
        // Given: A filter without authors
        let filter = NDKFilter(kinds: [1])

        // When: We get the outbox strategy
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)

        // Then: Strategy should be empty
        XCTAssertTrue(strategy.filtersByRelay.isEmpty,
                      "No relay-specific filters for filter without authors")
        XCTAssertTrue(strategy.unknownAuthors.isEmpty,
                      "No unknown authors for filter without authors")
        XCTAssertTrue(strategy.authorsToDiscover.isEmpty,
                      "No authors to discover for filter without authors")
    }

    // MARK: - Test 6: Insecure relays filtered out

    func testInsecureRelaysFilteredOut() async throws {
        // Given: A relay list with insecure (ws://) relays
        await ndk.outbox.track(
            pubkey: pubkey1,
            readRelays: [
                "wss://secure.relay.test/",
                "ws://insecure.relay.test/",
                "wss://another-secure.relay.test/",
            ],
            writeRelays: [],
            source: .nip65
        )

        // When: We get the outbox strategy
        let filter = NDKFilter(authors: [pubkey1], kinds: [1])
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)

        // Then: Only secure relays should be included
        for (relay, _) in strategy.filtersByRelay {
            XCTAssertTrue(relay.hasPrefix("wss://"),
                          "Only secure (wss://) relays should be included: \(relay)")
            XCTAssertFalse(relay.hasPrefix("ws://"),
                           "Insecure (ws://) relays should be filtered out: \(relay)")
        }
    }

    // MARK: - Test 7: Localhost relays filtered out

    func testLocalhostRelaysFilteredOut() async throws {
        // Given: A relay list with localhost relays
        await ndk.outbox.track(
            pubkey: pubkey1,
            readRelays: [
                "wss://relay.example.com/",
                "wss://localhost:8080/",
                "wss://127.0.0.1:8080/",
            ],
            writeRelays: [],
            source: .nip65
        )

        // When: We get the outbox strategy
        let filter = NDKFilter(authors: [pubkey1], kinds: [1])
        let strategy = await ndk.outbox.getOutboxStrategy(for: filter)

        // Then: Localhost relays should be filtered out
        for (relay, _) in strategy.filtersByRelay {
            XCTAssertFalse(relay.contains("localhost"),
                           "Localhost relays should be filtered out: \(relay)")
            XCTAssertFalse(relay.contains("127.0.0.1"),
                           "127.0.0.1 relays should be filtered out: \(relay)")
        }
    }

    // MARK: - Test 8: Repeated lookups are throttled

    func testRepeatedLookupsAreThrottled() async throws {
        // Given: A filter with unknown authors
        let filter = NDKFilter(authors: [pubkey1, pubkey2], kinds: [1])

        // When: We get the strategy twice
        let strategy1 = await ndk.outbox.getOutboxStrategy(for: filter)
        let strategy2 = await ndk.outbox.getOutboxStrategy(for: filter)

        // Then: First call should mark authors for discovery
        XCTAssertEqual(strategy1.authorsToDiscover, Set([pubkey1, pubkey2]),
                       "First call should mark authors for discovery")

        // Second call should NOT mark them again (throttled)
        XCTAssertTrue(strategy2.authorsToDiscover.isEmpty,
                      "Second call should be throttled - no authors to discover")

        // But they should still be in unknownAuthors
        XCTAssertEqual(strategy2.unknownAuthors, Set([pubkey1, pubkey2]),
                       "Authors should still be marked as unknown")
    }
}
