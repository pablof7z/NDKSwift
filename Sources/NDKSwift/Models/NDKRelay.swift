import Foundation

/// Relay information for NIP-65
public struct NDKRelayInfo: Codable, Equatable {
    public let url: RelayURL
    public let read: Bool
    public let write: Bool

    public init(url: RelayURL, read: Bool = true, write: Bool = true) {
        self.url = url
        self.read = read
        self.write = write
    }
}

/// Relay connection state
public enum NDKRelayConnectionState: Equatable {
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
public struct NDKRelayStats {
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
}

/// Represents a Nostr relay
public final class NDKRelay: Hashable, Equatable {
    /// Relay URL
    public let url: RelayURL

    /// Current connection state
    public private(set) var connectionState: NDKRelayConnectionState = .disconnected

    /// Relay statistics
    public private(set) var stats = NDKRelayStats()

    /// Relay information (NIP-11)
    public private(set) var info: NDKRelayInformation?

    /// Active subscriptions on this relay
    private var subscriptions: [String: NDKSubscription] = [:]

    /// Connection state observers
    private var stateObservers: [(NDKRelayConnectionState) -> Void] = []

    /// Reference to NDK instance
    public weak var ndk: NDK?

    /// WebSocket connection
    private var connection: NDKRelayConnection?

    /// Reconnection timer
    private var reconnectTimer: Timer?

    /// Current reconnection delay
    private var reconnectDelay: TimeInterval = 1.0

    /// Maximum reconnection delay
    private let maxReconnectDelay: TimeInterval = 300.0 // 5 minutes

    /// Subscription manager for this relay
    public lazy var subscriptionManager = NDKRelaySubscriptionManager(relay: self)

    /// Thread-safe access to statistics
    private let statsLock = NSLock()

    /// Thread-safe access to subscriptions
    private let subscriptionsLock = NSLock()

    // MARK: - Initialization

    public init(url: RelayURL) {
        self.url = url
    }

    // MARK: - Connection Management

    /// Connect to the relay
    public func connect() async throws {
        switch connectionState {
        case .disconnected, .failed:
            break
        default:
            return
        }

        updateConnectionState(.connecting)
        stats.connectionAttempts += 1

        guard let url = URL(string: normalizedURL) else {
            throw NDKError.relayConnectionFailed("Invalid URL: \(normalizedURL)")
        }

        connection = NDKRelayConnection(url: url)
        connection?.delegate = self
        connection?.connect()
    }

    /// Disconnect from the relay
    public func disconnect() async {
        guard connectionState == .connected || connectionState == .connecting else {
            return
        }

        updateConnectionState(.disconnecting)

        // Cancel reconnection timer
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        connection?.disconnect()
        connection = nil

        updateConnectionState(.disconnected)
    }

    /// Handle connection failure with exponential backoff
    private func handleConnectionFailure(_ error: Error) {
        updateConnectionState(.failed(error.localizedDescription))

        // Schedule reconnection with exponential backoff
        let delay = min(reconnectDelay, maxReconnectDelay)
        reconnectDelay *= 2

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { [weak self] in
                try? await self?.connect()
            }
        }
    }

    // MARK: - Relay Information

    /// Fetch relay information (NIP-11)
    private func fetchRelayInformation() async {
        // TODO: Implement NIP-11 relay information fetching
        // GET request to relay URL with Accept: application/nostr+json
    }

    // MARK: - Subscription Management

