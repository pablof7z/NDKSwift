import Foundation

/// Indicates how a relay was added to the pool
public enum NDKRelayOrigin: Codable, Equatable, Sendable {
    /// Explicitly added by developer during NDK initialization or via addRelay()
    case explicit
    /// Discovered through outbox model (from another user's relay list)
    case outbox(authorPubkey: String) // pubkey whose relay list led to discovery
    /// Added as a fallback relay
    case fallback
    /// Added from NDKOutboxConfig for relay list queries
    case outboxConfig
}

/// Relay information for NIP-65 (relay list metadata)
///
/// This struct represents relay preferences for read/write operations,
/// as defined in NIP-65. It's typically used in kind 10002 events.
public struct NDKRelayInfo: Codable, Equatable, Sendable {
    public let url: RelayURL
    public let read: Bool
    public let write: Bool

    public init(url: RelayURL, read: Bool = true, write: Bool = true) {
        self.url = url
        self.read = read
        self.write = write
    }
}

/// Represents the current state of a relay connection
///
/// The relay progresses through these states during its lifecycle:
/// - `disconnected` → `connecting` → `connected`
/// - Any state can transition to `failed` if an error occurs
/// - `connected` → `disconnecting` → `disconnected` for graceful shutdown
public enum NDKRelayConnectionState: Equatable, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed(String) // Store error message instead of Error for Equatable

    public static func == (lhs: NDKRelayConnectionState, rhs: NDKRelayConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.disconnecting, .disconnecting):
            return true
        case let (.failed(lhsMessage), .failed(rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

/// Relay statistics
public struct NDKRelayStats: Sendable, Equatable {
    public var connectedAt: Date?
    public var lastMessageAt: Date?
    public var messagesSent: Int = 0
    public var messagesReceived: Int = 0
    public var bytesReceived: Int = 0
    public var bytesSent: Int = 0
    public var latency: TimeInterval?
    public var connectionAttempts: Int = 0
    public var successfulConnections: Int = 0

    /// Signature verification statistics
    public var signatureStats: NDKRelaySignatureStats = .init()

    public init(
        connectedAt: Date? = nil,
        lastMessageAt: Date? = nil,
        messagesSent: Int = 0,
        messagesReceived: Int = 0,
        bytesReceived: Int = 0,
        bytesSent: Int = 0,
        latency: TimeInterval? = nil,
        connectionAttempts: Int = 0,
        successfulConnections: Int = 0,
        signatureStats: NDKRelaySignatureStats = .init()
    ) {
        self.connectedAt = connectedAt
        self.lastMessageAt = lastMessageAt
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.latency = latency
        self.connectionAttempts = connectionAttempts
        self.successfulConnections = successfulConnections
        self.signatureStats = signatureStats
    }
}

/// Internal actor that manages all mutable state for NDKRelay
actor RelayStateActor {
    // Connection state
    var connectionState: NDKRelayConnectionState = .disconnected
    var stats = NDKRelayStats()
    var info: NDKRelayInformation?

    // Relay origin tracking
    var origin: NDKRelayOrigin = .explicit

    // Subscription tracking
    var activeSubscriptions: [String: NDKRelaySubscriptionInfo] = [:]

    // Observers
    var stateObservers: [@Sendable (NDKRelayConnectionState) -> Void] = []
    var fullStateObservers: [@Sendable (NDKRelay.State) -> Void] = []

    // Connection management
    var connection: NDKRelayConnection?
    var reconnectTask: Task<Void, Never>?
    var reconnectDelay: TimeInterval = 1.0
    let maxReconnectDelay: TimeInterval = NetworkConstants.timeoutResource // 5 minutes
    var manuallyDisconnected: Bool = false

    // MARK: - Connection State

    func updateConnectionState(_ newState: NDKRelayConnectionState) {
        connectionState = newState

        // Notify connection state observers
        let observers = stateObservers
        Task { @MainActor in
            for observer in observers {
                observer(newState)
            }
        }

        // Notify full state observers
        notifyFullStateObservers()
    }

    // MARK: - Full State Management

    func getFullState() -> NDKRelay.State {
        return NDKRelay.State(
            connectionState: connectionState,
            stats: stats,
            info: info,
            activeSubscriptions: getActiveSubscriptions()
        )
    }

    private func notifyFullStateObservers() {
        let snapshot = getFullState()
        let observers = fullStateObservers
        Task { @MainActor in
            for observer in observers {
                observer(snapshot)
            }
        }
    }

    func getConnectionState() -> NDKRelayConnectionState {
        return connectionState
    }

    func isConnected() -> Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    // MARK: - Connection Management

    func setConnection(_ newConnection: NDKRelayConnection?) {
        connection = newConnection
    }

    func getConnection() -> NDKRelayConnection? {
        return connection
    }

    func cancelReconnectTask() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    func scheduleReconnectTask(_ task: Task<Void, Never>) {
        cancelReconnectTask()
        reconnectTask = task
    }

    func updateReconnectDelay(_ delay: TimeInterval) {
        reconnectDelay = delay
    }

    func getReconnectDelay() -> TimeInterval {
        return reconnectDelay
    }

    func resetReconnectDelay() {
        reconnectDelay = 1.0
    }

    func setManuallyDisconnected(_ value: Bool) {
        manuallyDisconnected = value
    }

    func isManuallyDisconnected() -> Bool {
        return manuallyDisconnected
    }

    // MARK: - Origin

    func setOrigin(_ newOrigin: NDKRelayOrigin) {
        origin = newOrigin
    }

    func getOrigin() -> NDKRelayOrigin {
        return origin
    }

    // MARK: - Stats

    func updateStats(_ updater: (inout NDKRelayStats) -> Void) {
        updater(&stats)
        notifyFullStateObservers()
    }

    func getStats() -> NDKRelayStats {
        return stats
    }

    func updateSignatureStats(_ updater: (inout NDKRelaySignatureStats) -> Void) {
        updater(&stats.signatureStats)
    }

    func getSignatureStats() -> NDKRelaySignatureStats {
        return stats.signatureStats
    }

    // MARK: - Relay Information

    func setInfo(_ newInfo: NDKRelayInformation?) {
        info = newInfo
        notifyFullStateObservers()
    }

    func getInfo() -> NDKRelayInformation? {
        return info
    }


    // MARK: - Observers

    func addStateObserver(_ observer: @escaping @Sendable (NDKRelayConnectionState) -> Void) {
        stateObservers.append(observer)
    }

    func getStateObservers() -> [@Sendable (NDKRelayConnectionState) -> Void] {
        return stateObservers
    }

    // MARK: - Full State Observers

    func addFullStateObserver(_ observer: @escaping @Sendable (NDKRelay.State) -> Void) {
        fullStateObservers.append(observer)
    }

    func removeAllFullStateObservers() {
        fullStateObservers.removeAll()
    }

    // MARK: - Subscription Management

    func addSubscription(id: String, filters: [NDKFilter]) {
        activeSubscriptions[id] = NDKRelaySubscriptionInfo(id: id, filters: filters)
        notifyFullStateObservers()
    }

    func removeSubscription(id: String) {
        activeSubscriptions.removeValue(forKey: id)
        notifyFullStateObservers()
    }

    func updateSubscriptionEventCount(id: String) {
        if var sub = activeSubscriptions[id] {
            sub.eventCount += 1
            sub.lastEventAt = Date()
            activeSubscriptions[id] = sub
            // Don't notify observers for every event to avoid performance issues
        }
    }

    func getActiveSubscriptions() -> [NDKRelaySubscriptionInfo] {
        Array(activeSubscriptions.values)
    }

    func clearAllSubscriptions() {
        activeSubscriptions.removeAll()
        notifyFullStateObservers()
    }
}

/// Represents a Nostr relay that manages WebSocket connections and subscription routing
///
/// `NDKRelay` handles:
/// - WebSocket connection lifecycle with automatic reconnection
/// - Subscription management with filter merging optimization
/// - Event routing and deduplication
/// - NIP-11 relay information fetching
/// - Connection state tracking and statistics
///
/// Example usage:
/// ```swift
/// let relay = NDKRelay(url: RelayConstants.example)
/// try await relay.connect()
///
/// // Monitor connection state
/// await relay.observeConnectionState { state in
///     print("Relay state: \(state)")
/// }
/// ```
public final class NDKRelay: RelayProtocol, Hashable, Equatable, @unchecked Sendable {
    /// Relay URL
    public let url: RelayURL

    // MARK: - State Management

    /// Unified state snapshot for reactive updates
    public struct State: Equatable {
        public let connectionState: NDKRelayConnectionState
        public let stats: NDKRelayStats
        public let info: NDKRelayInformation?
        public let activeSubscriptions: [NDKRelaySubscriptionInfo]

        public init(connectionState: NDKRelayConnectionState, stats: NDKRelayStats, info: NDKRelayInformation?, activeSubscriptions: [NDKRelaySubscriptionInfo] = []) {
            self.connectionState = connectionState
            self.stats = stats
            self.info = info
            self.activeSubscriptions = activeSubscriptions
        }
    }

    /// Reference to NDK instance
    private weak var _ndk: NDK?

    /// Set the NDK instance for this relay
    public func setNDK(_ ndk: NDK?) {
        _ndk = ndk
    }

    /// Get/set the NDK instance (required by RelayProtocol)
    public var ndk: NDK? {
        get { _ndk }
        set { _ndk = newValue }
    }


    /// Internal state actor that manages all mutable state
    private let stateActor = RelayStateActor()

    /// Get the current connection (internal use only)
    internal var connection: NDKRelayConnection? {
        get async {
            await stateActor.getConnection()
        }
    }

    // MARK: - Initialization

    public init(url: RelayURL) {
        self.url = url
    }

    // MARK: - Public Properties (Async)

    /// Current connection state of the relay
    ///
    /// Use `observeConnectionState(_:)` to receive real-time updates when this changes.
    public var connectionState: NDKRelayConnectionState {
        get async {
            await stateActor.getConnectionState()
        }
    }

    /// Statistics about relay performance and usage
    ///
    /// Includes metrics like messages sent/received, bytes transferred,
    /// connection attempts, and signature verification statistics.
    public var stats: NDKRelayStats {
        get async {
            await stateActor.getStats()
        }
    }

    /// Indicates how this relay was added to the pool
    ///
    /// - `.explicit`: Added by developer during initialization or via addRelay()
    /// - `.outbox`: Discovered through another user's relay list
    /// - `.fallback`: Added as a fallback relay
    public var origin: NDKRelayOrigin {
        get async {
            await stateActor.getOrigin()
        }
    }

    /// Set the origin of this relay
    internal func setOrigin(_ origin: NDKRelayOrigin) async {
        await stateActor.setOrigin(origin)
    }

    /// Relay information fetched via NIP-11
    ///
    /// This is automatically populated after connecting to a relay that supports NIP-11.
    /// Contains relay metadata like supported NIPs, limitations, and fees.
    public var info: NDKRelayInformation? {
        get async {
            await stateActor.getInfo()
        }
    }

    /// Check if relay is currently connected
    public var isConnected: Bool {
        get async {
            await stateActor.isConnected()
        }
    }

    /// Reactive stream of relay state changes
    ///
    /// Subscribe to this stream to receive real-time updates whenever the relay's
    /// connection state, statistics, or information changes.
    ///
    /// Example usage:
    /// ```swift
    /// Task {
    ///     for await state in relay.stateStream {
    ///         print("Relay state updated: \(state.connectionState)")
    ///     }
    /// }
    /// ```
    public var stateStream: AsyncStream<State> {
        AsyncStream { continuation in
            let task = Task {
                // Register for state updates
                await self.stateActor.addFullStateObserver { state in
                    continuation.yield(state)
                }

                // Immediately emit current state
                let currentState = await self.stateActor.getFullState()
                continuation.yield(currentState)
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }


    // MARK: - Connection Management

    /// Connect to the relay
    ///
    /// Establishes a WebSocket connection to the relay. If the connection fails,
    /// the relay will automatically attempt to reconnect with exponential backoff.
    ///
    /// - Throws: `NDKError.invalidURL` if the relay URL is malformed
    /// - Throws: `NDKError.connectionFailed` if the initial connection attempt fails
    public func connect() async throws {
        let currentState = await stateActor.getConnectionState()

        switch currentState {
        case .disconnected, .failed:
            break
        default:
            return
        }

        await stateActor.updateConnectionState(.connecting)

        // Reset manual disconnection flag when explicitly connecting
        await stateActor.setManuallyDisconnected(false)

        await stateActor.updateStats {
            $0.connectionAttempts += 1
        }

        let url = try URLUtils.validateURL(normalizedURL)

        let newConnection = NDKRelayConnection(url: url)
        await stateActor.setConnection(newConnection)
        await newConnection.setDelegate(self)

        if let conn = await stateActor.getConnection() {
            try await conn.connect()
        } else {
            throw NDKError.failedTo("establish connection", message: "Connection is nil")
        }
    }

    /// Disconnect from the relay
    ///
    /// Closes the WebSocket connection and cancels any pending reconnection attempts.
    /// This is a graceful disconnect that properly cleans up resources.
    public func disconnect() async {
        let currentState = await stateActor.getConnectionState()
        guard currentState == .connected || currentState == .connecting else {
            return
        }

        await stateActor.updateConnectionState(.disconnecting)

        // Mark as manually disconnected to prevent auto-reconnection
        await stateActor.setManuallyDisconnected(true)

        // Cancel reconnection task
        await stateActor.cancelReconnectTask()

        let currentConnection = await stateActor.getConnection()
        await stateActor.setConnection(nil)

        await currentConnection?.disconnect()

        await stateActor.updateConnectionState(.disconnected)
    }

    /// Handle connection failure with exponential backoff
    private func handleConnectionFailure(_ error: Error) async {
        await stateActor.updateConnectionState(.failed(error.localizedDescription))

        // Don't auto-reconnect if the relay was manually disconnected
        let isManuallyDisconnected = await stateActor.isManuallyDisconnected()
        if isManuallyDisconnected {
            NDKLogger.log(.debug, category: .relay, "Skipping auto-reconnect for \(url) - manually disconnected")
            return
        }

        // Schedule reconnection with exponential backoff
        let delay = await stateActor.getReconnectDelay()
        let actualDelay = min(delay, stateActor.maxReconnectDelay)
        await stateActor.updateReconnectDelay(delay * 2)

        let reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(actualDelay * Double(TimeConstants.nanosecondsPerSecond)))
            if !Task.isCancelled {
                try? await self.connect()
            }
        }

        await stateActor.scheduleReconnectTask(reconnectTask)
    }

    // MARK: - Relay Information

    /// Fetch relay information (NIP-11)
    private func fetchRelayInformation() async {
        guard let url = URL(string: normalizedURL) else {
            return
        }

        guard let httpURL = URLNormalizer.convertWebSocketToHTTP(url) else {
            return
        }

        do {
            var request = URLRequest(url: httpURL)
            request.setValue(HTTPConstants.contentTypeNostrJSON, forHTTPHeaderField: HTTPConstants.headerAccept)
            request.timeoutInterval = NetworkConstants.timeoutRelayInfo
            
            let networkClient = NDKNetworkClient()
            let data = try await networkClient.fetchData(with: request)
            let relayInfo = try JSONCoding.decode(NDKRelayInformation.self, from: data)
            await stateActor.setInfo(relayInfo)
        } catch {
            // Silently fail - not all relays support NIP-11
            if ndk?.debugMode == true {
                NDKLogger.log(.warning, category: .relay, "Failed to fetch relay information from \(url): \(error)")
            }
        }
    }


    // MARK: - Message Handling

    /// Send a raw Nostr message to the relay
    ///
    /// This is a low-level method primarily used internally. Most applications should
    /// use higher-level methods like `NDK.publish()` or subscription methods instead.
    ///
    /// - Parameter message: The serialized Nostr message to send
    /// - Throws: `NDKError.connectionLost` if the relay is not connected
    public func send(_ message: String) async throws {
        let currentState = await stateActor.getConnectionState()
        guard currentState == .connected else {
            throw NDKError.connectionLost(relay: url, message: "Not connected to relay")
        }

        guard let currentConnection = await stateActor.getConnection() else {
            throw NDKError.connectionLost(relay: url, message: "Not connected to relay")
        }

        try await currentConnection.send(message)

        await stateActor.updateStats {
            $0.messagesSent += 1
            $0.bytesSent += message.count
        }
    }

    /// Handle received message
    private func handleMessage(_ message: String) async {
        await stateActor.updateStats {
            $0.messagesReceived += 1
            $0.bytesReceived += message.count
            $0.lastMessageAt = Date()
        }

        // Parse and route message
        do {
            let nostrMessage = try NostrMessage.parse(from: message)
            await routeMessage(nostrMessage)
        } catch {
            // Log parsing error but don't crash
            if ndk?.debugMode == true {
                NDKLogger.log(.warning, category: .relay, "Failed to parse message from \(url): \(error)")
            }
        }
    }

    /// Route parsed message to appropriate handlers
    private func routeMessage(_ message: NostrMessage) async {
        switch message {
        case let .event(subscriptionId, event):
            await handleEventMessage(event, subscriptionId: subscriptionId)

        case let .eose(subscriptionId):
            await handleEOSEMessage(subscriptionId: subscriptionId)

        case let .ok(eventId, accepted, message):
            await handleOKMessage(eventId: eventId, accepted: accepted, message: message)

        case let .notice(message):
            await handleNoticeMessage(message)

        case let .auth(challenge):
            await handleAuthMessage(challenge: challenge)

        case let .count(subscriptionId, count):
            await handleCountMessage(subscriptionId: subscriptionId, count: count)

        case .req, .close:
            // These are client->relay messages, shouldn't receive them
            break

        case .negOpen, .negMsg, .negClose, .negErr:
            // NIP-77 messages - route to sync handler via NDK
            NDKLogger.log(.debug, category: .relay, "Routing NIP-77 message to handler: \(message)")
            if let ndk = ndk {
                Task {
                    await ndk.processNIP77Message(message, from: self)
                }
            } else {
                NDKLogger.log(.error, category: .relay, "No NDK instance to route NIP-77 message!")
            }
        }
    }

    /// Handle EVENT message
    private func handleEventMessage(_ event: NDKEvent, subscriptionId: String?) async {
        // Update subscription event count
        if let subId = subscriptionId {
            await incrementSubscriptionEventCount(id: subId)
        }

        // Route to subscription manager via NDK only
        if let ndk = ndk, let subId = subscriptionId {
            Task {
                await ndk.processEvent(event, subscriptionId: subId, from: self)
            }
        } else {
            NDKLogger.log(.warning, category: .relay, "⚠️ Cannot route event - ndk: \(ndk != nil), subId: \(subscriptionId != nil)")
        }
    }

    /// Handle EOSE message
    private func handleEOSEMessage(subscriptionId: String) async {
        // Route to subscription manager via NDK only
        if let ndk = ndk {
            ndk.processEOSE(subscriptionId: subscriptionId, from: self)
        } else {
            NDKLogger.log(.warning, category: .relay, "⚠️ Cannot process EOSE - no NDK instance")
        }
    }

    /// Handle OK message (publish result)
    private func handleOKMessage(eventId: EventID, accepted: Bool, message: String?) async {
        if ndk?.debugMode == true {
            let status = accepted ? "✅ Accepted" : "❌ Rejected"
            let msg = message.map { ": \($0)" } ?? ""
            NDKLogger.log(.info, category: .relay, "\(status) event \(eventId) at \(url)\(msg)")
        }

        // Notify NDK about OK message
        if let ndk = ndk {
            Task {
                await ndk.processOKMessage(eventId: eventId, accepted: accepted, message: message, from: self)
            }
        }
    }

    /// Handle NOTICE message
    private func handleNoticeMessage(_ message: String) async {
        if ndk?.debugMode == true {
            NDKLogger.log(.info, category: .relay, "Notice from \(url): \(message)")
        }

        // Notify NDK about notice message
        ndk?.processNotice(message: message, from: self)
    }

    /// Handle AUTH message
    private func handleAuthMessage(challenge: String) async {
        if ndk?.debugMode == true {
            NDKLogger.log(.info, category: .relay, "Auth challenge from \(url): \(challenge)")
        }

        // Notify NDK about auth challenge - implementation requires signer
        await ndk?.handleAuthChallenge(challenge: challenge, from: self)
    }

    /// Handle COUNT message
    private func handleCountMessage(subscriptionId: String, count: Int) async {
        if ndk?.debugMode == true {
            NDKLogger.log(.info, category: .relay, "Count for subscription \(subscriptionId): \(count)")
        }

        // Route to subscription manager via NDK only
        ndk?.processCount(subscriptionId: subscriptionId, count: count, from: self)
    }

    // MARK: - State Management

    /// Observe connection state changes
    ///
    /// Registers a callback that will be invoked whenever the relay's connection state changes.
    /// The observer is immediately called with the current state upon registration.
    ///
    /// - Parameter observer: A sendable closure that receives connection state updates
    ///
    /// Example:
    /// ```swift
    /// await relay.observeConnectionState { state in
    ///     switch state {
    ///     case .connected:
    ///         print("Connected to relay")
    ///     case .failed(let error):
    ///         print("Connection failed: \(error)")
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    public func observeConnectionState(_ observer: @escaping @Sendable (NDKRelayConnectionState) -> Void) async {
        await stateActor.addStateObserver(observer)
        // Immediately call with current state
        let currentState = await stateActor.getConnectionState()
        observer(currentState)
    }

    // MARK: - Utilities

    /// Get normalized relay URL
    public var normalizedURL: String {
        // Use the URLNormalizer for consistent normalization
        return URLNormalizer.tryNormalizeRelayUrl(url) ?? url
    }
}

// MARK: - NDKRelayConnectionDelegate

extension NDKRelay: NDKRelayConnectionDelegate {
    public func relayConnectionDidConnect(_: NDKRelayConnection) {
        Task {
            await stateActor.updateStats {
                $0.connectedAt = Date()
                $0.successfulConnections += 1
            }

            await stateActor.resetReconnectDelay()
            await stateActor.updateConnectionState(.connected)

            // Fetch relay information
            await fetchRelayInformation()
            // Note: Subscription replay is handled by InternalSubscriptionManager
        }
    }

    public func relayConnectionDidDisconnect(_: NDKRelayConnection, error: Error?) {
        Task {
            // Clear all subscriptions when disconnected
            await stateActor.clearAllSubscriptions()

            if let error = error {
                await handleConnectionFailure(error)
            } else {
                await stateActor.updateConnectionState(.disconnected)
            }
        }
    }

    public func relayConnection(_: NDKRelayConnection, didReceiveMessage message: NostrMessage) {
        Task {
            await handleNostrMessage(message)
        }
    }

    private func handleNostrMessage(_ message: NostrMessage) async {
        await stateActor.updateStats { $0.messagesReceived += 1 }

        // Use the same routing as routeMessage to avoid duplication
        await routeMessage(message)
    }
}

public extension NDKRelay {
    // MARK: - Publishing and Fetching

    /// Publish an event and wait for response
    func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?) {
        guard let connection = await connection else {
            throw NDKError.connectionLost(relay: url, message: "No connection available")
        }

        do {
            let success = try await connection.publishEvent(event)
            return (success: success, message: nil)
        } catch let error as NDKError {
            if case let .publishFailed(_, message) = error {
                NDKLogger.log(.warning, category: .relay, "Event \(event.id) rejected by relay \(url): \(message)")
                return (success: false, message: message)
            } else {
                throw error
            }
        }
    }


    // MARK: - Signature Statistics

    /// Update signature verification statistics in a thread-safe manner
    func updateSignatureStats(_ updater: @Sendable (inout NDKRelaySignatureStats) -> Void) async {
        await stateActor.updateSignatureStats(updater)
    }

    /// Get a copy of the current signature statistics
    func getSignatureStats() async -> NDKRelaySignatureStats {
        return await stateActor.getSignatureStats()
    }

    // MARK: - Subscription Management

    /// Get currently active subscriptions on this relay
    var activeSubscriptions: [NDKRelaySubscriptionInfo] {
        get async {
            await stateActor.getActiveSubscriptions()
        }
    }

    /// Track a new subscription on this relay (internal use)
    internal func trackSubscription(id: String, filters: [NDKFilter]) async {
        await stateActor.addSubscription(id: id, filters: filters)
    }

    /// Stop tracking a subscription (internal use)
    internal func untrackSubscription(id: String) async {
        await stateActor.removeSubscription(id: id)
    }

    /// Update event count for a subscription (internal use)
    internal func incrementSubscriptionEventCount(id: String) async {
        await stateActor.updateSubscriptionEventCount(id: id)
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: NDKRelay, rhs: NDKRelay) -> Bool {
        return lhs.normalizedURL == rhs.normalizedURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedURL)
    }
}

