import Foundation

/// Network-related constants for consistent usage across the codebase
public enum NetworkConstants {
    // Timeout Values (in seconds)
    public static let timeoutRelayInfo: TimeInterval = 10
    public static let timeoutRelayConnection: TimeInterval = 10
    public static let timeoutRPCRequest: TimeInterval = 30
    public static let timeoutStandardRequest: TimeInterval = 30
    public static let timeoutSubscription: TimeInterval = 5
    public static let timeoutResource: TimeInterval = 300
    public static let timeoutWalletDeposit: TimeInterval = 600
    
    // Data Collection Timeouts (for collect() operations)
    public static let timeoutDataCollectionShort: TimeInterval = 2.0  // For wallet operations
    public static let timeoutDataCollectionMedium: TimeInterval = 3.0 // For relay/contact lists
    public static let timeoutDataCollectionLong: TimeInterval = 5.0   // For zap operations
    public static let timeoutDataCollectionSync: TimeInterval = 30.0  // For sync operations
    
    // Connection Parameters
    public static let maxReconnectAttempts = 3
    public static let reconnectDelay: TimeInterval = 2.0
    
    // Subscription Parameters
    public static let eoseTimeoutRatio = 0.5 // 50% of relays for timeout
    
    // Ping/Health Check
    public static let timeoutPing: TimeInterval = 3.0
    
    // Cache Parameters
    public static let tombstoneTTL: TimeInterval = 600 // 10 minutes
    public static let cleanupInterval: TimeInterval = 300 // 5 minutes
    public static let defaultCacheCapacity = 1000
    public static let profileCacheSize = 1000
    public static let nip05CacheCapacity = 1000
    public static let domainRateLimiterCapacity = 500
    public static let outboxTrackerCapacity = 500
    
    // Retry Configuration
    public static let retryBaseDelay: TimeInterval = 5.0
    public static let retryDelayIncrement: TimeInterval = 5.0
    public static let maxMintRetries = 6
    public static let maxRetryDelay: TimeInterval = 30.0
    
    // NIP-05 Configuration
    public static let nip05RateLimit: TimeInterval = 360 // 6 minutes between requests
    public static let maxNIP05ResponseSize = 1_048_576 // 1MB
    
    // Filter Limits
    public static let maxFilterLimit = 1000
    
    // Data Collection
    public static let dataGroupingWindow: TimeInterval = 0.1 // 100ms
    
    // Deposit Monitoring
    public static let depositCheckBaseInterval: TimeInterval = 120.0 // 2 minutes
    public static let depositCheckMaxInterval: TimeInterval = 7200.0 // 2 hours
}