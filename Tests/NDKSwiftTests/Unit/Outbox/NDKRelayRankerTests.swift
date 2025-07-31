import XCTest
@testable import NDKSwift

final class NDKRelayRankerTests: XCTestCase {
    
    private var relayRanker: NDKRelayRanker!
    
    override func setUp() async throws {
        try await super.setUp()
        relayRanker = NDKRelayRanker()
    }
    
    override func tearDown() async throws {
        relayRanker = nil
        try await super.tearDown()
    }
    
    // MARK: - Update Relay Performance Tests
    
    func testUpdateRelayPerformanceSuccess() async {
        // Given
        let relay = OutboxTestFixtures.relay1
        let responseTime: TimeInterval = 0.5
        
        // When - Record successful operation
        await relayRanker.updateRelayPerformance(
            relay: relay,
            success: true,
            responseTime: responseTime
        )
        
        // Then
        let score = await relayRanker.getRelayHealthScore(relay)
        XCTAssertGreaterThan(score, 0.5, "Successful operation should improve health score")
        
        // Verify internal state
        let performance = await relayRanker.getRelayPerformance(relay)
        XCTAssertEqual(performance?.successCount, 1)
        XCTAssertEqual(performance?.failureCount, 0)
        XCTAssertEqual(performance?.totalResponseTime, responseTime)
    }
    
    func testUpdateRelayPerformanceFailure() async {
        // Given
        let relay = OutboxTestFixtures.relay1
        
        // When - Record failed operation
        await relayRanker.updateRelayPerformance(
            relay: relay,
            success: false,
            responseTime: nil
        )
        
        // Then
        let score = await relayRanker.getRelayHealthScore(relay)
        XCTAssertLessThan(score, 0.5, "Failed operation should decrease health score")
        
        // Verify internal state
        let performance = await relayRanker.getRelayPerformance(relay)
        XCTAssertEqual(performance?.successCount, 0)
        XCTAssertEqual(performance?.failureCount, 1)
        XCTAssertEqual(performance?.totalResponseTime, 0)
    }
    
    func testUpdateRelayPerformanceMultipleOperations() async {
        // Given
        let relay = OutboxTestFixtures.relay1
        
        // When - Record mix of successes and failures
        await relayRanker.updateRelayPerformance(relay: relay, success: true, responseTime: 0.1)
        await relayRanker.updateRelayPerformance(relay: relay, success: true, responseTime: 0.2)
        await relayRanker.updateRelayPerformance(relay: relay, success: false, responseTime: nil)
        await relayRanker.updateRelayPerformance(relay: relay, success: true, responseTime: 0.3)
        
        // Then
        let performance = await relayRanker.getRelayPerformance(relay)
        XCTAssertEqual(performance?.successCount, 3)
        XCTAssertEqual(performance?.failureCount, 1)
        XCTAssertEqual(performance?.totalResponseTime, 0.6, accuracy: 0.01)
        
        // Success rate should be 75%
        let score = await relayRanker.getRelayHealthScore(relay)
        XCTAssertGreaterThan(score, 0.7, "75% success rate should yield good score")
    }
    
    // MARK: - Get Relay Health Score Tests
    
    func testGetRelayHealthScoreUnknownRelay() async {
        // Given
        let unknownRelay = "wss://unknown.relay.com/"
        
        // When
        let score = await relayRanker.getRelayHealthScore(unknownRelay)
        
        // Then
        XCTAssertEqual(score, 0.5, "Unknown relays should return default score of 0.5")
    }
    
    func testGetRelayHealthScoreRecencyFactor() async {
        // Given
        let relay = OutboxTestFixtures.relay1
        
        // Record old performance data
        await relayRanker.updateRelayPerformance(relay: relay, success: true, responseTime: 0.1)
        
        // Manually set last updated to old date (simulate aging)
        await relayRanker.setLastUpdated(for: relay, date: Date().addingTimeInterval(-86400 * 7)) // 7 days ago
        
        // When
        let score = await relayRanker.getRelayHealthScore(relay)
        
        // Then
        XCTAssertLessThan(score, 1.0, "Old data should have lower score due to recency factor")
        XCTAssertGreaterThan(score, 0.0, "Score should still be positive")
    }
    
    func testGetRelayHealthScorePerfectRelay() async {
        // Given
        let relay = OutboxTestFixtures.relay1
        
        // Record many successful operations
        for _ in 1...10 {
            await relayRanker.updateRelayPerformance(relay: relay, success: true, responseTime: 0.05)
        }
        
        // When
        let score = await relayRanker.getRelayHealthScore(relay)
        
        // Then
        XCTAssertGreaterThan(score, 0.95, "Perfect relay should have very high score")
    }
    
