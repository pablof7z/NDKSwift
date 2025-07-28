import Foundation

/// Custom relay selection strategy for fine-grained control over outbox model behavior
///
/// The `RelaySelectionStrategy` allows you to override the default relay selection logic
/// used by the outbox model. This is useful for implementing custom routing rules,
/// geographic preferences, or application-specific relay policies.
///
/// ## Example
/// ```swift
/// // Create a strategy that prefers specific relays for certain users
/// let customStrategy = RelaySelectionStrategy { pubkey in
///     if pubkey == "special_user_pubkey" {
///         return ["wss://premium.relay.com/", "wss://fast.relay.com/"]
///     }
///     // Fall back to default behavior
///     return []
/// }
///
/// // Use the strategy when publishing
/// let relays = try await ndk.outbox.publish(event, strategy: customStrategy)
/// ```
public struct RelaySelectionStrategy {
    /// Closure that selects relays for a given public key
    ///
    /// - Parameter pubkey: The hex-encoded public key to select relays for
    /// - Returns: Array of relay URLs to use, or empty array to use default selection
    ///
    /// The closure is called during relay selection and can return:
    /// - Specific relay URLs to override default selection
    /// - Empty array to fall back to the outbox model's default logic
    public let selectRelays: (String) async -> [String]

    /// Creates a new relay selection strategy
    ///
    /// - Parameter selectRelays: Async closure that returns relay URLs for a given pubkey
    public init(selectRelays: @escaping (String) async -> [String]) {
        self.selectRelays = selectRelays
    }
}