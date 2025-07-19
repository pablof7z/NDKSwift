import Foundation

/// A dummy relay protocol implementation for optimistic events
final class OptimisticEventSource: RelayProtocol, @unchecked Sendable {
    let url: String = "optimistic://local"
    
    var connectionState: NDKRelayConnectionState {
        get async { .connected }
    }
    
    weak var ndk: NDK?
    
    var activeSubscriptions: [NDKSubscription] {
        get async { [] }
    }
    
    func connect() async throws {
        // No-op for optimistic source
    }
    
    func disconnect() async {
        // No-op for optimistic source
    }
    
    func send(_ message: String) async throws {
        // No-op for optimistic source
    }
    
    func addSubscription(_ subscription: NDKSubscription) async {
        // No-op for optimistic source
    }
    
    func removeSubscription(byId id: String) async {
        // No-op for optimistic source
    }
    
    func getSignatureStats() async -> NDKRelaySignatureStats {
        return NDKRelaySignatureStats()
    }
    
    func updateSignatureStats(_ updater: @Sendable (inout NDKRelaySignatureStats) -> Void) async {
        // No-op for optimistic source
    }
    
    func observeConnectionState(_ observer: @escaping @Sendable (NDKRelayConnectionState) -> Void) async {
        observer(.connected)
    }
    
    func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?) {
        return (success: true, message: nil)
    }
    
    func fetchEvents(filter: NDKFilter) async throws -> [NDKEvent] {
        return []
    }
}