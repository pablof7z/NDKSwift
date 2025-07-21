/// Protocol defining the interface for Nostr relays
/// This allows for both real relay implementations and test mocks
public protocol RelayProtocol: AnyObject, Sendable {
    /// The relay's URL
    var url: String { get }
    
    /// Current connection state
    var connectionState: NDKRelayConnectionState { get async }
    
    /// Reference to NDK instance
    var ndk: NDK? { get set }
    
    /// Active subscription IDs on this relay
    var activeSubscriptionIds: [String] { get async }
    
    // Subscription manager removed from protocol - implementation specific
    
    /// Connect to the relay
    func connect() async throws
    
    /// Disconnect from the relay
    func disconnect() async
    
    /// Send a message to the relay
    func send(_ message: String) async throws
    
    /// Add a subscription (internal use only)
    func addSubscriptionId(_ subscriptionId: String) async
    
    /// Remove a subscription by ID
    func removeSubscription(byId id: String) async
    
    /// Get signature verification statistics
    func getSignatureStats() async -> NDKRelaySignatureStats
    
    /// Update signature verification statistics
    func updateSignatureStats(_ updater: @Sendable (inout NDKRelaySignatureStats) -> Void) async
    
    /// Observe connection state changes
    func observeConnectionState(_ observer: @escaping @Sendable (NDKRelayConnectionState) -> Void) async
    
    /// Publish an event to the relay and wait for response
    /// - Parameter event: The event to publish
    /// - Returns: A tuple containing success status and optional message from the relay
    /// - Throws: If the relay is not connected or other network errors occur
    func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?)
    
    /// Fetch events from the relay matching the given filter
    /// 
    /// ⚠️ **WARNING**: This blocks until EOSE. See NDK.fetchEvents for guidance on when to use this.
    /// Consider using subscriptions for most use cases instead.
    /// 
    /// - Parameter filter: The filter to match events against
    /// - Returns: Array of events matching the filter
    /// - Throws: If the relay is not connected or other network errors occur
    func fetchEvents(filter: NDKFilter) async throws -> [NDKEvent]
}

