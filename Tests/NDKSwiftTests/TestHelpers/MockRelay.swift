import Foundation
import Combine
@testable import NDKSwiftCore

/// Type alias for backward compatibility
typealias MockRelay = MockRelayProtocol

/// A mock relay for testing purposes
class MockRelayProtocol: RelayProtocol, @unchecked Sendable {
    let url: String
    private(set) var connectionState: NDKRelayConnectionState = .disconnected
    weak var ndk: NDK?
    private(set) var activeSubscriptionIds: [String] = []
    
    // Track sent messages for testing
    private(set) var sentMessages: [String] = []
    
    // Track published events
    private(set) var publishedEvents: [NDKEvent] = []
    
    // Control test behavior
    var shouldFailPublish = false
    var publishDelay: TimeInterval = 0
    
    // Callback for intercepting sent messages
    var onSend: ((String) -> Void)?
    
    // State stream support
    private let stateSubject = PassthroughSubject<NDKRelayConnectionState, Never>()
    var stateStream: AsyncStream<NDKRelayConnectionState> {
        AsyncStream { continuation in
            let cancellable = stateSubject.sink { state in
                continuation.yield(state)
            }
            continuation.onTermination = { _ in
                _ = cancellable
            }
        }
    }
    
    init(url: String) {
        self.url = url
    }
    
    func connect() async {
        updateConnectionState(.connected)
    }
    
    func disconnect() async {
        updateConnectionState(.disconnected)
        activeSubscriptionIds.removeAll()
    }
    
    func updateConnectionState(_ newState: NDKRelayConnectionState) {
        connectionState = newState
        stateSubject.send(newState)
    }
    
    func send(_ message: String) async throws {
        sentMessages.append(message)
        onSend?(message)
    }
    
    func addSubscriptionId(_ subscriptionId: String) async {
        activeSubscriptionIds.append(subscriptionId)
    }
    
    func removeSubscription(byId id: String) async {
        activeSubscriptionIds.removeAll { $0 == id }
    }
    
    func getSignatureStats() async -> NDKRelaySignatureStats {
        NDKRelaySignatureStats()
    }
    
    func updateSignatureStats(_ updater: @Sendable (inout NDKRelaySignatureStats) -> Void) async {
        var stats = NDKRelaySignatureStats()
        updater(&stats)
    }
    
    func observeConnectionState(_ observer: @escaping @Sendable (NDKRelayConnectionState) -> Void) async {
        observer(connectionState)
    }
    
    func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?) {
        if publishDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(publishDelay * 1_000_000_000))
        }
        
        if shouldFailPublish {
            return (false, "Mock publish failure")
        }
        
        publishedEvents.append(event)
        return (true, nil)
    }
}