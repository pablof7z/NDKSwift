import Foundation

/// Protocol for cache adapters
public protocol NDKCacheAdapter: AnyObject {
    /// Whether this cache is fast enough to query before hitting relays
    var locking: Bool { get }

    /// Whether the cache is ready to use
    var ready: Bool { get }

    /// Query events from cache
    func query(subscription: NDKSubscription) async -> [NDKEvent]

    /// Store an event in cache
    func setEvent(_ event: NDKEvent, filters: [NDKFilter], relay: NDKRelay?) async

    /// Fetch a user profile from cache
    func fetchProfile(pubkey: PublicKey) async -> NDKUserProfile?

    /// Save a user profile to cache
    func saveProfile(pubkey: PublicKey, profile: NDKUserProfile) async

    /// Load NIP-05 verification data
    func loadNip05(_ nip05: String) async -> (pubkey: PublicKey, relays: [String])?

    /// Save NIP-05 verification data
    func saveNip05(_ nip05: String, pubkey: PublicKey, relays: [String]) async

    /// Update relay connection status
    func updateRelayStatus(_ url: RelayURL, status: NDKRelayConnectionState) async

    /// Get relay connection status
    func getRelayStatus(_ url: RelayURL) async -> NDKRelayConnectionState?

    /// Add an unpublished event (for retry logic)
    func addUnpublishedEvent(_ event: NDKEvent, relayUrls: [RelayURL]) async

    /// Get unpublished events for a relay
    func getUnpublishedEvents(for relayUrl: RelayURL) async -> [NDKEvent]

    /// Remove an unpublished event after successful publish
    func removeUnpublishedEvent(_ eventId: EventID, from relayUrl: RelayURL) async
}

/// Cache entry with metadata
public struct NDKCacheEntry<T> {
    public let value: T
    public let cachedAt: Date
    public let expiresAt: Date?

    public init(value: T, cachedAt: Date = Date(), expiresAt: Date? = nil) {
        self.value = value
        self.cachedAt = cachedAt
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
}
