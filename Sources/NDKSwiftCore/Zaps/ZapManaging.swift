import Foundation

/// Protocol for managing zaps
/// Allows for dependency injection and testing with alternative implementations
public protocol ZapManaging: Actor, Sendable {
    /// Register a zap protocol
    func register(protocol zapProtocol: NDKZapProtocol)

    /// Register a payment provider
    func register(provider: NDKPaymentProvider)

    /// Get all registered payment providers
    func getRegisteredProviders() -> [NDKPaymentProvider]

    /// Remove a payment provider by ID
    func unregister(providerId: String)

    /// Clear all payment providers
    func clearProviders()

    /// Register a fallback handler
    func register(fallbackHandler: ZapFallbackHandler)

    /// Fetch recipient zap information
    func fetchRecipientZapInfo(for pubkey: PublicKey, maxAge: TimeInterval) async -> RecipientZapInfo

    /// Clear cached recipient info
    func clearRecipientCache(for pubkey: String?)

    /// Send a zap
    /// - Parameters:
    ///   - event: Optional event to zap
    ///   - pubkey: Public key to receive the zap
    ///   - amountSats: Amount in satoshis
    ///   - comment: Optional comment
    ///   - preferredType: Preferred zap type (lightning or nutzap)
    ///   - preferredProvider: Optional ID of a specific provider to use
    /// - Returns: Result of the zap operation
    func zap(
        event: NDKEvent?,
        to pubkey: PublicKey,
        amountSats: Int64,
        comment: String?,
        preferredType: ZapType?,
        preferredProvider: String?
    ) async throws -> ZapResult

    /// Subscribe to zap updates for a user or event
    func subscribeToZaps(
        for event: NDKEvent?,
        pubkey: PublicKey?
    ) -> AsyncThrowingStream<ZapInfo, Error>
}
