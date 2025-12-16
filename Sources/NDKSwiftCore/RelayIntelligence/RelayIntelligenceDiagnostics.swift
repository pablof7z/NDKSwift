import Foundation

/// Diagnostic information about the relay pool
public struct PoolDiagnostics: Sendable {
    /// Total number of relays in the pool
    public let totalRelays: Int
    /// Number of persistent (explicit/outboxConfig) relays
    public let persistentRelays: Int
    /// Number of non-persistent (dynamic) relays
    public let dynamicRelays: Int
    /// Number of connected relays
    public let connectedRelays: Int

    public init(totalRelays: Int, persistentRelays: Int, dynamicRelays: Int, connectedRelays: Int) {
        self.totalRelays = totalRelays
        self.persistentRelays = persistentRelays
        self.dynamicRelays = dynamicRelays
        self.connectedRelays = connectedRelays
    }
}

/// Complete diagnostic report for relay intelligence
public struct RelayIntelligenceDiagnostics: Sendable {
    /// Statistics about the hint index
    public let hintIndex: HintIndexStatistics
    /// Statistics about the relay pool
    public let pool: PoolDiagnostics
    /// Most frequently mentioned relays in hints
    public let mostKnownRelays: [RelayMention]
    /// Breakdown of hints by source
    public let hintSourceBreakdown: [HintSource: Int]
    /// Timestamp when this report was generated
    public let generatedAt: Date

    public init(
        hintIndex: HintIndexStatistics,
        pool: PoolDiagnostics,
        mostKnownRelays: [RelayMention],
        hintSourceBreakdown: [HintSource: Int],
        generatedAt: Date = Date()
    ) {
        self.hintIndex = hintIndex
        self.pool = pool
        self.mostKnownRelays = mostKnownRelays
        self.hintSourceBreakdown = hintSourceBreakdown
        self.generatedAt = generatedAt
    }
}

// MARK: - NDK Extension for Diagnostics

public extension NDK {
    /// Generate a comprehensive diagnostic report for relay intelligence
    func relayIntelligenceDiagnostics() async -> RelayIntelligenceDiagnostics {
        // Gather hint index stats
        let hintStats = await hintIndex.statistics
        let mostKnown = await hintIndex.mostKnownRelays(limit: 10)
        let sourceBreakdown = await hintIndex.sourceBreakdown

        // Gather pool stats
        let relays = await pool.relays
        var persistentCount = 0
        var connectedCount = 0

        for relay in relays {
            if await relay.isPersistent {
                persistentCount += 1
            }
            if await relay.connectionState == .connected {
                connectedCount += 1
            }
        }

        let poolDiagnostics = PoolDiagnostics(
            totalRelays: relays.count,
            persistentRelays: persistentCount,
            dynamicRelays: relays.count - persistentCount,
            connectedRelays: connectedCount
        )

        return RelayIntelligenceDiagnostics(
            hintIndex: hintStats,
            pool: poolDiagnostics,
            mostKnownRelays: mostKnown,
            hintSourceBreakdown: sourceBreakdown
        )
    }
}
