import Foundation

/// Internal constants for outbox behavior - not user configurable
enum OutboxConstants {
    // MARK: - Publishing
    
    /// Number of relays per author for publishing (matches ndk-core behavior)
    static let relaysPerAuthor = 2
    
    /// Minimum number of relays to publish to
    static let minPublishRelays = 2
    
    /// Maximum number of relays to publish to (soft limit, can be exceeded based on author count)
    static let maxPublishRelays = 30
    
    /// Minimum number of successful publishes required
    static let minSuccessfulPublishes = 1
    
    /// Number of retry attempts for temporary failures
    static let publishRetries = 3
    
    /// Initial backoff interval for retries
    static let initialBackoffInterval: TimeInterval = 1.0
    
    /// Backoff multiplier for exponential backoff
    static let backoffMultiplier: Double = 2.0
    
    /// Always include user read relays when publishing to <10 p-tags
    static let includeUserReadRelaysForPublish = true
    
    /// Always republish when relay info is discovered
    static let republishOnRelayDiscovery = true
    
    /// Timeout for waiting for relay discovery
    static let relayDiscoveryTimeout: TimeInterval = 5.0
    
    // MARK: - Fetching
    
    /// Number of relays per author for fetching
    static let relaysPerAuthorForFetching = 2
    
    /// Minimum number of relays to fetch from
    static let minFetchRelays = 2
    
    /// Maximum number of relays to fetch from (soft limit, can be exceeded based on author count)
    static let maxFetchRelays = 50
    
    /// Prefer write relays if no read relays found
    static let preferWriteRelaysIfNoRead = true
    
    /// Always deduplicate events
    static let deduplicateEvents = true
    
    // MARK: - Subscriptions
    
    /// Always auto-reconnect subscriptions
    static let autoReconnect = true
    
    /// Reconnect delay for subscriptions
    static let reconnectDelay: TimeInterval = NetworkConstants.timeoutSubscription
}