import XCTest
@testable import NDKSwiftCore

final class RelayIntelligenceProtocolTests: XCTestCase {
    // MARK: - Protocol Conformance Tests

    func test_defaultRelayIntelligence_conformsToProtocol() async {
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk)

        // Verify it conforms to RelayIntelligence protocol
        let _: any RelayIntelligence = intelligence
    }

    // MARK: - Relay Selection for Publishing Tests

    func test_relaysForPublishing_returnsExplicitRelaysForOwnEvents() async {
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk)

        // Add explicit relays
        _ = await ndk.pool.addRelay("wss://relay1.example.com", origin: .explicit)
        _ = await ndk.pool.addRelay("wss://relay2.example.com", origin: .explicit)

        // Create event (no author set means it's "own" event)
        let event = EventTestFactory.createEvent(kind: 1, content: "Test")

        let relays = await intelligence.relaysForPublishing(event: event)

        XCTAssertEqual(relays.count, 2)
    }

    func test_relaysForPublishing_usesHintIndexForTargetedReplies() async {
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk)

        // Record hints for target author
        let targetPubkey = "abc123"
        await ndk.hintIndex.recordHint(pubkey: targetPubkey, relay: "wss://target-relay.example.com", source: .eventObserved)

        // Create a reply targeting that author
        let event = EventTestFactory.createEvent(kind: 1, content: "Reply", tags: [["p", targetPubkey]])

        let relays = await intelligence.relaysForPublishing(event: event)

        XCTAssertTrue(relays.contains("wss://target-relay.example.com/"))
    }

    // MARK: - Relay Selection for Fetching Tests

    func test_relaysForFetching_usesHintIndexForKnownPubkey() async {
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk)

        let pubkey = "known-author"
        await ndk.hintIndex.recordHint(pubkey: pubkey, relay: "wss://author-relay.example.com", source: .eventObserved)

        let filter = NDKFilter(authors: [pubkey])
        let relays = await intelligence.relaysForFetching(filter: filter)

        XCTAssertTrue(relays.contains("wss://author-relay.example.com/"))
    }

    func test_relaysForFetching_usesHintIndexForKnownEventId() async {
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk)

        let eventId = "event123"
        await ndk.hintIndex.recordHint(eventId: eventId, relay: "wss://event-relay.example.com", source: .eventObserved)

        let filter = NDKFilter(ids: [eventId])
        let relays = await intelligence.relaysForFetching(filter: filter)

        XCTAssertTrue(relays.contains("wss://event-relay.example.com/"))
    }

    func test_relaysForFetching_fallsBackToExplicitRelays() async {
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk)

        // Add explicit relays
        _ = await ndk.pool.addRelay("wss://explicit1.example.com", origin: .explicit)
        _ = await ndk.pool.addRelay("wss://explicit2.example.com", origin: .explicit)

        // Filter for unknown author (no hints available)
        let filter = NDKFilter(authors: ["unknown-author"])
        let relays = await intelligence.relaysForFetching(filter: filter)

        // Should include explicit relays as fallback
        XCTAssertTrue(relays.contains("wss://explicit1.example.com/"))
        XCTAssertTrue(relays.contains("wss://explicit2.example.com/"))
    }

    // MARK: - Relay Selection for Subscribing Tests

    func test_relaysForSubscribing_combinesHintsAndExplicitRelays() async {
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk)

        let pubkey = "subscribed-author"
        await ndk.hintIndex.recordHint(pubkey: pubkey, relay: "wss://hint-relay.example.com", source: .eventObserved)
        _ = await ndk.pool.addRelay("wss://explicit.example.com", origin: .explicit)

        let filter = NDKFilter(authors: [pubkey])
        let relays = await intelligence.relaysForSubscribing(filters: [filter])

        // Should include both hint relay and explicit relay
        XCTAssertTrue(relays.contains("wss://hint-relay.example.com/"))
        XCTAssertTrue(relays.contains("wss://explicit.example.com/"))
    }

    func test_relaysForSubscribing_deduplicatesRelays() async {
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk)

        let pubkey = "author"
        // Add same relay as both hint and explicit
        await ndk.hintIndex.recordHint(pubkey: pubkey, relay: "wss://same-relay.example.com", source: .eventObserved)
        _ = await ndk.pool.addRelay("wss://same-relay.example.com", origin: .explicit)

        let filter = NDKFilter(authors: [pubkey])
        let relays = await intelligence.relaysForSubscribing(filters: [filter])

        // Should not have duplicates (Set naturally deduplicates)
        let relayArray = Array(relays)
        let uniqueCount = Set(relayArray).count
        XCTAssertEqual(relayArray.count, uniqueCount)
    }
}
