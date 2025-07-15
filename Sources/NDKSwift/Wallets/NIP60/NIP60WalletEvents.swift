import Foundation

/// AsyncSequence for wallet events
public struct NIP60WalletEvent {
    public enum EventType {
        case configurationUpdated(mints: [String])
        case mintsAdded([String])
        case mintsRemoved([String])
        case balanceChanged(Int64)
        case nutzapReceived(amount: Int64, from: String?)
    }
    
    public let type: EventType
    public let timestamp: Date
    
    init(type: EventType) {
        self.type = type
        self.timestamp = Date()
    }
}

/// AsyncSequence implementation for wallet events
public final class NIP60WalletEventStream: AsyncSequence {
    public typealias Element = NIP60WalletEvent
    
    private let stream: AsyncStream<NIP60WalletEvent>
    private let continuation: AsyncStream<NIP60WalletEvent>.Continuation
    
    init() {
        var savedContinuation: AsyncStream<NIP60WalletEvent>.Continuation?
        self.stream = AsyncStream { continuation in
            savedContinuation = continuation
        }
        self.continuation = savedContinuation!
    }
    
    public func makeAsyncIterator() -> AsyncStream<NIP60WalletEvent>.AsyncIterator {
        stream.makeAsyncIterator()
    }
    
    func yield(_ event: NIP60WalletEvent) {
        continuation.yield(event)
    }
    
    func finish() {
        continuation.finish()
    }
}