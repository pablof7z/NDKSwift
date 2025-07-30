import Foundation

/// Tracks EOSE (End of Stored Events) status across multiple relays
/// Implements the same progressive timeout algorithm as ndk-core
actor EOSETracker {
    // Subscription context for logging
    private let subscriptionId: String
    
    // Relays that have sent EOSE
    private var eosesSeen = Set<RelayURL>()
    
    // All relays we expect to hear from
    private var expectedRelays = Set<RelayURL>()
    
    // When we last received an event
    private var lastEventReceivedAt: Date?
    
    // Whether we've already emitted the aggregated EOSE
    private var hasEmittedEOSE = false
    
    // Timer for progressive EOSE emission
    private var eoseTimer: Task<Void, Never>?
    
    // Stream for EOSE updates
    private var eoseUpdatesContinuation: AsyncStream<Bool>.Continuation?
    public let eoseUpdates: AsyncStream<Bool>
    
    init(subscriptionId: String) {
        self.subscriptionId = subscriptionId
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        self.eoseUpdates = stream
        self.eoseUpdatesContinuation = continuation
    }
    
    /// Set the relays we expect to hear from
    func setExpectedRelays(_ relays: Set<RelayURL>) {
        expectedRelays = relays
        NDKLogger.log(.debug, category: .subscription,
                     "🎯 [\(subscriptionId)] EOSETracker expecting EOSE from \(relays.count) relays")
    }
    
    /// Track that a relay has sent EOSE
    func trackEOSE(from relay: RelayURL) {
        guard expectedRelays.contains(relay) else {
            NDKLogger.log(.warning, category: .subscription,
                         "⚠️ [\(subscriptionId)] Received EOSE from unexpected relay: \(relay)")
            return
        }
        
        eosesSeen.insert(relay)
        
        NDKLogger.log(.debug, category: .subscription,
                     "📊 [\(subscriptionId)] EOSE received from \(relay) (\(eosesSeen.count)/\(expectedRelays.count))")
        
        // Check if we should emit EOSE
        checkEOSEEmission()
    }
    
    /// Track that we received an event (resets the timeout)
    func trackEventReceived() {
        lastEventReceivedAt = Date()
    }
    
    /// Check if all expected relays have sent EOSE
    func allRelaysEOSEd() -> Bool {
        return !expectedRelays.isEmpty && eosesSeen == expectedRelays
    }
    
    /// Check if we should emit the aggregated EOSE event
    func shouldEmitEOSE(events: Set<EventID>, filter: NDKFilter) -> Bool {
        // Already emitted
        if hasEmittedEOSE { return false }
        
        // All relays EOSEd
        if allRelaysEOSEd() { return true }
        
        // Query is fully filled
        if isQueryFullyFilled(events: events, filter: filter) { return true }
        
        return false
    }
    
    /// Check if we should emit EOSE based on progressive timeout
    private func checkEOSEEmission() {
        // Cancel existing timer
        eoseTimer?.cancel()
        
        let hasSeenAllEoses = allRelaysEOSEd()
        
        if hasSeenAllEoses {
            emitEOSE(reason: "all relays EOSEd")
            return
        }
        
        // Calculate progressive timeout (matching ndk-core logic)
        guard expectedRelays.count > 0 else { return }
        
        let percentageOfRelaysThatHaveSentEose = Double(eosesSeen.count) / Double(expectedRelays.count)
        
        NDKLogger.log(.debug, category: .subscription,
                     "📊 [\(subscriptionId)] EOSE percentage: \(Int(percentageOfRelaysThatHaveSentEose * 100))% (\(eosesSeen.count)/\(expectedRelays.count))")
        
        // Don't start timeout until at least 2 relays and 50% have EOSEd
        guard eosesSeen.count >= 2 && percentageOfRelaysThatHaveSentEose >= 0.5 else { return }
        
        // Base timeout of 1 second, reduced by percentage
        let baseTimeout: TimeInterval = 1.0
        var timeToWaitForNextEose = baseTimeout * (1.0 - percentageOfRelaysThatHaveSentEose)
        
        if timeToWaitForNextEose == 0 {
            emitEOSE(reason: "100% timeout reduction")
            return
        }
        
        // Ensure minimum timeout of 50ms
        timeToWaitForNextEose = max(timeToWaitForNextEose, 0.05)
        
        NDKLogger.log(.debug, category: .subscription,
                     "⏱️ [\(subscriptionId)] Setting EOSE timeout: \(Int(timeToWaitForNextEose * 1000))ms")
        
        eoseTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeToWaitForNextEose * Double(TimeConstants.nanosecondsPerSecond)))
            
            guard !Task.isCancelled else { return }
            
            await self?.checkIfShouldEmitAfterTimeout()
        }
    }
    
    /// Check if we should emit EOSE after timeout
    private func checkIfShouldEmitAfterTimeout() {
        // If we received an event in the last 20ms, restart the timer
        if let lastEventTime = lastEventReceivedAt,
           Date().timeIntervalSince(lastEventTime) < 0.02 {
            NDKLogger.log(.debug, category: .subscription,
                         "⏱️ [\(subscriptionId)] Recent event received, restarting EOSE timer")
            checkEOSEEmission()
            return
        }
        
        emitEOSE(reason: "progressive timeout")
    }
    
    /// Emit the aggregated EOSE event
    private func emitEOSE(reason: String) {
        guard !hasEmittedEOSE else { return }
        
        hasEmittedEOSE = true
        eoseTimer?.cancel()
        
        let relaysSentEOSE = Array(eosesSeen).sorted()
        let relaysNotSentEOSE = Array(expectedRelays.subtracting(eosesSeen)).sorted()
        
        NDKLogger.log(.info, category: .subscription,
                     "✅ [\(subscriptionId)] Emitting aggregated EOSE: \(reason) | EOSEd: \(eosesSeen.count)/\(expectedRelays.count) relays | EOSEd relays: \(relaysSentEOSE) | Pending: \(relaysNotSentEOSE)")
        
        eoseUpdatesContinuation?.yield(true)
    }
    
    /// Check if query is fully filled (simple version, full logic is in DataRequirement)
    private func isQueryFullyFilled(events: Set<EventID>, filter: NDKFilter) -> Bool {
        // For replaceable events, always wait for all relays
        // to ensure we get the most recent version
        if filter.isReplaceable {
            return false
        }
        
        // ID queries
        if let requestedIds = filter.ids, !requestedIds.isEmpty {
            if events.count >= requestedIds.count {
                return true
            }
        }
        
        // Limit queries
        if let limit = filter.limit {
            if events.count >= limit {
                return true
            }
        }
        
        return false
    }
    
    deinit {
        eoseTimer?.cancel()
        eoseUpdatesContinuation?.finish()
    }
}