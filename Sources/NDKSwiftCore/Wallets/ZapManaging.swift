import Foundation

/// Protocol for managing zaps
public protocol ZapManaging: Actor, Sendable {
    /// Send a zap
    /// - Parameters:
    ///   - event: Optional event to zap
    ///   - recipient: User to receive the zap
    ///   - amountSats: Amount in satoshis
    ///   - comment: Optional comment
    ///   - preferredType: Preferred zap type (lightning or nutzap)
    ///   - preferredProvider: Optional ID of a specific provider to use
    /// - Returns: Result of the zap operation
    func zap(
        event: NDKEvent?,
        to recipient: NDKUser,
        amountSats: Int64,
        comment: String?,
        preferredType: ZapType?,
        preferredProvider: String?
    ) async throws -> ZapResult

    /// Subscribe to zap updates
    /// - Parameters:
    ///   - event: Optional event to monitor
    ///   - user: Optional user to monitor
    /// - Returns: Stream of zap info
    func subscribeToZaps(
        for event: NDKEvent?,
        user: NDKUser?
    ) -> AsyncThrowingStream<ZapInfo, Error>
}

// Re-export ZapInfo to make it available
// Note: ZapInfo definition depends on NDKSwiftCore types, so it should be defined here or in Types.swift
// Since NDKZapManager (implementation) is in Cashu, but the interface is here.
// We need to define ZapInfo here if it's used in the protocol.

public struct ZapInfo: Sendable {
    public let type: ZapType
    public let amountSats: Int64
    public let sender: String?
    public let recipient: String
    public let comment: String?
    public let timestamp: Date
    public let event: NDKEvent

    public init(
        type: ZapType,
        amountSats: Int64,
        sender: String?,
        recipient: String,
        comment: String?,
        timestamp: Date,
        event: NDKEvent
    ) {
        self.type = type
        self.amountSats = amountSats
        self.sender = sender
        self.recipient = recipient
        self.comment = comment
        self.timestamp = timestamp
        self.event = event
    }
}
