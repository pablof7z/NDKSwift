import Foundation

/// Thread-safe index for tracking relay hints.
/// Learns where users and events have been observed, enabling smarter relay selection.
public actor HintIndex {
    // MARK: - Storage

    private var pubkeyHints: [String: [HintEntry]] = [:]
    private var eventIdHints: [String: [HintEntry]] = [:]
    private var addressHints: [String: [HintEntry]] = [:]

    private let maxSize: Int
    private var totalEntries: Int = 0

    // MARK: - Initialization

    public init(maxSize: Int = 10000) {
        self.maxSize = maxSize
    }

    // MARK: - Recording Hints

    /// Record a relay hint for a pubkey
    public func recordHint(pubkey: String, relay: RelayURL, source: HintSource) {
        let normalizedRelay = relay.normalizedRelayURL
        let entry = HintEntry(relay: normalizedRelay, source: source)

        var hints = pubkeyHints[pubkey, default: []]

        // Check for duplicate (same relay + source)
        if hints.contains(where: { $0.relay == normalizedRelay && $0.source == source }) {
            return
        }

        hints.append(entry)
        pubkeyHints[pubkey] = hints
        totalEntries += 1

        evictIfNeeded()
    }

    /// Record a relay hint for an event ID
    public func recordHint(eventId: String, relay: RelayURL, source: HintSource) {
        let normalizedRelay = relay.normalizedRelayURL
        let entry = HintEntry(relay: normalizedRelay, source: source)

        var hints = eventIdHints[eventId, default: []]

        if hints.contains(where: { $0.relay == normalizedRelay && $0.source == source }) {
            return
        }

        hints.append(entry)
        eventIdHints[eventId] = hints
        totalEntries += 1

        evictIfNeeded()
    }

    /// Record a relay hint for an addressable event (kind:pubkey:d-tag)
    public func recordHint(address: String, relay: RelayURL, source: HintSource) {
        let normalizedRelay = relay.normalizedRelayURL
        let entry = HintEntry(relay: normalizedRelay, source: source)

        var hints = addressHints[address, default: []]

        if hints.contains(where: { $0.relay == normalizedRelay && $0.source == source }) {
            return
        }

        hints.append(entry)
        addressHints[address] = hints
        totalEntries += 1

        evictIfNeeded()
    }

    // MARK: - Retrieving Hints

    /// Get all hints for a pubkey
    public func hints(for pubkey: String) -> [HintEntry] {
        return pubkeyHints[pubkey] ?? []
    }

    /// Get all hints for an event ID
    public func hints(forEventId eventId: String) -> [HintEntry] {
        return eventIdHints[eventId] ?? []
    }

    /// Get all hints for an address
    public func hints(forAddress address: String) -> [HintEntry] {
        return addressHints[address] ?? []
    }

    /// Get unique relay URLs for a pubkey
    public func relayURLs(for pubkey: String) -> Set<RelayURL> {
        return Set(hints(for: pubkey).map { $0.relay })
    }

    /// Get unique relay URLs for an event ID
    public func relayURLs(forEventId eventId: String) -> Set<RelayURL> {
        return Set(hints(forEventId: eventId).map { $0.relay })
    }

    // MARK: - Statistics

    /// Total number of hint entries
    public var count: Int {
        return totalEntries
    }

    /// Number of unique pubkeys with hints
    public var pubkeyCount: Int {
        return pubkeyHints.count
    }

    /// Number of unique event IDs with hints
    public var eventIdCount: Int {
        return eventIdHints.count
    }

    /// Number of unique addresses with hints
    public var addressCount: Int {
        return addressHints.count
    }

    // MARK: - Management

    /// Clear all hints
    public func clear() {
        pubkeyHints.removeAll()
        eventIdHints.removeAll()
        addressHints.removeAll()
        totalEntries = 0
    }

    // MARK: - Private

    private func evictIfNeeded() {
        guard totalEntries > maxSize else { return }

        // Simple eviction: remove oldest entries from each map
        // Remove 10% buffer to avoid frequent evictions
        let evictCount = totalEntries - maxSize + (maxSize / 10)
        var evicted = 0

        // Evict from pubkey hints first (typically the largest)
        for (key, hints) in pubkeyHints {
            if evicted >= evictCount { break }
            if hints.count > 1 {
                pubkeyHints[key] = Array(hints.dropFirst())
                evicted += 1
                totalEntries -= 1
            }
        }

        // Then event hints
        for (key, hints) in eventIdHints {
            if evicted >= evictCount { break }
            if hints.count > 1 {
                eventIdHints[key] = Array(hints.dropFirst())
                evicted += 1
                totalEntries -= 1
            }
        }

        // Then address hints
        for (key, hints) in addressHints {
            if evicted >= evictCount { break }
            if hints.count > 1 {
                addressHints[key] = Array(hints.dropFirst())
                evicted += 1
                totalEntries -= 1
            }
        }
    }
}
