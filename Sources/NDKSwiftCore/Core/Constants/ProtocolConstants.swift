import Foundation

/// Constants related to the Nostr protocol implementation
public enum ProtocolConstants {
    // MARK: - NIP-65 Outbox Model

    /// Maximum number of p-tags for applying NIP-65 outbox model
    /// Events with more than this number of p-tags should not send to all mentioned users' relays
    /// to avoid relay spam and excessive network usage
    public static let maxPTagsForOutboxModel = 10

    // MARK: - Display Limits

    /// Maximum number of items to display in filter descriptions before truncating with "..."
    public static let maxFilterDescriptionItems = 3

    /// Maximum number of tag values to display in filter descriptions before truncating with "..."
    public static let maxTagValuesInDescription = 2

    // MARK: - Relay Hints

    /// Minimum tag array size for relay hints (e.g., ["e", "eventId", "relayUrl"])
    public static let minTagSizeForRelayHint = 3

    /// Minimum tag array size for petnames in contact lists (e.g., ["p", "pubkey", "relay", "petname"])
    public static let minTagSizeForPetname = 4

    // MARK: - User Display

    /// Maximum pubkey length to display before truncating in user descriptions
    public static let maxPubkeyDisplayLength = 16

    // MARK: - Tag Validation

    /// Minimum tag array size for a valid tag (must have at least tag name and one value)
    public static let minValidTagSize = 2
}
