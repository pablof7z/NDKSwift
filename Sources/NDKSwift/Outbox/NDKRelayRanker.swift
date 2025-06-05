import Foundation

/// Ranks relays based on various criteria for optimal selection
public actor NDKRelayRanker {
    private let ndk: NDK
    private let tracker: NDKOutboxTracker

    /// Cache of relay scores
    private var relayScores: [String: RelayScore] = [:]

    public init(ndk: NDK, tracker: NDKOutboxTracker) {
        self.ndk = ndk
        self.tracker = tracker
    }

    /// Get top relays for a set of authors
    public func getTopRelaysForAuthors(
        _ pubkeys: [String],
        limit: Int? = nil
    ) async -> [String] {
        // Count how many authors use each relay
        var relayAuthorCount: [String: Int] = [:]

        for pubkey in pubkeys {
            if let item = await tracker.getRelaysSyncFor(pubkey: pubkey) {
                for relayURL in item.allRelayURLs {
                    relayAuthorCount[relayURL, default: 0] += 1
                }
            }
        }

        // Sort by author count and apply limit
        let sorted = relayAuthorCount.sorted { $0.value > $1.value }
            .map { $0.key }

        if let limit = limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    /// Rank relays for optimal selection
    public func rankRelays(
        _ relayURLs: [String],
        for pubkeys: [String],
        preferences: RelayPreferences = .default
    ) async -> [RankedRelay] {
        var rankedRelays: [RankedRelay] = []

        // Get connected relays for preferential treatment
        let connectedRelayURLs = await ndk.relayPool.connectedRelays().map { $0.url }
        let connectedSet = Set(connectedRelayURLs)

        for relayURL in relayURLs {
            let score = await calculateRelayScore(
                relayURL,
                for: pubkeys,
                isConnected: connectedSet.contains(relayURL),
                preferences: preferences
            )

            rankedRelays.append(RankedRelay(url: relayURL, score: score))
        }

        // Sort by score descending
        return rankedRelays.sorted { $0.score > $1.score }
    }

    /// Update relay score based on performance
    public func updateRelayPerformance(
        _ relayURL: String,
        success: Bool,
        responseTime: TimeInterval? = nil
    ) {
        var score = relayScores[relayURL] ?? RelayScore()

        if success {
            score.successCount += 1
            if let responseTime = responseTime {
                score.totalResponseTime += responseTime
            }
        } else {
            score.failureCount += 1
        }

        score.lastUpdated = Date()
        relayScores[relayURL] = score
    }

    /// Get relay health score (0-1)
    public func getRelayHealthScore(_ relayURL: String) -> Double {
        guard let score = relayScores[relayURL] else { return 0.5 } // Default neutral score

        let total = score.successCount + score.failureCount
        guard total > 0 else { return 0.5 }

        // Calculate success rate
        let successRate = Double(score.successCount) / Double(total)

        // Factor in recency (decay older scores)
        let ageInHours = Date().timeIntervalSince(score.lastUpdated) / 3600
        let recencyFactor = max(0.5, 1.0 - (ageInHours / 168)) // Decay over a week

        return successRate * recencyFactor
    }

    // MARK: - Private Methods

    private func calculateRelayScore(
        _ relayURL: String,
        for pubkeys: [String],
        isConnected: Bool,
        preferences: RelayPreferences
    ) async -> Double {
        var score = 0.0

        // Connection status bonus
        if isConnected {
            score += preferences.connectionBonus
        }

        // Health score component
        let healthScore = getRelayHealthScore(relayURL)
        score += healthScore * preferences.healthWeight

        // Author coverage component
        var authorCoverage = 0
        for pubkey in pubkeys {
            if let item = await tracker.getRelaysSyncFor(pubkey: pubkey),
               item.allRelayURLs.contains(relayURL)
            {
                authorCoverage += 1
            }
        }
        let coverageRatio = pubkeys.isEmpty ? 0 : Double(authorCoverage) / Double(pubkeys.count)
        score += coverageRatio * preferences.coverageWeight

        // Response time component
        if let relayScore = relayScores[relayURL], relayScore.successCount > 0 {
            let avgResponseTime = relayScore.totalResponseTime / Double(relayScore.successCount)
            // Lower response time = higher score (capped at 1.0)
            let responseScore = max(0, 1.0 - (avgResponseTime / preferences.maxAcceptableResponseTime))
            score += responseScore * preferences.responseTimeWeight
        }

        return score
    }
}

/// Preferences for relay ranking
public struct RelayPreferences {
    /// Bonus score for already connected relays
    public let connectionBonus: Double

    /// Weight for relay health score
    public let healthWeight: Double

    /// Weight for author coverage
    public let coverageWeight: Double

    /// Weight for response time
    public let responseTimeWeight: Double

    /// Maximum acceptable response time in seconds
    public let maxAcceptableResponseTime: TimeInterval

    public init(
        connectionBonus: Double = 0.3,
        healthWeight: Double = 0.3,
        coverageWeight: Double = 0.5,
        responseTimeWeight: Double = 0.2,
        maxAcceptableResponseTime: TimeInterval = 2.0
    ) {
        self.connectionBonus = connectionBonus
        self.healthWeight = healthWeight
        self.coverageWeight = coverageWeight
        self.responseTimeWeight = responseTimeWeight
        self.maxAcceptableResponseTime = maxAcceptableResponseTime
    }

    public static let `default` = RelayPreferences()
}

/// A relay with its calculated score
public struct RankedRelay {
    public let url: String
    public let score: Double
}

/// Internal relay score tracking
private struct RelayScore {
    var successCount: Int = 0
    var failureCount: Int = 0
    var totalResponseTime: TimeInterval = 0
    var lastUpdated: Date = .init()
}
