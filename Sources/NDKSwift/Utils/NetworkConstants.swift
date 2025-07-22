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
}