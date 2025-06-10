import Foundation
@testable import NDKSwift

/// Mock relay for testing
public final class MockRelay: RelayProtocol {
    public let url: String
    public var connectionState: NDKRelayConnectionState = .disconnected
    public weak var ndk: NDK?
    
    // Mock configuration
    public var shouldFailConnection = false
    public var connectionError: Error?
    public var shouldFailSend = false
    public var sendError: Error?
    public var autoConnect = true
    public var connectionDelay: TimeInterval = 0.0
    
    // State tracking
    public private(set) var sentMessages: [String] = []
    public private(set) var subscriptions: [String: NDKSubscription] = [:]
    private var stateObservers: [(NDKRelayConnectionState) -> Void] = []
    
    // Mock events
    private var mockEvents: [NDKEvent] = []
    public var autoRespond = false
    public var mockResponses: [String: [NDKEvent]] = [:]
    
    // Statistics
    private var signatureStats = NDKRelaySignatureStats()
    
    public init(url: String) {
        self.url = url
    }
    
    // MARK: - RelayProtocol Implementation
    
    public var activeSubscriptions: [NDKSubscription] {
        return Array(subscriptions.values)
    }
    
    public func connect() async throws {
        guard connectionState == .disconnected else { return }
        
        connectionState = .connecting
        notifyStateObservers()
        
        if shouldFailConnection {
            connectionState = .failed(connectionError?.localizedDescription ?? "Connection failed")
            notifyStateObservers()
            throw connectionError ?? NDKError.network("connection_failed", "Mock connection failed")
        }
        
        if connectionDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(connectionDelay * 1_000_000_000))
        }
        
        if autoConnect {
            connectionState = .connected
            notifyStateObservers()
        }
    }
    
    public func disconnect() async {
        guard connectionState != .disconnected else { return }
        
        connectionState = .disconnecting
        notifyStateObservers()
        
        // Clear subscriptions
        subscriptions.removeAll()
        
        connectionState = .disconnected
        notifyStateObservers()
    }
    
    public func send(_ message: String) async throws {
        guard connectionState == .connected else {
            throw NDKError.network("not_connected", "Mock relay is not connected")
        }
        
        if shouldFailSend {
            throw sendError ?? NDKError.network("send_failed", "Mock send failed")
        }
        
        sentMessages.append(message)
        
        // Process auto-responses
        if autoRespond {
            processMessage(message)
        }
    }
    
    public func addSubscription(_ subscription: NDKSubscription) {
        subscriptions[subscription.id] = subscription
    }
    
    public func removeSubscription(byId id: String) {
        subscriptions.removeValue(forKey: id)
    }
    
    public func getSignatureStats() -> NDKRelaySignatureStats {
        return signatureStats
    }
    
    public func updateSignatureStats(_ updater: (inout NDKRelaySignatureStats) -> Void) {
        updater(&signatureStats)
    }
    
    public func observeConnectionState(_ observer: @escaping (NDKRelayConnectionState) -> Void) {
        stateObservers.append(observer)
        // Immediately notify of current state
        observer(connectionState)
    }
    
    // MARK: - Mock Helpers
    
    public func addMockEvent(_ event: NDKEvent) {
        mockEvents.append(event)
    }
    
    public func addMockResponse(for subscriptionId: String, events: [NDKEvent]) {
        mockResponses[subscriptionId] = events
    }
    
    public func simulateEvent(_ event: NDKEvent, forSubscription subscriptionId: String) {
        guard let subscription = subscriptions[subscriptionId] else { return }
        
        // Check if event matches filters
        for filter in subscription.filters {
            if filter.matches(event: event) {
                Task {
                    await subscription.handleEvent(event, from: self)
                }
                break
            }
        }
    }
    
    public func simulateEOSE(forSubscription subscriptionId: String) {
        guard let subscription = subscriptions[subscriptionId] else { return }
        
        Task {
            await subscription.handleEOSE(from: self)
        }
    }
    
    public func simulateError(_ error: Error, forSubscription subscriptionId: String) {
        guard let subscription = subscriptions[subscriptionId] else { return }
        
        Task {
            await subscription.handleError(error, from: self)
        }
    }
    
    public func wasSent(messageType: String) -> Bool {
        return sentMessages.contains { $0.contains("[\"\(messageType)\"") }
    }
    
    public func reset() {
        sentMessages.removeAll()
        subscriptions.removeAll()
        mockEvents.removeAll()
        mockResponses.removeAll()
        connectionState = .disconnected
        notifyStateObservers()
    }
    
    // MARK: - Private Helpers
    
    private func notifyStateObservers() {
        for observer in stateObservers {
            observer(connectionState)
        }
    }
    
    private func processMessage(_ message: String) {
        // Parse REQ messages and auto-respond
        if message.hasPrefix("[\"REQ\"") {
            if let data = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
               json.count > 1,
               let subId = json[1] as? String {
                
                // Send mock events
                if let events = mockResponses[subId] {
                    for event in events {
                        simulateEvent(event, forSubscription: subId)
                    }
                } else {
                    // Send default mock events that match filters
                    if let subscription = subscriptions[subId] {
                        for event in mockEvents {
                            for filter in subscription.filters {
                                if filter.matches(event: event) {
                                    simulateEvent(event, forSubscription: subId)
                                    break
                                }
                            }
                        }
                    }
                }
                
                // Auto EOSE
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    simulateEOSE(forSubscription: subId)
                }
            }
        }
    }
}

// MARK: - Helper Extensions

extension NDKSubscription {
    /// Handle event from mock relay (for testing)
    func handleEvent(_ event: NDKEvent, from relay: RelayProtocol) async {
        // This would normally be internal to subscription
        // For testing, we can simulate the behavior
        await withCheckedContinuation { continuation in
            Task {
                // Add event to subscription's internal stream
                // This is a simplified version - actual implementation may differ
                continuation.resume()
            }
        }
    }
    
    /// Handle EOSE from mock relay (for testing)
    func handleEOSE(from relay: RelayProtocol) async {
        // This would normally be internal to subscription
        await withCheckedContinuation { continuation in
            Task {
                // Mark EOSE received from this relay
                continuation.resume()
            }
        }
    }
    
    /// Handle error from mock relay (for testing)
    func handleError(_ error: Error, from relay: RelayProtocol) async {
        // This would normally be internal to subscription
        await withCheckedContinuation { continuation in
            Task {
                // Handle error for this relay
                continuation.resume()
            }
        }
    }
}