/// Protocol defining the interface for Nostr relays
/// This allows for both real relay implementations and test mocks
public protocol RelayProtocol: AnyObject, Sendable {
    /// The relay's URL
    var url: String { get }

    /// Current connection state
    var connectionState: NDKRelayConnectionState { get async }

    /// Reference to NDK instance
    var ndk: NDK? { get set }

    /// Connect to the relay
    func connect() async throws

    /// Disconnect from the relay
    func disconnect() async

    /// Send a message to the relay
    func send(_ message: String) async throws

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
}

