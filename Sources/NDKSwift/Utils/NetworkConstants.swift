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
    
    // Connection Parameters
    public static let maxReconnectAttempts = 3
    public static let reconnectDelay: TimeInterval = 2.0
    
    // Subscription Parameters
    public static let eoseTimeoutRatio = 0.5 // 50% of relays for timeout
}