/// Relay information from NIP-11
public struct NDKRelayInformation: Codable, Sendable, Equatable {
    public let name: String?
    public let description: String?
    public let banner: String?
    public let icon: String?
    public let pubkey: PublicKey?
    public let contact: String?
    public let supportedNips: [Int]?
    public let software: String?
    public let version: String?
    public let limitation: RelayLimitation?
    public let retention: [RelayRetention]?
    public let relayCountries: [String]?
    public let languageTags: [String]?
    public let tags: [String]?
    public let postingPolicy: String?
    public let paymentsUrl: String?
    public let fees: RelayFees?

    private enum CodingKeys: String, CodingKey {
        case name, description, banner, icon, pubkey, contact
        case supportedNips = "supported_nips"
        case software, version, limitation, retention
        case relayCountries = "relay_countries"
        case languageTags = "language_tags"
        case tags
        case postingPolicy = "posting_policy"
        case paymentsUrl = "payments_url"
        case fees
    }
}

/// Relay limitations
public struct RelayLimitation: Codable, Sendable, Equatable {
    public let maxMessageLength: Int?
    public let maxSubscriptions: Int?
    public let maxFilters: Int?
    public let maxLimit: Int?
    public let maxSubidLength: Int?
    public let maxEventTags: Int?
    public let maxContentLength: Int?
    public let minPowDifficulty: Int?
    public let authRequired: Bool?
    public let paymentRequired: Bool?
    public let restrictedWrites: Bool?

