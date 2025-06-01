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
        case (.failed(let lhsMessage), .failed(let rhsMessage)):
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
    
    /// WebSocket connection (placeholder for now)
    private var webSocket: Any?
    
    /// Reconnection timer
    private var reconnectTimer: Timer?
    
    /// Current reconnection delay
    private var reconnectDelay: TimeInterval = 1.0
    
    /// Maximum reconnection delay
    private let maxReconnectDelay: TimeInterval = 300.0 // 5 minutes
    
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
        
        // TODO: Implement actual WebSocket connection
        // For now, simulate connection
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        stats.connectedAt = Date()
        stats.successfulConnections += 1
        reconnectDelay = 1.0 // Reset delay on successful connection
        
        updateConnectionState(.connected)
        
        // Fetch relay information
        Task {
            await fetchRelayInformation()
        }
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
        
        // TODO: Close WebSocket connection
        
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
        subscriptions[subscription.id] = subscription
    }
    
    /// Remove a subscription from this relay
    public func removeSubscription(_ subscription: NDKSubscription) {
        subscriptions.removeValue(forKey: subscription.id)
    }
    
    /// Get all active subscriptions
    public var activeSubscriptions: [NDKSubscription] {
        return Array(subscriptions.values)
    }
    
    // MARK: - Message Handling
    
    /// Send a message to the relay
    public func send(_ message: String) async throws {
        guard connectionState == .connected else {
            throw NDKError.relayConnectionFailed("Not connected to relay")
        }
        
        // TODO: Send message through WebSocket
        stats.messagesSent += 1
        stats.bytesSent += message.count
    }
    
    /// Handle received message
    private func handleMessage(_ message: String) {
        stats.messagesReceived += 1
        stats.bytesReceived += message.count
        stats.lastMessageAt = Date()
        
        // TODO: Parse and route message to appropriate handlers
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
        var normalized = url
        
        // Ensure wss:// or ws:// prefix
        if !normalized.lowercased().hasPrefix("ws://") && !normalized.lowercased().hasPrefix("wss://") {
            normalized = "wss://\(normalized)"
        }
        
        // Remove trailing slash
        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        
        return normalized.lowercased()
    }
    
    // MARK: - Hashable & Equatable
    
    public static func == (lhs: NDKRelay, rhs: NDKRelay) -> Bool {
        return lhs.normalizedURL == rhs.normalizedURL
    }
    
    public func hash(into hasher: inout Hasher) {
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