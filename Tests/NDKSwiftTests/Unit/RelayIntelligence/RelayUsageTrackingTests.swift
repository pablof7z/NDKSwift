import XCTest
@testable import NDKSwiftCore

final class RelayUsageTrackingTests: XCTestCase {
    // MARK: - Last Activity Tracking Tests

    func test_relay_lastActivityAt_startsNil() async {
        let relay = NDKRelay(url: "wss://relay.example.com")
        let stats = await relay.stats
        XCTAssertNil(stats.lastActivityAt)
    }

    func test_relay_lastActivityAt_updatedOnMessageSent() async {
        let relay = NDKRelay(url: "wss://relay.example.com")
        let beforeSend = Date()

        // Simulate message sent by updating stats directly
        await relay.recordActivity()

        let stats = await relay.stats
        XCTAssertNotNil(stats.lastActivityAt)
        if let lastActivity = stats.lastActivityAt {
            XCTAssertGreaterThanOrEqual(lastActivity, beforeSend)
        }
    }

    func test_relay_idleTime_calculatedCorrectly() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        // Record activity
        await relay.recordActivity()

        // Wait a short time
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let idleTime = await relay.idleTime
        XCTAssertGreaterThanOrEqual(idleTime, 0.1)
    }

    func test_relay_idleTime_isInfiniteWithNoActivity() async {
        let relay = NDKRelay(url: "wss://relay.example.com")

        let idleTime = await relay.idleTime
        XCTAssertEqual(idleTime, .infinity)
    }
}