    private enum CodingKeys: String, CodingKey {
        case maxMessageLength = "max_message_length"
        case maxSubscriptions = "max_subscriptions"
        case maxFilters = "max_filters"
        case maxLimit = "max_limit"
        case maxSubidLength = "max_subid_length"
        case maxEventTags = "max_event_tags"
        case maxContentLength = "max_content_length"
        case minPowDifficulty = "min_pow_difficulty"
        case authRequired = "auth_required"
        case paymentRequired = "payment_required"
        case restrictedWrites = "restricted_writes"
    }
}

/// Relay retention policy
public struct RelayRetention: Codable, Sendable, Equatable {
    public let kinds: [Int]?
    public let time: Int?
    public let count: Int?
}

/// Relay fee structure
public struct RelayFees: Codable, Sendable, Equatable {
    public let admission: [RelayFee]?
    public let publication: [RelayFee]?
}

/// Individual relay fee
public struct RelayFee: Codable, Sendable, Equatable {
    public let amount: Int
    public let unit: String
    public let period: Int?
    public let kinds: [Int]?
}

/// Subscription info tracked by relay
public struct NDKRelaySubscriptionInfo: Sendable, Equatable {
    public let id: String
    public let filters: [NDKFilter]
    public let createdAt: Date
    public var eventCount: Int
    public var lastEventAt: Date?

    public init(id: String, filters: [NDKFilter], createdAt: Date = Date()) {
        self.id = id
        self.filters = filters
        self.createdAt = createdAt
        self.eventCount = 0
        self.lastEventAt = nil
    }
}