    /// Add a subscription to this relay
    public func addSubscription(_ subscription: NDKSubscription) {
        subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }
        subscriptions[subscription.id] = subscription
    }

    /// Remove a subscription from this relay
    public func removeSubscription(_ subscription: NDKSubscription) {
        subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }
        subscriptions.removeValue(forKey: subscription.id)
    }

    /// Get all active subscriptions
    public var activeSubscriptions: [NDKSubscription] {
        subscriptionsLock.lock()
        defer { subscriptionsLock.unlock() }
        return Array(subscriptions.values)
    }

    // MARK: - Message Handling

    /// Send a message to the relay
    public func send(_ message: String) async throws {
        guard connectionState == .connected, let connection = connection else {
            throw NDKError.relayConnectionFailed("Not connected to relay")
        }

        try await connection.send(message)
        stats.messagesSent += 1
        stats.bytesSent += message.count
    }

    /// Handle received message
    private func handleMessage(_ message: String) {
        stats.messagesReceived += 1
        stats.bytesReceived += message.count
        stats.lastMessageAt = Date()

        // Parse and route message
        do {
            let nostrMessage = try NostrMessage.parse(from: message)
            routeMessage(nostrMessage)
        } catch {
            // Log parsing error but don't crash
            if ndk?.debugMode == true {
                print("⚠️ Failed to parse message from \(url): \(error)")
            }
        }
    }

    /// Route parsed message to appropriate handlers
    private func routeMessage(_ message: NostrMessage) {
        switch message {
        case let .event(subscriptionId, event):
            handleEventMessage(event, subscriptionId: subscriptionId)

        case let .eose(subscriptionId):
            handleEOSEMessage(subscriptionId: subscriptionId)

        case let .ok(eventId, accepted, message):
            handleOKMessage(eventId: eventId, accepted: accepted, message: message)

        case let .notice(message):
            handleNoticeMessage(message)

        case let .auth(challenge):
            handleAuthMessage(challenge: challenge)

        case let .count(subscriptionId, count):
            handleCountMessage(subscriptionId: subscriptionId, count: count)

        case .req, .close:
            // These are client->relay messages, shouldn't receive them
            break
        }
    }

    /// Handle EVENT message
    private func handleEventMessage(_ event: NDKEvent, subscriptionId: String?) {
        // Set relay reference on event
        event.setRelay(self)

        // Route to subscription manager via NDK
        ndk?.processEvent(event, from: self)

        // Also notify local subscriptions for backward compatibility
        if let subscriptionId = subscriptionId {
            subscriptionsLock.lock()
            let subscription = subscriptions[subscriptionId]
            subscriptionsLock.unlock()
            
            if let subscription = subscription {
                subscription.handleEvent(event, fromRelay: self)
            }
        }
    }

    /// Handle EOSE message
    private func handleEOSEMessage(subscriptionId: String) {
        // Route to subscription manager via NDK
        ndk?.processEOSE(subscriptionId: subscriptionId, from: self)

        // Also notify local subscription for backward compatibility
        subscriptionsLock.lock()
        let subscription = subscriptions[subscriptionId]
        subscriptionsLock.unlock()
        
        if let subscription = subscription {
            subscription.handleEOSE(fromRelay: self)
        }
    }

    /// Handle OK message (publish result)
    private func handleOKMessage(eventId: EventID, accepted: Bool, message: String?) {
        if ndk?.debugMode == true {
            let status = accepted ? "✅ Accepted" : "❌ Rejected"
            let msg = message.map { ": \($0)" } ?? ""
            print("\(status) event \(eventId) at \(url)\(msg)")
        }

        // Notify NDK about OK message
        ndk?.processOKMessage(eventId: eventId, accepted: accepted, message: message, from: self)
    }

    /// Handle NOTICE message
    private func handleNoticeMessage(_ message: String) {
        if ndk?.debugMode == true {
            print("📢 Notice from \(url): \(message)")
        }

        // TODO: Emit notice event for listeners
    }

    /// Handle AUTH message
    private func handleAuthMessage(challenge: String) {
        if ndk?.debugMode == true {
            print("🔐 Auth challenge from \(url): \(challenge)")
        }

        // TODO: Handle NIP-42 authentication
    }

    /// Handle COUNT message
    private func handleCountMessage(subscriptionId: String, count: Int) {
        if ndk?.debugMode == true {
            print("🔢 Count for subscription \(subscriptionId): \(count)")
        }

        // TODO: Handle NIP-45 count results
    }

    // MARK: - State Management

    /// Update connection state and notify observers
    private func updateConnectionState(_ newState: NDKRelayConnectionState) {
        connectionState = newState

        // Notify observers
        for observer in stateObservers {
            observer(newState)
        }
    }

    /// Observe connection state changes
    public func observeConnectionState(_ observer: @escaping (NDKRelayConnectionState) -> Void) {
        stateObservers.append(observer)
        // Immediately call with current state
        observer(connectionState)
    }

    // MARK: - Utilities

    /// Check if relay is currently connected
    public var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    /// Get normalized relay URL
    public var normalizedURL: String {
        // Use the URLNormalizer for consistent normalization
        return URLNormalizer.tryNormalizeRelayUrl(url) ?? url
    }
}

