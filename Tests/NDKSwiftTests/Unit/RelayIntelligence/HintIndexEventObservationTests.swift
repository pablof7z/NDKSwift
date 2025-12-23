import XCTest
@testable import NDKSwiftCore

final class HintIndexEventObservationTests: XCTestCase {
    var hintIndex: HintIndex!

    override func setUp() async throws {
        hintIndex = HintIndex(maxSize: 100)
    }

    // MARK: - Event Observation Tests

    func test_recordEventObservation_storesPubkeyHint() async {
        let pubkey = "abc123pubkey"
        let relay = "wss://relay.example.com"

        await hintIndex.recordEventObservation(pubkey: pubkey, eventId: "event123", relay: relay)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.relay, relay.normalizedRelayURL)
        XCTAssertEqual(hints.first?.source, .eventObserved)
    }

    func test_recordEventObservation_storesEventIdHint() async {
        let eventId = "event123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordEventObservation(pubkey: "abc123", eventId: eventId, relay: relay)

        let hints = await hintIndex.hints(forEventId: eventId)
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.relay, relay.normalizedRelayURL)
        XCTAssertEqual(hints.first?.source, .eventObserved)
    }

    func test_recordEventObservation_storesBothHints() async {
        let pubkey = "abc123pubkey"
        let eventId = "event123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordEventObservation(pubkey: pubkey, eventId: eventId, relay: relay)

        let pubkeyHints = await hintIndex.hints(for: pubkey)
        let eventIdHints = await hintIndex.hints(forEventId: eventId)

        XCTAssertEqual(pubkeyHints.count, 1)
        XCTAssertEqual(eventIdHints.count, 1)
    }

    func test_recordEventObservation_multipleRelays() async {
        let pubkey = "abc123pubkey"
        let eventId = "event123"

        await hintIndex.recordEventObservation(pubkey: pubkey, eventId: eventId, relay: "wss://relay1.com")
        await hintIndex.recordEventObservation(pubkey: pubkey, eventId: eventId, relay: "wss://relay2.com")

        let pubkeyHints = await hintIndex.hints(for: pubkey)
        let eventIdHints = await hintIndex.hints(forEventId: eventId)

        XCTAssertEqual(pubkeyHints.count, 2)
        XCTAssertEqual(eventIdHints.count, 2)
    }
}
