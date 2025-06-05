import Foundation

// MARK: - Subscription Metrics

/// Overall metrics for a subscription across all relays
public struct NDKSubscriptionMetrics {
    /// Unique identifier for the subscription
    public let subscriptionId: String
    
    /// Total number of unique events received across all relays
    public var totalUniqueEvents: Int
    
    /// Total number of events received (including duplicates)
    public var totalEvents: Int
    
    /// Number of relays this subscription is active on
    public var activeRelayCount: Int
    
    /// Timestamp when the subscription was started
    public let startTime: Date
    
    /// Timestamp when the subscription was closed (nil if still active)
    public var endTime: Date?
    
    /// Duration of the subscription in seconds (nil if still active)
    public var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    /// Whether the subscription is currently active
    public var isActive: Bool {
        return endTime == nil
    }
    
    public init(subscriptionId: String, startTime: Date = Date()) {
        self.subscriptionId = subscriptionId
        self.totalUniqueEvents = 0
        self.totalEvents = 0
        self.activeRelayCount = 0
        self.startTime = startTime
        self.endTime = nil
    }
}

// MARK: - Relay-Level Subscription Tracking

/// Tracks subscription details at the relay level
public struct NDKRelaySubscriptionMetrics {
    /// The relay URL
    public let relayUrl: String
    
    /// The actual filter sent to this relay (may differ from original due to optimization)
    public let appliedFilter: NDKFilter
    
    /// Number of events received from this relay for this subscription
    public var eventsReceived: Int
    
    /// Whether EOSE has been received from this relay
    public var eoseReceived: Bool
    
    /// Timestamp when the subscription was sent to this relay
    public let subscriptionTime: Date
    
    /// Timestamp when EOSE was received (nil if not received)
    public var eoseTime: Date?
    
    /// Time to receive EOSE in seconds (nil if not received)
    public var timeToEose: TimeInterval? {
        guard let eoseTime = eoseTime else { return nil }
        return eoseTime.timeIntervalSince(subscriptionTime)
    }
    
    public init(relayUrl: String, appliedFilter: NDKFilter, subscriptionTime: Date = Date()) {
        self.relayUrl = relayUrl
        self.appliedFilter = appliedFilter
        self.eventsReceived = 0
        self.eoseReceived = false
        self.subscriptionTime = subscriptionTime
        self.eoseTime = nil
    }
}

// MARK: - Subscription Detail

/// Complete details for a subscription including relay-level metrics
public struct NDKSubscriptionDetail {
    /// The subscription ID
    public let subscriptionId: String
    
    /// The original filter requested by the user
    public let originalFilter: NDKFilter
    
    /// Overall metrics for the subscription
    public var metrics: NDKSubscriptionMetrics
    
    /// Relay-specific metrics keyed by relay URL
    public var relayMetrics: [String: NDKRelaySubscriptionMetrics]
    
    /// List of unique relay URLs this subscription was sent to
    public var relayUrls: [String] {
        return Array(relayMetrics.keys)
    }
    
    public init(subscriptionId: String, originalFilter: NDKFilter) {
        self.subscriptionId = subscriptionId
        self.originalFilter = originalFilter
        self.metrics = NDKSubscriptionMetrics(subscriptionId: subscriptionId)
        self.relayMetrics = [:]
    }
}

// MARK: - Closed Subscription History

/// Represents a completed subscription for historical tracking
public struct NDKClosedSubscription {
    /// The subscription ID
    public let subscriptionId: String
    
    /// The filter that was used
    public let filter: NDKFilter
    
    /// Relays the subscription was sent to
    public let relays: [String]
    
    /// Number of unique events received
    public let uniqueEventCount: Int
    
    /// Total number of events received (including duplicates)
    public let totalEventCount: Int
    
    /// Duration of the subscription in seconds
    public let duration: TimeInterval
    
    /// When the subscription was started
    public let startTime: Date
    
    /// When the subscription was closed
    public let endTime: Date
    
    /// Average events per second
    public var eventsPerSecond: Double {
        guard duration > 0 else { return 0 }
        return Double(totalEventCount) / duration
    }
    
    public init(detail: NDKSubscriptionDetail) {
        self.subscriptionId = detail.subscriptionId
        self.filter = detail.originalFilter
        self.relays = detail.relayUrls
        self.uniqueEventCount = detail.metrics.totalUniqueEvents
        self.totalEventCount = detail.metrics.totalEvents
        self.duration = detail.metrics.duration ?? 0
        self.startTime = detail.metrics.startTime
        self.endTime = detail.metrics.endTime ?? Date()
    }
}

// MARK: - Global Subscription Statistics

/// Overall statistics for all subscriptions in the NDK instance
public struct NDKSubscriptionStatistics {
    /// Number of currently active subscriptions
    public var activeSubscriptions: Int
    
    /// Total number of subscriptions created (active + closed)
    public var totalSubscriptions: Int
    
    /// Total unique events received across all subscriptions
    public var totalUniqueEvents: Int
    
    /// Total events received (including duplicates)
    public var totalEvents: Int
    
    /// Number of closed subscriptions being tracked
    public var closedSubscriptionsTracked: Int
    
    /// Average events per subscription
    public var averageEventsPerSubscription: Double {
        guard totalSubscriptions > 0 else { return 0 }
        return Double(totalEvents) / Double(totalSubscriptions)
    }
    
    public init() {
        self.activeSubscriptions = 0
        self.totalSubscriptions = 0
        self.totalUniqueEvents = 0
        self.totalEvents = 0
        self.closedSubscriptionsTracked = 0
    }
}