import Foundation
@testable import NDKSwiftCore

/// A controllable mock relay for testing without network connectivity.
/// This actor wraps relay behavior and provides full control over:
/// - Connection states
/// - Event injection
/// - EOSE simulation
/// - Message tracking
public actor ControllableMockRelay {

    // MARK: - Properties

    public let url: RelayURL
    private weak var ndk: NDK?
    private var _connectionState: NDKRelayConnectionState = .disconnected

    // MARK: - Tracking

    /// All raw messages sent to this relay
    private(set) var sentMessages: [String] = []

    /// All events published to this relay
    private(set) var publishedEvents: [NDKEvent] = []

    /// Currently active subscriptions (subscriptionId -> filters)
    private(set) var activeSubscriptions: [String: [NDKFilter]] = [:]

    /// Track EOSE sent for subscriptions
    private(set) var eoseSent: Set<String> = []

    // MARK: - Event Injection

    /// Events to emit for specific subscription IDs
    private var queuedEvents: [String: [NDKEvent]] = [:]

    /// Whether to auto-send EOSE after queued events
    private var autoSendEOSE: Set<String> = []

    // MARK: - Behavior Configuration

    public var shouldFailPublish = false
    public var publishFailureMessage = "Mock publish failure"
    public var publishDelay: TimeInterval = 0

    // MARK: - Associated NDKRelay

    /// The real NDKRelay in the pool (for EOSE routing)
    private weak var poolRelay: NDKRelay?

    // MARK: - Initialization

    public init(url: RelayURL) {
        self.url = url
    }

    /// Associate with an NDK instance and create/get the relay in pool
    public func attach(to ndk: NDK) async -> NDKRelay {
        self.ndk = ndk

        // Add relay to pool and get the NDKRelay instance
        let relay = await ndk.pool.addRelay(url)
        self.poolRelay = relay

        return relay
    }

    /// Set the associated pool relay's connection state
    public func setConnected(_ connected: Bool = true) async {
        guard let relay = poolRelay else { return }
        let state: NDKRelayConnectionState = connected ? .connected : .disconnected
        await relay.updateConnectionState(state)
        _connectionState = state
    }

    /// Simulate authentication
    public func setAuthenticated() async {
        guard let relay = poolRelay else { return }
        await relay.updateConnectionState(.authenticated)
        _connectionState = .authenticated
    }

    /// Simulate connection failure
    public func setFailed(_ message: String = "Mock failure") async {
        guard let relay = poolRelay else { return }
        await relay.updateConnectionState(.failed(message))
        _connectionState = .failed(message)
    }

    // MARK: - Event Injection

    /// Queue events to be delivered for a subscription
    public func queueEvents(_ events: [NDKEvent], forSubscription subscriptionId: String, sendEOSE: Bool = true) {
        queuedEvents[subscriptionId, default: []].append(contentsOf: events)
        if sendEOSE {
            autoSendEOSE.insert(subscriptionId)
        }
    }

    /// Inject an event directly into the subscription pipeline
    public func injectEvent(_ event: NDKEvent, subscriptionId: String) async {
        guard let ndk = ndk, let relay = poolRelay else {
            NDKLogger.log(.warning, category: .relay,
                         "[MockRelay] Cannot inject event - not attached to NDK")
            return
        }

        // Route through the internal subscription manager
        await ndk.internalSubscriptionManager.processEvent(event, subscriptionId: subscriptionId, from: relay)
    }

    /// Send EOSE for a subscription
    public func sendEOSE(subscriptionId: String) async {
        guard let ndk = ndk, let relay = poolRelay else {
            NDKLogger.log(.warning, category: .relay,
                         "[MockRelay] Cannot send EOSE - not attached to NDK")
            return
        }

        eoseSent.insert(subscriptionId)
        ndk.processEOSE(subscriptionId: subscriptionId, from: relay)
    }

    // MARK: - Subscription Tracking

    /// Register a subscription (call this when subscription is created)
    public func registerSubscription(_ subscriptionId: String, filters: [NDKFilter]) async {
        activeSubscriptions[subscriptionId] = filters

        // Deliver queued events if any
        if let events = queuedEvents[subscriptionId] {
            for event in events {
                await injectEvent(event, subscriptionId: subscriptionId)
            }
            queuedEvents.removeValue(forKey: subscriptionId)
        }

        // Auto-send EOSE if configured
        if autoSendEOSE.contains(subscriptionId) {
            autoSendEOSE.remove(subscriptionId)
            await sendEOSE(subscriptionId: subscriptionId)
        }
    }

    /// Unregister a subscription
    public func unregisterSubscription(_ subscriptionId: String) {
        activeSubscriptions.removeValue(forKey: subscriptionId)
    }

    // MARK: - Test Assertions

    public func hasActiveSubscription(_ subscriptionId: String) -> Bool {
        activeSubscriptions[subscriptionId] != nil
    }

    public func didSendEOSE(for subscriptionId: String) -> Bool {
        eoseSent.contains(subscriptionId)
    }

    public func getPublishedEventCount() -> Int {
        publishedEvents.count
    }

    // MARK: - Reset

    public func reset() {
        sentMessages.removeAll()
        publishedEvents.removeAll()
        activeSubscriptions.removeAll()
        queuedEvents.removeAll()
        autoSendEOSE.removeAll()
        eoseSent.removeAll()
        _connectionState = .disconnected
    }
}

// MARK: - NDK Extension for Testing

extension NDK {
    /// Create a connected mock relay attached to this NDK instance
    /// Returns both the mock controller and the NDKRelay in the pool
    @discardableResult
    public func addMockRelay(url: RelayURL) async -> (mock: ControllableMockRelay, relay: NDKRelay) {
        let mock = ControllableMockRelay(url: url)
        let relay = await mock.attach(to: self)
        await mock.setConnected()
        return (mock, relay)
    }

    /// Add multiple connected mock relays
    public func addMockRelays(urls: [RelayURL]) async -> [(mock: ControllableMockRelay, relay: NDKRelay)] {
        var results: [(ControllableMockRelay, NDKRelay)] = []
        for url in urls {
            let result = await addMockRelay(url: url)
            results.append(result)
        }
        return results
    }
}

// MARK: - NDKPool Extension for Testing

extension NDKPool {
    /// Get all currently connected relay URLs (for test verification)
    public func getConnectedRelayURLsForTesting() async -> Set<RelayURL> {
        await connectedRelayURLs
    }

    /// Force a relay to appear connected (for testing)
    public func setRelayConnected(_ url: RelayURL, connected: Bool = true) async {
        guard let relay = await getRelay(for: url) else { return }
        await relay.updateConnectionState(connected ? .connected : .disconnected)
    }
}