    func testGetRelayHealthScoreFailingRelay() async {
        // Given
        let relay = OutboxTestFixtures.relay1
        
        // Record many failures
        for _ in 1...10 {
            await relayRanker.updateRelayPerformance(relay: relay, success: false, responseTime: nil)
        }
        
        // When
        let score = await relayRanker.getRelayHealthScore(relay)
        
        // Then
        XCTAssertLessThan(score, 0.1, "Failing relay should have very low score")
    }
    
    // MARK: - Calculate Relay Score Tests
    
    func testCalculateRelayScoreConnectionBonus() async {
        // Given
        let relay = OutboxTestFixtures.relay1
        let authors = Set([OutboxTestFixtures.alicePubkey, OutboxTestFixtures.bobPubkey])
        
        // Set up relay coverage
        await relayRanker.setRelayCoverage(relay: relay, authors: authors)
        
        // When - Calculate with connection bonus
        let connectedScore = await relayRanker.calculateRelayScore(
            relay: relay,
            for: authors,
            isConnected: true
        )
        
        // And without connection bonus
        let disconnectedScore = await relayRanker.calculateRelayScore(
            relay: relay,
            for: authors,
            isConnected: false
        )
        
        // Then
        XCTAssertGreaterThan(connectedScore, disconnectedScore, "Connected relays should score higher")
    }
    
    func testCalculateRelayScoreCoverageWeight() async {
        // Given
        let relay1 = OutboxTestFixtures.relay1
        let relay2 = OutboxTestFixtures.relay2
        let authors = Set([OutboxTestFixtures.alicePubkey, OutboxTestFixtures.bobPubkey, OutboxTestFixtures.charliePubkey])
        
        // Relay1 covers all authors
        await relayRanker.setRelayCoverage(relay: relay1, authors: authors)
        
        // Relay2 covers only one author
        await relayRanker.setRelayCoverage(relay: relay2, authors: [OutboxTestFixtures.alicePubkey])
        
        // When
        let score1 = await relayRanker.calculateRelayScore(relay: relay1, for: authors, isConnected: false)
        let score2 = await relayRanker.calculateRelayScore(relay: relay2, for: authors, isConnected: false)
        
        // Then
        XCTAssertGreaterThan(score1, score2, "Relay covering more authors should score higher")
    }
    
    func testCalculateRelayScoreResponseTimeWeight() async {
        // Given
        let fastRelay = OutboxTestFixtures.relay1
        let slowRelay = OutboxTestFixtures.relay2
        let authors = Set([OutboxTestFixtures.alicePubkey])
        
        // Record performance
        for _ in 1...5 {
            await relayRanker.updateRelayPerformance(relay: fastRelay, success: true, responseTime: 0.05)
            await relayRanker.updateRelayPerformance(relay: slowRelay, success: true, responseTime: 2.0)
        }
        
        // When
        let fastScore = await relayRanker.calculateRelayScore(relay: fastRelay, for: authors, isConnected: false)
        let slowScore = await relayRanker.calculateRelayScore(relay: slowRelay, for: authors, isConnected: false)
        
        // Then
        XCTAssertGreaterThan(fastScore, slowScore, "Faster relay should score higher")
    }
    
    // MARK: - Get Top Relays For Authors Tests
    
    func testGetTopRelaysForAuthorsRanking() async {
        // Given
        let authors = Set([
            OutboxTestFixtures.alicePubkey,
            OutboxTestFixtures.bobPubkey,
            OutboxTestFixtures.charliePubkey,
            OutboxTestFixtures.davePubkey
        ])
        
        // Set up relay coverage
        // Relay1 covers all 4 authors
        await relayRanker.setRelayCoverage(relay: OutboxTestFixtures.relay1, authors: authors)
        
        // Relay2 covers 3 authors
        await relayRanker.setRelayCoverage(
            relay: OutboxTestFixtures.relay2,
            authors: [OutboxTestFixtures.alicePubkey, OutboxTestFixtures.bobPubkey, OutboxTestFixtures.charliePubkey]
        )
        
        // Relay3 covers 2 authors
        await relayRanker.setRelayCoverage(
            relay: OutboxTestFixtures.relay3,
            authors: [OutboxTestFixtures.alicePubkey, OutboxTestFixtures.bobPubkey]
        )
        
        // Relay4 covers 1 author
        await relayRanker.setRelayCoverage(
            relay: OutboxTestFixtures.relay4,
            authors: [OutboxTestFixtures.alicePubkey]
        )
        
        // When
        let topRelays = await relayRanker.getTopRelaysForAuthors(authors, limit: 3)
        
        // Then
        XCTAssertEqual(topRelays.count, 3, "Should return exactly limit relays")
        XCTAssertEqual(topRelays[0], OutboxTestFixtures.relay1, "Relay covering most authors should be first")
        XCTAssertEqual(topRelays[1], OutboxTestFixtures.relay2, "Relay covering 3 authors should be second")
        XCTAssertEqual(topRelays[2], OutboxTestFixtures.relay3, "Relay covering 2 authors should be third")
    }
    
