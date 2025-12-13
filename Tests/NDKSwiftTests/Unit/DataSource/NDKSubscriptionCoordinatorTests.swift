import XCTest
@testable import NDKSwiftCore

final class NDKSubscriptionCoordinatorTests: XCTestCase {

    func testHandleEventWithNonNDKRelayDoesNotCrash() async throws {
        // Given: A coordinator with event handler
        let ndk = NDK()
        let filter = NDKFilter(kinds: [1])
        let coordinator = NDKSubscriptionCoordinator(
            id: "test-sub",
            filters: [filter],
            relays: nil,
            ndk: ndk
        )

        var receivedEvents: [(NDKEvent, String)] = []
        coordinator.setOnEvent { event, relay in
            receivedEvents.append((event, relay.url))
        }

        // When: Event from a mock relay (not NDKRelay)
        let mockRelay = MockRelayProtocol(url: "wss://test.relay")
        let event = NDKEvent(kind: 1, content: "test", tags: [], pubkey: "test-pubkey")

        await coordinator.handleEvent(event, from: mockRelay)

        // Then: Should handle gracefully without crash
        // With force cast, this would crash. After fix, it should skip the callback
        // but still process through eventContinuation
        XCTAssertEqual(receivedEvents.count, 0, "Mock relay should not trigger NDKRelay-specific callbacks")
    }

    func testHandleEOSEWithNonNDKRelayDoesNotCrash() async throws {
        // Given: A coordinator with EOSE handler
        let ndk = NDK()
        let filter = NDKFilter(kinds: [1])
        let coordinator = NDKSubscriptionCoordinator(
            id: "test-sub",
            filters: [filter],
            relays: nil,
            ndk: ndk
        )

        var eoseRelays: [String] = []
        coordinator.setOnEOSE { relay in
            eoseRelays.append(relay.url)
        }

        // When: EOSE from a mock relay
        let mockRelay = MockRelayProtocol(url: "wss://test.relay")

        await coordinator.handleEOSE(from: mockRelay)

        // Then: Should handle gracefully without crash
        // With force cast, this would crash. After fix, it should skip the callback
        XCTAssertEqual(eoseRelays.count, 0, "Mock relay should not trigger NDKRelay-specific callbacks")
    }

    func testHandleEventWithNDKRelayWorks() async throws {
        // Given: A coordinator with event handler and real NDKRelay
        let ndk = NDK()
        let filter = NDKFilter(kinds: [1])
        let coordinator = NDKSubscriptionCoordinator(
            id: "test-sub",
            filters: [filter],
            relays: nil,
            ndk: ndk
        )

        var receivedEvents: [(NDKEvent, String)] = []
        coordinator.setOnEvent { event, relay in
            receivedEvents.append((event, relay.url))
        }

        // When: Event from a real NDKRelay
        let ndkRelay = NDKRelay(url: "wss://test.relay")
        ndkRelay.ndk = ndk
        let event = NDKEvent(kind: 1, content: "test", tags: [], pubkey: "test-pubkey")

        await coordinator.handleEvent(event, from: ndkRelay)

        // Then: Should call the callback
        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents[0].1, "wss://test.relay")
    }
}
