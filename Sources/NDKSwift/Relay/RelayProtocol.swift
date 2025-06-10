import Foundation

/// Protocol defining the interface for Nostr relays
/// This allows for both real relay implementations and test mocks
public protocol RelayProtocol: AnyObject {
    /// The relay's URL
    var url: String { get }
    
    /// Current connection state
    var connectionState: NDKRelayConnectionState { get }
    
    /// Reference to NDK instance
    var ndk: NDK? { get set }
    
    /// Active subscriptions on this relay
    var activeSubscriptions: [NDKSubscription] { get }
    
    // Subscription manager removed from protocol - implementation specific
    
    /// Connect to the relay
    func connect() async throws
    
    /// Disconnect from the relay
    func disconnect() async
    
    /// Send a message to the relay
    func send(_ message: String) async throws
    
    /// Add a subscription
    func addSubscription(_ subscription: NDKSubscription)
    
    /// Remove a subscription by ID
    func removeSubscription(byId id: String)
    
    /// Get signature verification statistics
    func getSignatureStats() -> NDKRelaySignatureStats
    
    /// Update signature verification statistics
    func updateSignatureStats(_ updater: (inout NDKRelaySignatureStats) -> Void)
    
    /// Observe connection state changes
    func observeConnectionState(_ observer: @escaping (NDKRelayConnectionState) -> Void)
}

/// Extension to provide default implementations
public extension RelayProtocol {
    /// Default implementation for adding subscriptions
    func addSubscription(_ subscription: NDKSubscription) {
        // Default implementation - can be overridden
    }
    
    /// Default implementation for removing subscriptions
    func removeSubscription(byId id: String) {
        // Default implementation - can be overridden
    }
}