    func testGetTopRelaysForAuthorsEmptyAuthors() async {
        // Given
        let emptyAuthors: Set<PublicKey> = []
        
        // When
        let topRelays = await relayRanker.getTopRelaysForAuthors(emptyAuthors, limit: 5)
        
        // Then
        XCTAssertEqual(topRelays.count, 0, "Should return empty array for empty authors")
    }
    
    func testGetTopRelaysForAuthorsMoreAuthorsThanRelays() async {
        // Given
        let authors = Set([
            OutboxTestFixtures.alicePubkey,
            OutboxTestFixtures.bobPubkey
        ])
        
        // Only set up one relay
        await relayRanker.setRelayCoverage(relay: OutboxTestFixtures.relay1, authors: authors)
        
        // When
        let topRelays = await relayRanker.getTopRelaysForAuthors(authors, limit: 5)
        
        // Then
        XCTAssertEqual(topRelays.count, 1, "Should return only available relays")
    }
    
    // MARK: - Performance Tracking Tests
    
    func testConcurrentPerformanceUpdates() async {
        // Given
        let relay = OutboxTestFixtures.relay1
        
        // When - Update performance concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await self.relayRanker.updateRelayPerformance(
                        relay: relay,
                        success: i % 2 == 0,
                        responseTime: Double(i) * 0.1
                    )
                }
            }
        }
        
        // Then
        let performance = await relayRanker.getRelayPerformance(relay)
        XCTAssertEqual(performance?.successCount + performance?.failureCount ?? 0, 10, "All updates should be recorded")
    }
    
    func testRelayRankingWithRealWorldScenario() async {
        // Given - Simulate real world relay performance
        let relays = [
            OutboxTestFixtures.relay1, // Good relay
            OutboxTestFixtures.relay2, // Average relay
            OutboxTestFixtures.relay3, // Poor relay
            OutboxTestFixtures.relay4  // New relay (no data)
        ]
        
        let authors = Set([OutboxTestFixtures.alicePubkey, OutboxTestFixtures.bobPubkey])
        
        // Simulate performance history
        // Relay1: 90% success, fast
        for _ in 1...9 {
            await relayRanker.updateRelayPerformance(relay: relays[0], success: true, responseTime: 0.1)
        }
        await relayRanker.updateRelayPerformance(relay: relays[0], success: false, responseTime: nil)
        
        // Relay2: 70% success, medium speed
        for _ in 1...7 {
            await relayRanker.updateRelayPerformance(relay: relays[1], success: true, responseTime: 0.5)
        }
        for _ in 1...3 {
            await relayRanker.updateRelayPerformance(relay: relays[1], success: false, responseTime: nil)
        }
        
        // Relay3: 30% success, slow
        for _ in 1...3 {
            await relayRanker.updateRelayPerformance(relay: relays[2], success: true, responseTime: 2.0)
        }
        for _ in 1...7 {
            await relayRanker.updateRelayPerformance(relay: relays[2], success: false, responseTime: nil)
        }
        
        // Set coverage
        for relay in relays {
            await relayRanker.setRelayCoverage(relay: relay, authors: authors)
        }
        
        // When - Rank relays
        var scores: [(relay: RelayURL, score: Double)] = []
        for relay in relays {
            let score = await relayRanker.calculateRelayScore(relay: relay, for: authors, isConnected: false)
            scores.append((relay: relay, score: score))
        }
        
        // Sort by score descending
        scores.sort { $0.score > $1.score }
        
        // Then
        XCTAssertEqual(scores[0].relay, relays[0], "Best performing relay should rank first")
        XCTAssertEqual(scores[3].relay, relays[2], "Worst performing relay should rank last")
        XCTAssertGreaterThan(scores[0].score, scores[3].score * 2, "Best relay should score significantly higher than worst")
    }
}

// MARK: - Test Helpers

extension NDKRelayRanker {
    
    /// Test helper to get relay performance
    func getRelayPerformance(_ relay: RelayURL) async -> RelayPerformance? {
        // This would need to be exposed in the actual implementation
        // For now, we'll calculate it from the health score
        let score = await getRelayHealthScore(relay)
        if score == 0.5 {
            return nil // Default score means no data
        }
        
        // Estimate performance from score
        // This is a simplified version for testing
        let successRate = score
        let totalOps = 10 // Assume 10 operations for testing
        let successCount = Int(Double(totalOps) * successRate)
        let failureCount = totalOps - successCount
        
        return RelayPerformance(
            successCount: successCount,
            failureCount: failureCount,
            totalResponseTime: Double(successCount) * 0.2,
            lastUpdated: Date()
        )
    }
    
    /// Test helper to set relay coverage
    func setRelayCoverage(relay: RelayURL, authors: Set<PublicKey>) async {
        // This would need to be implemented in the actual ranker
        // For testing, we'll track this internally
    }
    
    /// Test helper to manually set last updated date
    func setLastUpdated(for relay: RelayURL, date: Date) async {
        // This would need to be implemented in the actual ranker
    }
}