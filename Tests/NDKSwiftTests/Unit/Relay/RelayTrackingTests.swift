@testable import NDKSwiftCore
import XCTest

final class RelayTrackingTests: XCTestCase {
    func testEventTrackerIsPublic() async throws {
        let ndk = NDK()

        // Verify eventTracker is publicly accessible
        XCTAssertNotNil(ndk.eventTracker)

        // Test basic tracking functionality
        let eventId = "abcd1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab"
        let relayUrl = "wss://relay.example.com"

        await ndk.eventTracker.setSourceRelay(eventId: eventId, relay: relayUrl)

        let sourceRelay = await ndk.eventTracker.getSourceRelay(eventId: eventId)
        XCTAssertEqual(sourceRelay, relayUrl)

        let seenRelays = await ndk.eventTracker.getSeenOnRelays(eventId: eventId)
        XCTAssertTrue(seenRelays.contains(relayUrl))
    }

    func testMultipleRelayTracking() async throws {
        let ndk = NDK()
        let eventId = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        let relay1 = "wss://relay1.example.com"
        let relay2 = "wss://relay2.example.com"
        let relay3 = "wss://relay3.example.com"

        // Set first relay as source
        await ndk.eventTracker.setSourceRelay(eventId: eventId, relay: relay1)

        // Mark seen on additional relays
        await ndk.eventTracker.markSeen(eventId: eventId, relay: relay2)
        await ndk.eventTracker.markSeen(eventId: eventId, relay: relay3)

        // Verify source relay is still the first one
        let sourceRelay = await ndk.eventTracker.getSourceRelay(eventId: eventId)
        XCTAssertEqual(sourceRelay, relay1)

        // Verify all relays are tracked
        let seenRelays = await ndk.eventTracker.getSeenOnRelays(eventId: eventId)
        XCTAssertEqual(seenRelays.count, 3)
        XCTAssertTrue(seenRelays.contains(relay1))
        XCTAssertTrue(seenRelays.contains(relay2))
        XCTAssertTrue(seenRelays.contains(relay3))
    }
}
