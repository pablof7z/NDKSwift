import Foundation
@testable import NDKSwiftCore

/// Mock relay with outbox-specific testing capabilities  
/// Provides a testable relay implementation for outbox testing
final class MockOutboxRelay {
    
    // MARK: - Relay Properties
    
    let url: RelayURL
    private(set) var connectionState: NDKRelayConnectionState = .disconnected
    
    // MARK: - Mock Configuration
    
    /// Behavior configuration
    var shouldFailConnection = false
    var shouldAuthChallenge = false
    var shouldRejectEvents = false
    var rejectReason: String = "rejected by mock"
    var responseDelay: TimeInterval = 0
    var maxRetryAttempts = 3
    
    /// Rate limiting simulation
    var rateLimitAfterCount: Int?
    private var publishCount = 0
    
    /// Tracking
    private(set) var publishedEvents: [NDKEvent] = []
    private(set) var activeSubscriptions: [String: NDKFilter] = [:]
    private(set) var authAttempts = 0
    
    /// Events to emit for subscriptions
    private var eventsToEmit: [NDKEvent] = []
    
    // MARK: - Initialization
    
    init(url: RelayURL) {
        self.url = url
    }
    
    // MARK: - Mock Helpers
    
    /// Add events that will be emitted for matching subscriptions
    func addEventsToEmit(_ events: [NDKEvent]) {
        eventsToEmit.append(contentsOf: events)
    }
    
    /// Clear all tracking data
    func reset() {
        publishedEvents.removeAll()
        activeSubscriptions.removeAll()
        authAttempts = 0
        publishCount = 0
        eventsToEmit.removeAll()
    }
    
    /// Simulate connection state change
    func simulateConnectionState(_ state: NDKRelayConnectionState) {
        self.connectionState = state
    }
    
    /// Get published events count for a specific pubkey
    func getPublishedCount(for pubkey: PublicKey) -> Int {
        publishedEvents.filter { $0.pubkey == pubkey }.count
    }
    
    // MARK: - Mock Relay Methods
    
    func connect() async throws {
        if shouldFailConnection {
            connectionState = .disconnected
            throw NDKError.connectionFailed(relay: url, message: "Mock connection failure")
        }
        
        if shouldAuthChallenge {
            connectionState = .authRequired(challenge: "mock-challenge")
        } else {
            connectionState = .connected
        }
    }
    
    func disconnect() async {
        connectionState = .disconnected
        activeSubscriptions.removeAll()
    }
    
    func publish(_ event: NDKEvent) async throws -> MockPublishResult {
        // Simulate response delay
        if responseDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        
        // Check connection
        guard await isConnected() else {
            return MockPublishResult(success: false, message: "Not connected")
        }
        
        // Simulate auth challenge
        let isAuth = await isAuthenticated()
        if shouldAuthChallenge && !isAuth {
            return MockPublishResult(success: false, message: "Authentication required")
        }
        
        // Simulate rate limiting
        publishCount += 1
        if let limit = rateLimitAfterCount, publishCount > limit {
            return MockPublishResult(success: false, message: "Rate limited")
        }
        
        // Simulate rejection
        if shouldRejectEvents {
            return MockPublishResult(success: false, message: rejectReason)
        }
        
        // Success
        publishedEvents.append(event)
        return MockPublishResult(success: true, message: "Published successfully")
    }
    
    func subscribe(
        _ filter: NDKFilter,
        subscriptionId: String
    ) async -> AsyncThrowingStream<MockRelayMessage, Error> {
        activeSubscriptions[subscriptionId] = filter
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                // Emit matching events
                for event in self.eventsToEmit {
                    if self.matchesFilter(event: event, filter: filter) {
                        continuation.yield(MockRelayMessage.event(subscriptionId, event))
                        
                        // Small delay between events
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                }
                
                // Send EOSE
                continuation.yield(MockRelayMessage.eose(subscriptionId))
                
                // Keep alive for continuous subscriptions
                // (In real implementation, closeOnEose would be handled by subscription options)
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    func unsubscribe(_ subscriptionId: String) async {
        activeSubscriptions.removeValue(forKey: subscriptionId)
    }
    
    func sendAuthResponse(_ authEvent: NDKEvent) async throws {
        authAttempts += 1
        
        if authAttempts <= maxRetryAttempts {
            connectionState = .authenticated
        } else {
            throw NDKError.relayError(relay: url, message: "Auth failed after \(authAttempts) attempts")
        }
    }
    
    // MARK: - Helper Methods
    
    private func matchesFilter(event: NDKEvent, filter: NDKFilter) -> Bool {
        // Check authors
        if let authors = filter.authors, !authors.isEmpty {
            guard authors.contains(event.pubkey) else { return false }
        }
        
        // Check kinds
        if let kinds = filter.kinds, !kinds.isEmpty {
            guard kinds.contains(event.kind) else { return false }
        }
        
        // Check tags
        if let filterTags = filter.tags {
            for (tagName, tagValues) in filterTags {
                let eventTagValues = Set(event.tags
                    .filter { $0.count > 0 && $0[0] == tagName }
                    .compactMap { $0.count > 1 ? $0[1] : nil })
                
                // Event must have at least one matching tag value
                if !tagValues.isEmpty && eventTagValues.isDisjoint(with: tagValues) {
                    return false
                }
            }
        }
        
        // Check time constraints
        if let since = filter.since, event.createdAt < since {
            return false
        }
        if let until = filter.until, event.createdAt > until {
            return false
        }
        
        return true
    }
    
    // MARK: - Connection State Helpers
    
    private func isConnected() async -> Bool {
        return connectionState == .connected || connectionState == .authenticated
    }
    
    private func isAuthenticated() async -> Bool {
        return connectionState == .authenticated
    }
}

// MARK: - Mock Types

struct MockPublishResult {
    let success: Bool
    let message: String
}

enum MockRelayMessage {
    case event(String, NDKEvent)
    case eose(String)
    case notice(String)
}
