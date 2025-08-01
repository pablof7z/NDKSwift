import Foundation

/// Represents an event that occurs within a NIP-60 wallet
/// Used to notify observers about wallet state changes through an AsyncSequence
public struct NIP60WalletEvent {
    /// Types of events that can occur in a NIP-60 wallet
    public enum EventType {
        /// Wallet configuration was updated with new mint list
        case configurationUpdated(mints: [String])
        /// New mints were added to the wallet
        case mintsAdded([String])
        /// Mints were removed from the wallet
        case mintsRemoved([String])
        /// Wallet balance changed to new amount (in satoshis)
        case balanceChanged(Int64)
        /// Nutzap payment received
        case nutzapReceived(amount: Int64, from: String?, eventId: String)
        /// A new transaction was added to the history
        case transactionAdded(WalletTransaction)
        /// An existing transaction was updated
        case transactionUpdated(WalletTransaction)
        /// Blacklisted mints were updated
        case blacklistUpdated(Set<String>)
    }

    /// The type of event that occurred
    public let type: EventType
    /// When the event occurred
    public let timestamp: Date

    init(type: EventType) {
        self.type = type
        self.timestamp = Date()
    }
}

/// AsyncSequence implementation for streaming NIP-60 wallet events
/// Provides a way to observe wallet state changes asynchronously
public final class NIP60WalletEventStream: AsyncSequence {
    public typealias Element = NIP60WalletEvent

    private let stream: AsyncStream<NIP60WalletEvent>
    private let continuation: AsyncStream<NIP60WalletEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<NIP60WalletEvent>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    public func makeAsyncIterator() -> AsyncStream<NIP60WalletEvent>.AsyncIterator {
        stream.makeAsyncIterator()
    }

    /// Send a new wallet event to all active observers
    /// - Parameter event: The wallet event to broadcast
    func yield(_ event: NIP60WalletEvent) {
        continuation.yield(event)
    }

    /// Signal that no more events will be sent
    /// This completes the AsyncSequence for all observers
    func finish() {
        continuation.finish()
    }
}