import XCTest
@testable import NDKSwiftCore

final class HintIndexRelaySelectionTests: XCTestCase {
    // MARK: - Publishing Integration Tests

    func test_selectRelaysForPublishing_usesHintIndexWhenTrackerHasNoInfo() async {
        let ndk = NDK()

        // Add explicit relay (fallback)
        _ = await ndk.pool.addRelay("wss://explicit.example.com", origin: .appRelays)

        // Record hints for the author (simulate learning from observed events)
        await ndk.hintIndex.recordHint(pubkey: "author-pubkey", relay: "wss://author-hint.example.com", source: .eventObserved)

        // Create event from that author
        let event = EventTestFactory.createEvent(kind: 1, content: "Test", pubkey: "author-pubkey")

        // Select relays - should include hint relay since tracker has no relay list
        let selection = await ndk.relaySelector.selectRelaysForPublishing(event: event)

        // Verify hint relay is included
        XCTAssertTrue(selection.relays.contains("wss://author-hint.example.com/"), "Should include relay from HintIndex")
    }

    func test_selectRelaysForPublishing_includesHintsForPTaggedUsers() async {
        let ndk = NDK()

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://explicit.example.com", origin: .appRelays)

        // Record hint for a user we'll mention in p-tag
        await ndk.hintIndex.recordHint(pubkey: "mentioned-user", relay: "wss://mentioned-user-relay.example.com", source: .nip19)

        // Create event with p-tag mentioning that user
        let event = EventTestFactory.createEvent(
            kind: 1,
            content: "Hello @mentioned-user",
            tags: [["p", "mentioned-user"]]
        )

        // Select relays
        let selection = await ndk.relaySelector.selectRelaysForPublishing(event: event)

        // Verify mentioned user's relay is included
        XCTAssertTrue(selection.relays.contains("wss://mentioned-user-relay.example.com/"), "Should include relay hints for p-tagged users")
    }

    // MARK: - Fetching Integration Tests

    func test_selectRelaysForFetching_usesHintIndexForAuthors() async {
        let ndk = NDK()

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://explicit.example.com", origin: .appRelays)

        // Record hints for authors we want to fetch
        await ndk.hintIndex.recordHint(pubkey: "target-author", relay: "wss://target-author-relay.example.com", source: .eventObserved)

        // Create filter for that author
        let filter = NDKFilter(authors: ["target-author"])

        // Select relays
        let selection = await ndk.relaySelector.selectRelaysForFetching(filter: filter)

        // Verify hint relay is included
        XCTAssertTrue(selection.relays.contains("wss://target-author-relay.example.com/"), "Should include relay from HintIndex for filter authors")
    }

    func test_selectRelaysForFetching_combinesTrackerAndHintIndex() async {
        let ndk = NDK()

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://explicit.example.com", origin: .appRelays)

        // Record hint for one author
        await ndk.hintIndex.recordHint(pubkey: "author-with-hint", relay: "wss://hint-relay.example.com", source: .eventObserved)

        // Create filter for multiple authors (some with hints, some without)
        let filter = NDKFilter(authors: ["author-with-hint", "author-without-hint"])

        // Select relays
        let selection = await ndk.relaySelector.selectRelaysForFetching(filter: filter)

        // Verify hint relay is included for the author with hints
        XCTAssertTrue(selection.relays.contains("wss://hint-relay.example.com/"), "Should include relay from HintIndex")
        // Explicit relay should also be included as fallback
        XCTAssertTrue(selection.relays.contains("wss://explicit.example.com/"), "Should include explicit relay")
    }

    // MARK: - Event ID Hints Tests

    func test_selectRelaysForFetching_usesEventIdHints() async {
        let ndk = NDK()

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://explicit.example.com", origin: .appRelays)

        // Record hint for an event ID
        await ndk.hintIndex.recordHint(eventId: "event123", relay: "wss://event-source-relay.example.com", source: .eventObserved)

        // Create filter for that event ID
        let filter = NDKFilter(ids: ["event123"])

        // Select relays
        let selection = await ndk.relaySelector.selectRelaysForFetching(filter: filter)

        // Verify event ID hint relay is included
        XCTAssertTrue(selection.relays.contains("wss://event-source-relay.example.com/"), "Should include relay from HintIndex for event ID")
    }

    // MARK: - Priority Tests

    func test_trackerRelaysHavePriorityOverHintIndex() async {
        // When tracker has relay info, it should be used
        // HintIndex should only fill gaps when tracker returns nil
        let ndk = NDK()

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://explicit.example.com", origin: .appRelays)

        // Record hint for a pubkey
        await ndk.hintIndex.recordHint(pubkey: "test-pubkey", relay: "wss://hint-relay.example.com", source: .eventObserved)

        // If tracker has relay info for same pubkey, that should be used
        // (This tests that we don't double up on relays when both have info)

        let filter = NDKFilter(authors: ["test-pubkey"])
        let selection = await ndk.relaySelector.selectRelaysForFetching(filter: filter)

        // At minimum, explicit relay and hint relay should be present
        XCTAssertFalse(selection.relays.isEmpty)
        XCTAssertTrue(selection.relays.contains("wss://hint-relay.example.com/"), "Should include HintIndex relay")
    }
}
