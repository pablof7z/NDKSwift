import Foundation

/// Tracks metrics about subscription grouping effectiveness
public actor NDKSubscriptionGroupingMetrics {
    /// Total number of subscriptions created
    private var totalSubscriptions: Int = 0
    
    /// Number of subscriptions that were grouped with others
    private var groupedSubscriptions: Int = 0
    
    /// Number of non-groupable subscriptions
    private var nonGroupableSubscriptions: Int = 0
    
    /// Total number of REQ messages sent
    private var totalReqMessages: Int = 0
    
    /// Number of REQ messages saved through grouping
    private var reqMessagesSaved: Int = 0
    
    /// Average group size (subscriptions per group)
    private var groupSizes: [Int] = []
    
    /// Time saved through batching (estimated)
    private var totalTimeSaved: TimeInterval = 0
    
    /// Grouping delay statistics
    private var delayStatistics: DelayStatistics = DelayStatistics()
    
    /// Per-relay metrics
    private var relayMetrics: [String: RelayMetrics] = [:]
    
    // MARK: - Recording Methods
    
    /// Records a new subscription
    public func recordSubscription(isGroupable: Bool) {
        totalSubscriptions += 1
        if !isGroupable {
            nonGroupableSubscriptions += 1
        }
    }
    
    /// Records when a subscription is added to an existing group
    public func recordGroupedSubscription() {
        groupedSubscriptions += 1
    }
    
    /// Records when a REQ message is sent
    public func recordReqMessage(groupSize: Int, relay: String) {
        totalReqMessages += 1
        groupSizes.append(groupSize)
        
        // Calculate saved messages (group size - 1)
        if groupSize > 1 {
            reqMessagesSaved += (groupSize - 1)
        }
        
        // Update relay-specific metrics
        var metrics = relayMetrics[relay] ?? RelayMetrics()
        metrics.totalReqMessages += 1
        
        // Calculate new average
        let previousTotal = metrics.totalReqMessages - 1
        let previousAverage = metrics.averageGroupSize
        metrics.averageGroupSize = (previousAverage * Double(previousTotal) + Double(groupSize)) / Double(metrics.totalReqMessages)
        
        // Store back in dictionary
        relayMetrics[relay] = metrics
    }
    
    /// Records delay information
    public func recordDelay(actualDelay: TimeInterval, configuredDelay: TimeInterval, delayType: NDKSubscriptionDelayType) {
        delayStatistics.record(actualDelay: actualDelay, configuredDelay: configuredDelay, delayType: delayType)
    }
    
    /// Records time saved through batching
    public func recordTimeSaved(_ time: TimeInterval) {
        totalTimeSaved += time
    }
    
    // MARK: - Metrics Retrieval
    
    /// Get current metrics snapshot
    public func getSnapshot() -> MetricsSnapshot {
        let avgGroupSize = groupSizes.isEmpty ? 0.0 : 
            Double(groupSizes.reduce(0, +)) / Double(groupSizes.count)
        
        let groupingEfficiency = totalSubscriptions > 0 ? 
            Double(groupedSubscriptions) / Double(totalSubscriptions) : 0.0
        
        let messageReduction = totalReqMessages > 0 ? 
            Double(reqMessagesSaved) / Double(totalReqMessages + reqMessagesSaved) : 0.0
        
        return MetricsSnapshot(
            totalSubscriptions: totalSubscriptions,
            groupedSubscriptions: groupedSubscriptions,
            nonGroupableSubscriptions: nonGroupableSubscriptions,
            totalReqMessages: totalReqMessages,
            reqMessagesSaved: reqMessagesSaved,
            averageGroupSize: avgGroupSize,
            groupingEfficiency: groupingEfficiency,
            messageReduction: messageReduction,
            totalTimeSaved: totalTimeSaved,
            delayStatistics: delayStatistics,
            relayMetrics: relayMetrics
        )
    }
    
    /// Reset all metrics
    public func reset() {
        totalSubscriptions = 0
        groupedSubscriptions = 0
        nonGroupableSubscriptions = 0
        totalReqMessages = 0
        reqMessagesSaved = 0
        groupSizes = []
        totalTimeSaved = 0
        delayStatistics = DelayStatistics()
        relayMetrics = [:]
    }
}

// MARK: - Supporting Types

/// Statistics about grouping delays
public struct DelayStatistics: Sendable {
    public var totalDelays: Int = 0
    public var averageActualDelay: TimeInterval = 0
    public var averageConfiguredDelay: TimeInterval = 0
    public var atLeastCount: Int = 0
    public var atMostCount: Int = 0
    
    mutating func record(actualDelay: TimeInterval, configuredDelay: TimeInterval, delayType: NDKSubscriptionDelayType) {
        totalDelays += 1
        
        // Update running averages
        averageActualDelay = ((averageActualDelay * Double(totalDelays - 1)) + actualDelay) / Double(totalDelays)
        averageConfiguredDelay = ((averageConfiguredDelay * Double(totalDelays - 1)) + configuredDelay) / Double(totalDelays)
        
        switch delayType {
        case .atLeast:
            atLeastCount += 1
        case .atMost:
            atMostCount += 1
        }
    }
}

/// Metrics specific to a relay
public struct RelayMetrics: Sendable {
    public var totalReqMessages: Int = 0
    public var averageGroupSize: Double = 0
}

/// Snapshot of current metrics
public struct MetricsSnapshot: Sendable {
    public let totalSubscriptions: Int
    public let groupedSubscriptions: Int
    public let nonGroupableSubscriptions: Int
    public let totalReqMessages: Int
    public let reqMessagesSaved: Int
    public let averageGroupSize: Double
    public let groupingEfficiency: Double
    public let messageReduction: Double
    public let totalTimeSaved: TimeInterval
    public let delayStatistics: DelayStatistics
    public let relayMetrics: [String: RelayMetrics]
    
    /// Get a human-readable summary
    public var summary: String {
        """
        Subscription Grouping Metrics:
        - Total Subscriptions: \(totalSubscriptions)
        - Grouped Subscriptions: \(groupedSubscriptions) (\(String(format: "%.1f", groupingEfficiency * 100))%)
        - Non-Groupable: \(nonGroupableSubscriptions)
        - REQ Messages Sent: \(totalReqMessages)
        - REQ Messages Saved: \(reqMessagesSaved) (\(String(format: "%.1f", messageReduction * 100))% reduction)
        - Average Group Size: \(String(format: "%.2f", averageGroupSize))
        - Time Saved: \(String(format: "%.2f", totalTimeSaved))s
        - Delay Stats: \(delayStatistics.totalDelays) delays, avg actual: \(String(format: "%.3f", delayStatistics.averageActualDelay))s
        """
    }
}

// MARK: - Global Metrics Instance

/// Shared metrics instance for the application
public let NDKSubscriptionMetrics = NDKSubscriptionGroupingMetrics()