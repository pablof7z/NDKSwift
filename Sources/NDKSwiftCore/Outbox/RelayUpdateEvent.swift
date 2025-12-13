import Foundation

/// Event emitted when a user's relay preferences are discovered or updated
///
/// The `RelayUpdateEvent` is published through the outbox model's event stream
/// whenever a user's relay list (NIP-65) is discovered or changes. This allows
/// applications to react to relay preference updates in real-time.
///
/// ## Usage
/// ```swift
/// // Monitor relay updates for specific users
/// for await update in ndk.outbox.relayUpdates {
///     print("User \(update.pubkey) updated relays")
///     print("Read relays: \(update.relays.readRelays)")
///     print("Write relays: \(update.relays.writeRelays)")
/// }
/// ```
public struct RelayUpdateEvent: Sendable {
    /// The public key of the user whose relay preferences were updated
    public let pubkey: String

    /// The updated relay sets for reading and writing
    ///
    /// - `readRelays`: Relays the user reads from (for fetching their events)
    /// - `writeRelays`: Relays the user writes to (for publishing to them)
    public let relays: (readRelays: Set<RelayURL>, writeRelays: Set<RelayURL>)

    /// Subscription IDs that are affected by this relay update
    ///
    /// These subscriptions may need to be reconfigured to use the new relay set
    public let affectedSubscriptionIds: Set<String>

    /// When this relay update was discovered
    public let timestamp: Date

    /// Creates a new relay update event
    ///
    /// - Parameters:
    ///   - pubkey: The public key of the user
    ///   - relays: Tuple of read and write relay sets
    ///   - affectedSubscriptionIds: IDs of subscriptions affected by this update
    ///   - timestamp: When the update occurred (defaults to current time)
    public init(
        pubkey: String,
        relays: (readRelays: Set<RelayURL>, writeRelays: Set<RelayURL>),
        affectedSubscriptionIds: Set<String>,
        timestamp: Date = Date()
    ) {
        self.pubkey = pubkey
        self.relays = relays
        self.affectedSubscriptionIds = affectedSubscriptionIds
        self.timestamp = timestamp
    }
}
