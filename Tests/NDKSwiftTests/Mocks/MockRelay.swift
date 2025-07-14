import Foundation
@testable import NDKSwift

/// Mock relay for testing that conforms to RelayProtocol
final class MockRelay: RelayProtocol, @unchecked Sendable {
    let url: String
    var publishedEvents: [NDKEvent] = []
    var subscriptions: [String: NDKSubscription] = [:]
    var connectionState: NDKRelayConnectionState = .disconnected
    var ndk: NDK?
    var activeSubscriptions: [NDKSubscription] = []
    private var stateObservers: [(NDKRelayConnectionState) -> Void] = []
    private var signatureStats = NDKRelaySignatureStats()
    
    init(url: String) {
        self.url = url
    }
    
    // MARK: - RelayProtocol Implementation
    
    func connect() async throws {
        connectionState = .connected
        notifyStateObservers()
    }
    
    func disconnect() async {
        connectionState = .disconnected
        notifyStateObservers()
    }
    
    func send(_ message: String) async throws {
        // Mock implementation - parse and handle the message
    }
    
    func addSubscription(_ subscription: NDKSubscription) async {
        subscriptions[subscription.id] = subscription
        activeSubscriptions.append(subscription)
    }
    
    func removeSubscription(byId id: String) async {
        subscriptions.removeValue(forKey: id)
        activeSubscriptions.removeAll { $0.id == id }
    }
    
    func getSignatureStats() async -> NDKRelaySignatureStats {
        return signatureStats
    }
    
    func updateSignatureStats(_ updater: @Sendable (inout NDKRelaySignatureStats) -> Void) async {
        updater(&signatureStats)
    }
    
    func observeConnectionState(_ observer: @escaping @Sendable (NDKRelayConnectionState) -> Void) async {
        stateObservers.append(observer)
        observer(connectionState)
    }
    
    func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?) {
        publishedEvents.append(event)
        return (success: true, message: nil)
    }
    
    func fetchEvents(filter: NDKFilter) async throws -> [NDKEvent] {
        // Return events matching the filter from publishedEvents
        return publishedEvents.filter { event in
            // Simple filter matching for testing
            if let authors = filter.authors, !authors.contains(event.pubkey) {
                return false
            }
            if let kinds = filter.kinds, !kinds.contains(event.kind) {
                return false
            }
            return true
        }
    }
    
    // MARK: - Test Helpers
    
    private func notifyStateObservers() {
        for observer in stateObservers {
            observer(connectionState)
        }
    }
}