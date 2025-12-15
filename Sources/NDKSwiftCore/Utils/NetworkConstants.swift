import Foundation

/// Network-related constants for consistent usage across the codebase
public enum NetworkConstants {
    // Timeout Values (in seconds)
    /// Timeout for fetching relay information (NIP-11) - balanced for slow connections
    public static let timeoutRelayInfo: TimeInterval = 10
    /// Initial connection timeout for relay websockets - allows for handshake completion
    public static let timeoutRelayConnection: TimeInterval = 10
    /// RPC requests may involve multiple round trips - extended timeout
    public static let timeoutRPCRequest: TimeInterval = 30
    /// Standard HTTP request timeout - generous for mobile networks
    public static let timeoutStandardRequest: TimeInterval = 30
    /// Subscription timeout for receiving initial data - short to detect dead subscriptions
    public static let timeoutSubscription: TimeInterval = 5
    /// Large resources (images, files) need extended timeout for slow connections
    public static let timeoutResource: TimeInterval = 5 * TimeConstants.minute // 5 minutes
    /// Wallet deposits may involve multiple chain confirmations
    public static let timeoutWalletDeposit: TimeInterval = 10 * TimeConstants.minute // 10 minutes

    // Data Collection Timeouts (for collect() operations)
    public static let timeoutDataCollectionShort: TimeInterval = 2.0 // For wallet operations
    public static let timeoutDataCollectionMedium: TimeInterval = 3.0 // For relay/contact lists
    public static let timeoutDataCollectionLong: TimeInterval = 5.0 // For zap operations
    public static let timeoutDataCollectionSync: TimeInterval = 30.0 // For sync operations

    // Connection Parameters
    /// Maximum reconnect attempts before giving up - prevents infinite retry loops
    public static let maxReconnectAttempts = 3
    /// Delay between reconnection attempts - prevents hammering servers
    public static let reconnectDelay: TimeInterval = 2.0

    // Subscription Parameters
    /// Ratio of relays that must send EOSE before considering the subscription complete
    public static let eoseTimeoutRatio = 0.5 // 50% of relays for timeout

    // Ping/Health Check
    public static let timeoutPing: TimeInterval = 3.0

    // Cache Parameters
    /// TTL for tombstones (deletion markers) - prevents re-adding deleted items too soon
    public static let tombstoneTTL: TimeInterval = 10 * TimeConstants.minute // 10 minutes
    /// Interval for cache cleanup tasks - balances performance vs memory usage
    public static let cleanupInterval: TimeInterval = 5 * TimeConstants.minute // 5 minutes
    /// Default capacity for general-purpose caches - prevents unbounded memory growth
    public static let defaultCacheCapacity = 1000
    /// Profile cache size - based on typical social graph sizes
    public static let profileCacheSize = 1000
    /// NIP-05 verification cache - reduces redundant network requests
    public static let nip05CacheCapacity = 1000
    /// Rate limiter capacity for NIP-05 domains - prevents DoS attacks
    public static let domainRateLimiterCapacity = 500
    /// Outbox tracker capacity - tracks recent relay selections
    public static let outboxTrackerCapacity = 500

    // Retry Configuration
    public static let retryBaseDelay: TimeInterval = 5.0
    public static let retryDelayIncrement: TimeInterval = 5.0
    public static let maxMintRetries = 6
    public static let maxRetryDelay: TimeInterval = 30.0

    // NIP-05 Configuration
    /// Minimum time between NIP-05 verifications for same address - prevents abuse
    public static let nip05RateLimit: TimeInterval = 6 * TimeConstants.minute // 6 minutes between requests
    /// Maximum allowed response size for NIP-05 queries - prevents DoS via large responses
    public static let maxNIP05ResponseSize = 1_048_576 // 1MB

    // Filter Limits
    public static let maxFilterLimit = 1000

    // Data Collection
    public static let dataGroupingWindow: TimeInterval = 0.1 // 100ms

    // Deposit Monitoring
    public static let depositCheckBaseInterval: TimeInterval = 2 * TimeConstants.minute // 2 minutes
    public static let depositCheckMaxInterval: TimeInterval = 2 * TimeConstants.hour // 2 hours
}
