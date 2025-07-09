import Foundation

/// Protocol defining the interface for Nostr relays
/// This allows for both real relay implementations and test mocks
public protocol RelayProtocol: AnyObject, Sendable {
    /// The relay's URL
    var url: String { get }
    
    /// Current connection state
    var connectionState: NDKRelayConnectionState { get async }
    
    /// Reference to NDK instance
    var ndk: NDK? { get set }
    
    /// Active subscriptions on this relay
    var activeSubscriptions: [NDKSubscription] { get async }
    
    // Subscription manager removed from protocol - implementation specific
    
    /// Connect to the relay
    func connect() async throws
    
    /// Disconnect from the relay
    func disconnect() async
    
    /// Send a message to the relay
    func send(_ message: String) async throws
    
    /// Add a subscription
    func addSubscription(_ subscription: NDKSubscription) async
    
    /// Remove a subscription by ID
    func removeSubscription(byId id: String) async
    
    /// Get signature verification statistics
    func getSignatureStats() async -> NDKRelaySignatureStats
    
    /// Update signature verification statistics
    func updateSignatureStats(_ updater: @Sendable (inout NDKRelaySignatureStats) -> Void) async
    
    /// Observe connection state changes
    func observeConnectionState(_ observer: @escaping @Sendable (NDKRelayConnectionState) -> Void) async
}

/// Extension to provide default implementations
public extension RelayProtocol {
    /// Default implementation for adding subscriptions
    func addSubscription(_ subscription: NDKSubscription) async {
        // Default implementation - can be overridden
    }
    
    /// Default implementation for removing subscriptions
    func removeSubscription(byId id: String) async {
        // Default implementation - can be overridden
    }
}
