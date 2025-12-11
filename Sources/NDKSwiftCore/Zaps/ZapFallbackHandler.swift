import Foundation
import NDKSwiftCore

/// Protocol for handling zap failures/fallbacks (e.g., funding a Nutzap via Lightning)
public protocol ZapFallbackHandler {
    /// Attempt to handle a failed zap
    /// - Parameters:
    ///   - manager: The Zap Manager
    ///   - protocol: The zap protocol that was attempted
    ///   - prepared: The prepared zap data
    ///   - preferredProvider: The user's preferred payment provider ID
    /// - Returns: A ZapResult if handled, nil if not handled
    func tryFallback(
        manager: NDKZapManager,
        protocol: NDKZapProtocol,
        prepared: PreparedZap,
        preferredProvider: String?
    ) async throws -> ZapResult?
}
