import Foundation

/// Type of entity in a hint
public enum HintEntityType: Sendable, Equatable {
    case pubkey
    case eventId
    case address
}

/// Type of relay operation
public enum RelayOperation: Sendable, Equatable {
    case publish
    case fetch
    case subscribe
}

/// Events emitted by the relay intelligence system for debugging/monitoring
public enum IntelligenceEvent: Sendable {
    /// A new hint was recorded
    case hintRecorded(type: HintEntityType, identifier: String, relay: RelayURL, source: HintSource)

    /// Relays were selected for an operation
    case relaySelected(operation: RelayOperation, relays: Set<RelayURL>, reason: String)

    /// A relay was evicted from the pool
    case relayEvicted(relay: RelayURL, reason: String)

    /// A relay was added to the pool
    case relayAdded(relay: RelayURL, origin: NDKRelayOrigin)
}

/// Actor that manages an event stream for intelligence events
/// Supports multiple subscribers via AsyncStream
public actor IntelligenceEventStream {
    private var continuations: [UUID: AsyncStream<IntelligenceEvent>.Continuation] = [:]

    public init() {}

    /// Get an async stream of intelligence events
    public nonisolated var events: AsyncStream<IntelligenceEvent> {
        AsyncStream { continuation in
            let id = UUID()

            Task { [weak self] in
                await self?.addContinuation(id: id, continuation: continuation)
            }

            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    /// Emit an event to all subscribers
    public func emit(_ event: IntelligenceEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func addContinuation(id: UUID, continuation: AsyncStream<IntelligenceEvent>.Continuation) {
        continuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
