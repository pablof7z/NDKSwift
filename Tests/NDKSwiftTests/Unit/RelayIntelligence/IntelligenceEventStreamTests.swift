import XCTest
@testable import NDKSwiftCore

final class IntelligenceEventStreamTests: XCTestCase {
    // MARK: - Event Types Tests

    func test_intelligenceEvent_hintRecorded() {
        let event = IntelligenceEvent.hintRecorded(
            type: .pubkey,
            identifier: "test-pubkey",
            relay: "wss://relay.example.com",
            source: .eventObserved
        )

        if case .hintRecorded(let type, let identifier, let relay, let source) = event {
            XCTAssertEqual(type, .pubkey)
            XCTAssertEqual(identifier, "test-pubkey")
            XCTAssertEqual(relay, "wss://relay.example.com")
            XCTAssertEqual(source, .eventObserved)
        } else {
            XCTFail("Expected hintRecorded event")
        }
    }

    func test_intelligenceEvent_relaySelected() {
        let event = IntelligenceEvent.relaySelected(
            operation: .publish,
            relays: ["wss://r1.example.com/", "wss://r2.example.com/"],
            reason: "explicit relays"
        )

        if case .relaySelected(let operation, let relays, let reason) = event {
            XCTAssertEqual(operation, .publish)
            XCTAssertEqual(relays.count, 2)
            XCTAssertEqual(reason, "explicit relays")
        } else {
            XCTFail("Expected relaySelected event")
        }
    }

    func test_intelligenceEvent_relayEvicted() {
        let event = IntelligenceEvent.relayEvicted(
            relay: "wss://idle.example.com/",
            reason: "idle timeout"
        )

        if case .relayEvicted(let relay, let reason) = event {
            XCTAssertEqual(relay, "wss://idle.example.com/")
            XCTAssertEqual(reason, "idle timeout")
        } else {
            XCTFail("Expected relayEvicted event")
        }
    }

    // MARK: - Event Stream Tests

    func test_eventStream_receivesPublishedEvents() async {
        let stream = IntelligenceEventStream()

        // Start collecting events in a task
        let collectedEvents = Task {
            var events: [IntelligenceEvent] = []
            for await event in stream.events {
                events.append(event)
                if events.count >= 2 { break }
            }
            return events
        }

        // Wait a moment for subscription
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Emit some events
        await stream.emit(.hintRecorded(type: .pubkey, identifier: "p1", relay: "wss://r1.example.com", source: .nip19))
        await stream.emit(.relayEvicted(relay: "wss://idle.example.com/", reason: "idle"))

        // Wait for collection
        let events = await collectedEvents.value

        XCTAssertEqual(events.count, 2)
    }

    func test_eventStream_supportsMultipleSubscribers() async {
        let stream = IntelligenceEventStream()

        // Start two subscribers
        let subscriber1 = Task {
            var count = 0
            for await _ in stream.events {
                count += 1
                if count >= 2 { break }
            }
            return count
        }

        let subscriber2 = Task {
            var count = 0
            for await _ in stream.events {
                count += 1
                if count >= 2 { break }
            }
            return count
        }

        // Wait for subscriptions
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Emit events
        await stream.emit(.hintRecorded(type: .pubkey, identifier: "p1", relay: "wss://r1.example.com", source: .nip19))
        await stream.emit(.hintRecorded(type: .eventId, identifier: "e1", relay: "wss://r2.example.com", source: .eventObserved))

        let count1 = await subscriber1.value
        let count2 = await subscriber2.value

        XCTAssertEqual(count1, 2)
        XCTAssertEqual(count2, 2)
    }
}