// MARK: - NDKRelayConnectionDelegate

extension NDKRelay: NDKRelayConnectionDelegate {
    public func relayConnectionDidConnect(_: NDKRelayConnection) {
        stats.connectedAt = Date()
        stats.successfulConnections += 1
        reconnectDelay = 1.0 // Reset delay on successful connection

        updateConnectionState(.connected)

        // Fetch relay information and replay subscriptions
        Task {
            await fetchRelayInformation()
            // Replay any waiting subscriptions
            await subscriptionManager.executePendingSubscriptions()
        }
    }

    public func relayConnectionDidDisconnect(_: NDKRelayConnection, error: Error?) {
        if let error = error {
            handleConnectionFailure(error)
        } else {
            updateConnectionState(.disconnected)
        }
    }

    public func relayConnection(_: NDKRelayConnection, didReceiveMessage message: NostrMessage) {
        handleNostrMessage(message)
    }

    private func handleNostrMessage(_ message: NostrMessage) {
        stats.messagesReceived += 1

        switch message {
        case let .event(subscriptionId, event):
            // Route through subscription manager first
            Task {
                await subscriptionManager.handleEvent(event, relaySubscriptionId: subscriptionId)
            }

            // Also handle legacy subscriptions for backward compatibility
            if let subId = subscriptionId {
                subscriptionsLock.lock()
                let subscription = subscriptions[subId]
                subscriptionsLock.unlock()
                
                if let subscription = subscription {
                    subscription.handleEvent(event, fromRelay: self)
                }
            }

        case let .eose(subscriptionId):
            // Route through subscription manager
            Task {
                await subscriptionManager.handleEOSE(relaySubscriptionId: subscriptionId)
            }

            // Also handle legacy subscriptions
            subscriptionsLock.lock()
            let subscription = subscriptions[subscriptionId]
            subscriptionsLock.unlock()
            
            if let subscription = subscription {
                subscription.handleEOSE(fromRelay: self)
            }

        case let .ok(eventId, accepted, errorMessage):
            // Handle event publishing confirmation
            handleOKMessage(eventId: eventId, accepted: accepted, message: errorMessage)

        case let .notice(noticeMessage):
            print("Notice from \(url): \(noticeMessage)")

        case let .auth(challenge):
            // Handle authentication challenge
            handleAuthChallenge(challenge)

        default:
            // Handle other message types as needed
            break
        }
    }

    private func handleAuthChallenge(_ challenge: String) {
        // TODO: Implement NIP-42 authentication
        print("Auth challenge from \(url): \(challenge)")
    }
}

public extension NDKRelay {
    // MARK: - Signature Statistics

    /// Update signature verification statistics in a thread-safe manner
    func updateSignatureStats(_ update: (inout NDKRelaySignatureStats) -> Void) {
        statsLock.lock()
        defer { statsLock.unlock() }
        update(&stats.signatureStats)
    }

    /// Get a copy of the current signature statistics
    func getSignatureStats() -> NDKRelaySignatureStats {
        statsLock.lock()
        defer { statsLock.unlock() }
        return stats.signatureStats
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
public struct NDKRelayInformation: Codable {
    public let name: String?
    public let description: String?
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
        case name, description, pubkey, contact
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
public struct RelayLimitation: Codable {
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
public struct RelayRetention: Codable {
    public let kinds: [Int]?
    public let time: Int?
    public let count: Int?
}

/// Relay fee structure
public struct RelayFees: Codable {
    public let admission: [RelayFee]?
    public let publication: [RelayFee]?
}

/// Individual relay fee
public struct RelayFee: Codable {
    public let amount: Int
    public let unit: String
    public let period: Int?
    public let kinds: [Int]?
}
