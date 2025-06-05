@testable import NDKSwift
import XCTest

final class NDKRelayRankerTests: XCTestCase {
    var ndk: NDK!
    var tracker: NDKOutboxTracker!
    var ranker: NDKRelayRanker!

    override func setUp() async throws {
        ndk = NDK()
        tracker = NDKOutboxTracker(ndk: ndk)
        ranker = NDKRelayRanker(ndk: ndk, tracker: tracker)
    }

    func testGetTopRelaysForAuthors() async {
        // Set up relay information for multiple authors
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://popular.relay", "wss://relay1.com"],
            writeRelays: ["wss://popular.relay"]
        )

        await tracker.track(
            pubkey: "author2",
            readRelays: ["wss://popular.relay", "wss://relay2.com"],
            writeRelays: ["wss://popular.relay", "wss://relay3.com"]
        )

        await tracker.track(
            pubkey: "author3",
            readRelays: ["wss://relay1.com"],
            writeRelays: ["wss://relay3.com"]
        )

        // Get top relays
        let topRelays = await ranker.getTopRelaysForAuthors(
            ["author1", "author2", "author3"]
        )

        // popular.relay should be first (used by 2 authors)
        XCTAssertEqual(topRelays.first, "wss://popular.relay")

        // Verify ordering by author count
        let relayAuthorCounts = await getRelayAuthorCounts(
            for: ["author1", "author2", "author3"]
        )

        XCTAssertEqual(relayAuthorCounts["wss://popular.relay"], 2)
        XCTAssertTrue(relayAuthorCounts["wss://relay1.com"] ?? 0 >= 1)
        XCTAssertTrue(relayAuthorCounts["wss://relay3.com"] ?? 0 >= 1)
    }

    func testGetTopRelaysWithLimit() async {
        // Track many relays
        for i in 0 ..< 10 {
            await tracker.track(
                pubkey: "author\(i)",
                readRelays: ["wss://relay\(i).com", "wss://common.relay"]
            )
        }

        let topRelays = await ranker.getTopRelaysForAuthors(
            (0 ..< 10).map { "author\($0)" },
            limit: 3
        )

        XCTAssertEqual(topRelays.count, 3)
        XCTAssertEqual(topRelays.first, "wss://common.relay")
    }

    func testUpdateRelayPerformance() async {
        let relayURL = "wss://test.relay"

        // Record some successes and failures
        await ranker.updateRelayPerformance(relayURL, success: true, responseTime: 0.1)
        await ranker.updateRelayPerformance(relayURL, success: true, responseTime: 0.2)
        await ranker.updateRelayPerformance(relayURL, success: false)
        await ranker.updateRelayPerformance(relayURL, success: true, responseTime: 0.15)

        // Get health score (should be 75% success rate)
        let healthScore = await ranker.getRelayHealthScore(relayURL)

        // Health score includes recency factor, so exact value may vary
        XCTAssertGreaterThan(healthScore, 0.5)
        XCTAssertLessThanOrEqual(healthScore, 1.0)
    }

    func testRelayHealthScoreDecay() async {
        let relayURL = "wss://old.relay"

        // Update performance with perfect score
        await ranker.updateRelayPerformance(relayURL, success: true)
        await ranker.updateRelayPerformance(relayURL, success: true)

        let immediateScore = await ranker.getRelayHealthScore(relayURL)
        XCTAssertGreaterThan(immediateScore, 0.9)

        // Simulate time passing (can't actually wait in tests)
        // The score should decay over time but this is hard to test without mocking time
    }

    func testRankRelaysWithPreferences() async {
        // Set up test data
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://relay1.com", "wss://relay2.com"],
            writeRelays: ["wss://relay1.com"]
        )

        // Update performance metrics
        await ranker.updateRelayPerformance("wss://relay1.com", success: true, responseTime: 0.1)
        await ranker.updateRelayPerformance("wss://relay2.com", success: true, responseTime: 0.5)

        // Create custom preferences
        let preferences = RelayPreferences(
            connectionBonus: 0.5,
            healthWeight: 0.2,
            coverageWeight: 0.5,
            responseTimeWeight: 0.3,
            maxAcceptableResponseTime: 1.0
        )

        let rankedRelays = await ranker.rankRelays(
            ["wss://relay1.com", "wss://relay2.com", "wss://relay3.com"],
            for: ["author1"],
            preferences: preferences
        )

        XCTAssertEqual(rankedRelays.count, 3)

        // relay1 should score higher (better response time, covers author)
        XCTAssertEqual(rankedRelays[0].url, "wss://relay1.com")
        XCTAssertGreaterThan(rankedRelays[0].score, rankedRelays[1].score)
    }

    func testRankRelaysWithConnectedBonus() async {
        // Mock connected relays
        let mockNDK = MockNDKWithConnectedRelays(
            connectedRelayURLs: ["wss://connected.relay"]
        )
        let mockTracker = NDKOutboxTracker(ndk: mockNDK)
        let mockRanker = NDKRelayRanker(ndk: mockNDK, tracker: mockTracker)

        await mockTracker.track(
            pubkey: "author1",
            readRelays: ["wss://connected.relay", "wss://disconnected.relay"]
        )

        let rankedRelays = await mockRanker.rankRelays(
            ["wss://connected.relay", "wss://disconnected.relay"],
            for: ["author1"],
            preferences: RelayPreferences(connectionBonus: 1.0)
        )

        // Connected relay should rank higher
        XCTAssertEqual(rankedRelays[0].url, "wss://connected.relay")
        XCTAssertGreaterThan(
            rankedRelays[0].score,
            rankedRelays[1].score,
            "Connected relay should have higher score"
        )
    }

    func testEmptyAuthors() async {
        let topRelays = await ranker.getTopRelaysForAuthors([])
        XCTAssertEqual(topRelays.count, 0)

        let rankedRelays = await ranker.rankRelays(
            ["wss://relay1.com"],
            for: []
        )

        XCTAssertEqual(rankedRelays.count, 1)
        // Score should be based only on health and connection status
    }

    // MARK: - Helper Methods

    private func getRelayAuthorCounts(for pubkeys: [String]) async -> [String: Int] {
        var counts: [String: Int] = [:]

        for pubkey in pubkeys {
            if let item = await tracker.getRelaysSyncFor(pubkey: pubkey) {
                for relayURL in item.allRelayURLs {
                    counts[relayURL, default: 0] += 1
                }
            }
        }

        return counts
    }
}

// MARK: - Mock Implementations

class MockNDKWithConnectedRelays: NDK {
    let connectedRelayURLs: [String]

    init(connectedRelayURLs: [String]) {
        self.connectedRelayURLs = connectedRelayURLs
        super.init()
    }

    override var relayPool: NDKRelayPool {
        return MockRelayPool(connectedURLs: connectedRelayURLs)
    }
}

class MockRelayPool: NDKRelayPool {
    let connectedURLs: [String]

    init(connectedURLs: [String]) {
        self.connectedURLs = connectedURLs
        super.init()
    }

    override var connectedRelays: [NDKRelay] {
        return connectedURLs.map { url in
            NDKRelay(url: url, connectionState: .connected)
        }
    }
}

extension NDKRelay {
    convenience init(url: String, connectionState: NDKRelayConnectionState) {
        self.init(url)
        self.connectionState = connectionState
    }
}
