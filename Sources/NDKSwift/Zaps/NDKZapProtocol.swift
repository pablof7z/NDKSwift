import Foundation

/// Handles the Nostr-side logic of a zap (e.g., NIP-57, NIP-61)
public protocol NDKZapProtocol {
    /// The type of zap this protocol handles
    var type: ZapType { get }
    
    /// Check if this protocol can zap the given user
    func canZap(user: NDKUser) async throws -> Bool
    
    /// Prepare the zap by creating necessary events and payment request
    /// - Parameters:
    ///   - event: Optional event being zapped
    ///   - user: The recipient of the zap
    ///   - amountSats: Amount in satoshis
    ///   - comment: Optional comment
    /// - Returns: Prepared zap data including payment request
    func prepareZap(
        event: NDKEvent?,
        to user: NDKUser,
        amountSats: Int64,
        comment: String?
    ) async throws -> PreparedZap
    
    /// Complete the zap after payment confirmation
    /// - Parameters:
    ///   - prepared: The prepared zap data
    ///   - confirmation: Payment confirmation from provider
    /// - Returns: ZapResult with sent event and confirmation handler
    func completeZap(
        prepared: PreparedZap,
        confirmation: PaymentConfirmation
    ) async throws -> ZapResult
}

/// Data prepared by a zap protocol before payment
public struct PreparedZap {
    /// The payment request to be fulfilled
    public let paymentRequest: PaymentRequest
    
    /// The recipient user
    public let recipient: NDKUser
    
    /// Optional event being zapped
    public let zappedEvent: NDKEvent?
    
    /// Comment for the zap
    public let comment: String?
    
    /// Protocol-specific metadata
    public let metadata: [String: Any]
    
    public init(
        paymentRequest: PaymentRequest,
        recipient: NDKUser,
        zappedEvent: NDKEvent? = nil,
        comment: String? = nil,
        metadata: [String: Any] = [:]
    ) {
        self.paymentRequest = paymentRequest
        self.recipient = recipient
        self.zappedEvent = zappedEvent
        self.comment = comment
        self.metadata = metadata
    }
}