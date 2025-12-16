import XCTest
@testable import NDKSwiftCore

final class RelayIntelligenceEventEmissionTests: XCTestCase {
    // MARK: - Event Emission Tests

    func test_relaysForPublishing_emitsRelaySelectedEvent() async {
        let ndk = NDK()
        let eventStream = IntelligenceEventStream()
        let intelligence = DefaultRelayIntelligence(ndk: ndk, eventStream: eventStream)

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://relay.example.com", origin: .explicit)

        // Start collecting events
        let eventsTask = Task {
            var events: [IntelligenceEvent] = []
            for await event in eventStream.events {
                events.append(event)
                if events.count >= 1 { break }
            }
            return events
        }

        // Wait for subscription
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Trigger relay selection
        let event = EventTestFactory.createEvent(kind: 1, content: "Test")
        _ = await intelligence.relaysForPublishing(event: event)

        // Wait for event
        let collectedEvents = await eventsTask.value

        // Verify event was emitted
        XCTAssertEqual(collectedEvents.count, 1)
        if case .relaySelected(let operation, _, _) = collectedEvents.first {
            XCTAssertEqual(operation, .publish)
        } else {
            XCTFail("Expected relaySelected event for publish")
        }
    }

    func test_relaysForFetching_emitsRelaySelectedEvent() async {
        let ndk = NDK()
        let eventStream = IntelligenceEventStream()
        let intelligence = DefaultRelayIntelligence(ndk: ndk, eventStream: eventStream)

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://relay.example.com", origin: .explicit)

        // Start collecting events
        let eventsTask = Task {
            var events: [IntelligenceEvent] = []
            for await event in eventStream.events {
                events.append(event)
                if events.count >= 1 { break }
            }
            return events
        }

        // Wait for subscription
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Trigger relay selection
        let filter = NDKFilter(authors: ["test-pubkey"])
        _ = await intelligence.relaysForFetching(filter: filter)

        // Wait for event
        let collectedEvents = await eventsTask.value

        XCTAssertEqual(collectedEvents.count, 1)
        if case .relaySelected(let operation, _, _) = collectedEvents.first {
            XCTAssertEqual(operation, .fetch)
        } else {
            XCTFail("Expected relaySelected event for fetch")
        }
    }

    func test_relaysForSubscribing_emitsRelaySelectedEvent() async {
        let ndk = NDK()
        let eventStream = IntelligenceEventStream()
        let intelligence = DefaultRelayIntelligence(ndk: ndk, eventStream: eventStream)

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://relay.example.com", origin: .explicit)

        // Start collecting events
        let eventsTask = Task {
            var events: [IntelligenceEvent] = []
            for await event in eventStream.events {
                events.append(event)
                if events.count >= 1 { break }
            }
            return events
        }

        // Wait for subscription
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Trigger relay selection
        let filter = NDKFilter(authors: ["test-pubkey"])
        _ = await intelligence.relaysForSubscribing(filters: [filter])

        // Wait for event
        let collectedEvents = await eventsTask.value

        XCTAssertEqual(collectedEvents.count, 1)
        if case .relaySelected(let operation, _, _) = collectedEvents.first {
            XCTAssertEqual(operation, .subscribe)
        } else {
            XCTFail("Expected relaySelected event for subscribe")
        }
    }

    func test_intelligence_worksWithoutEventStream() async {
        // Verify intelligence still works when no event stream is provided
        let ndk = NDK()
        let intelligence = DefaultRelayIntelligence(ndk: ndk) // No event stream

        // Add explicit relay
        _ = await ndk.pool.addRelay("wss://relay.example.com", origin: .explicit)

        // This should not crash
        let event = EventTestFactory.createEvent(kind: 1, content: "Test")
        let relays = await intelligence.relaysForPublishing(event: event)

        XCTAssertFalse(relays.isEmpty)
    }
}
