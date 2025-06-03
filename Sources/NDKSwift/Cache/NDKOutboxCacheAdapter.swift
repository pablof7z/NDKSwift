import Foundation

/// Extended cache adapter protocol with comprehensive outbox support
public protocol NDKOutboxCacheAdapter: NDKCacheAdapter {
    // MARK: - Unpublished Event Management
    
    /// Store an unpublished event with detailed relay status
    func storeUnpublishedEvent(
        _ event: NDKEvent,
        targetRelays: Set<String>,
        publishConfig: OutboxPublishConfig?
    ) async
    
    /// Get all unpublished events with their status
    func getAllUnpublishedEvents() async -> [UnpublishedEventRecord]
    
    /// Update the status of an unpublished event for a specific relay
    func updateUnpublishedEventStatus(
        eventId: String,
        relayURL: String,
        status: RelayPublishStatus
    ) async
    
    /// Mark an unpublished event as globally succeeded
    func markEventAsPublished(eventId: String) async
    
    /// Get unpublished events that need retry
    func getEventsForRetry(olderThan: TimeInterval) async -> [UnpublishedEventRecord]
    
    /// Clean up old published events
    func cleanupPublishedEvents(olderThan: TimeInterval) async
    
    // MARK: - Outbox Relay Information
    
    /// Store relay information for a user
    func storeOutboxItem(_ item: NDKOutboxItem) async
    
    /// Get relay information for a user
    func getOutboxItem(for pubkey: String) async -> NDKOutboxItem?
    
    /// Store relay health metrics
    func updateRelayHealth(url: String, health: RelayHealthMetrics) async
    
    /// Get relay health metrics
    func getRelayHealth(url: String) async -> RelayHealthMetrics?
}

/// Record of an unpublished event with relay statuses
public struct UnpublishedEventRecord: Codable {
    public let event: NDKEvent
    public let targetRelays: Set<String>
    public let relayStatuses: [String: RelayPublishStatus]
    public let createdAt: Date
    public let lastAttemptAt: Date?
    public let publishConfig: StoredPublishConfig?
    public let overallStatus: PublishStatus
    
    public init(
        event: NDKEvent,
        targetRelays: Set<String>,
        relayStatuses: [String: RelayPublishStatus] = [:],
        createdAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        publishConfig: StoredPublishConfig? = nil,
        overallStatus: PublishStatus = .pending
    ) {
        self.event = event
        self.targetRelays = targetRelays
        self.relayStatuses = relayStatuses
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
        self.publishConfig = publishConfig
        self.overallStatus = overallStatus
    }
    
    /// Check if this event should be retried
    public func shouldRetry(after interval: TimeInterval) -> Bool {
        guard overallStatus == .pending || overallStatus == .inProgress else {
            return false
        }
        
        guard let lastAttempt = lastAttemptAt else {
            return true // Never attempted
        }
        
        return Date().timeIntervalSince(lastAttempt) > interval
    }
}

/// Stored version of publish config (simplified for persistence)
public struct StoredPublishConfig: Codable {
    public let minSuccessfulRelays: Int
    public let maxRetries: Int
    public let enablePow: Bool
    public let maxPowDifficulty: Int?
    
    public init(from config: OutboxPublishConfig) {
        self.minSuccessfulRelays = config.minSuccessfulRelays
        self.maxRetries = config.maxRetries
        self.enablePow = config.enablePow
        self.maxPowDifficulty = config.maxPowDifficulty
    }
}

/// Relay health metrics for caching
public struct RelayHealthMetrics: Codable {
    public let url: String
    public let successRate: Double
    public let avgResponseTime: TimeInterval
    public let lastSuccessAt: Date?
    public let lastFailureAt: Date?
    public let totalRequests: Int
    public let successfulRequests: Int
    public let updatedAt: Date
    
    public init(
        url: String,
        successRate: Double,
        avgResponseTime: TimeInterval,
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        totalRequests: Int = 0,
        successfulRequests: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.url = url
        self.successRate = successRate
        self.avgResponseTime = avgResponseTime
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.totalRequests = totalRequests
        self.successfulRequests = successfulRequests
        self.updatedAt = updatedAt
    }
}

// MARK: - Default Implementation Extensions

extension NDKOutboxCacheAdapter {
    /// Default implementation that converts to legacy format
    public func addUnpublishedEvent(_ event: NDKEvent, relayUrls: [RelayURL]) async {
        let targetRelays = Set(relayUrls)
        await storeUnpublishedEvent(event, targetRelays: targetRelays, publishConfig: nil)
    }
    
    /// Default implementation that filters by relay
    public func getUnpublishedEvents(for relayUrl: RelayURL) async -> [NDKEvent] {
        let allEvents = await getAllUnpublishedEvents()
        return allEvents
            .filter { $0.targetRelays.contains(relayUrl) }
            .map { $0.event }
    }
    
    /// Default implementation that updates status
    public func removeUnpublishedEvent(_ eventId: EventID, from relayUrl: RelayURL) async {
        await updateUnpublishedEventStatus(
            eventId: eventId,
            relayURL: relayUrl,
            status: .succeeded
        )
    }
}