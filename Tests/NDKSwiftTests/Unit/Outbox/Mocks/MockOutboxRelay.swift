import Foundation
@testable import NDKSwift

/// Mock relay with outbox-specific testing capabilities
final class MockOutboxRelay: NDKRelay {
    
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
        super.init(url: url)
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
    
    // MARK: - NDKRelay Overrides
    
    override func connect() async {
        if shouldFailConnection {
            connectionState = .disconnected
            return
        }
        
        if shouldAuthChallenge {
            connectionState = .authRequired
        } else {
            connectionState = .connected
        }
    }
    
    override func disconnect() async {
        connectionState = .disconnected
        activeSubscriptions.removeAll()
    }
    
    override func publish(_ event: NDKEvent) async throws -> RelayPublishResult {
        // Simulate response delay
        if responseDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        
        // Check connection
        guard connectionState == .connected || connectionState == .authenticated else {
            return RelayPublishResult(
                relay: self,
                status: .failed(.connectionFailed("Not connected"))
            )
        }
        
        // Simulate auth challenge
        if shouldAuthChallenge && connectionState != .authenticated {
            return RelayPublishResult(
                relay: self,
                status: .failed(.authFailed("Authentication required"))
            )
        }
        
        // Simulate rate limiting
        publishCount += 1
        if let limit = rateLimitAfterCount, publishCount > limit {
            return RelayPublishResult(
                relay: self,
                status: .rateLimited(retryAfter: Date().addingTimeInterval(5))
            )
        }
        
        // Simulate rejection
        if shouldRejectEvents {
            return RelayPublishResult(
                relay: self,
                status: .failed(.rejected(rejectReason))
            )
        }
        
        // Success
        publishedEvents.append(event)
        return RelayPublishResult(
            relay: self,
            status: .success
        )
    }
    
    override func subscribe(
        _ filter: NDKFilter,
        subscriptionId: String
    ) async -> AsyncThrowingStream<RelayMessage, Error> {
        activeSubscriptions[subscriptionId] = filter
        
        return AsyncThrowingStream { continuation in
            Task {
                // Emit matching events
                for event in eventsToEmit {
                    if matchesFilter(event: event, filter: filter) {
                        continuation.yield(.event(subscriptionId, event))
                        
                        // Small delay between events
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                }
                
                // Send EOSE
                continuation.yield(.eose(subscriptionId))
                
                // Keep subscription open unless it should close on EOSE
                if filter.closeOnEose ?? false {
                    continuation.finish()
                } else {
                    // Keep alive for continuous subscriptions
                    try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
                    continuation.finish()
                }
            }
        }
    }
    
    override func unsubscribe(_ subscriptionId: String) async {
        activeSubscriptions.removeValue(forKey: subscriptionId)
    }
    
    override func sendAuthResponse(_ authEvent: NDKEvent) async throws {
        authAttempts += 1
        
        if authAttempts <= maxRetryAttempts {
            connectionState = .authenticated
        } else {
            throw NDKError.relayError(message: "Auth failed after \(authAttempts) attempts")
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
                    .filter { $0.id == tagName }
                    .compactMap { $0.values.first })
                
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
}